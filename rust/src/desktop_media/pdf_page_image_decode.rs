use image::{DynamicImage, RgbImage};
use lopdf::{Dictionary, Document, Object, ObjectId, Stream};
use std::collections::HashSet;

#[derive(Clone, Copy, Debug)]
pub(super) struct PdfImageCandidate {
    pub object_id: ObjectId,
    pub width: i64,
    pub height: i64,
}

pub(super) fn collect_page_image_candidates(
    doc: &Document,
    page_id: ObjectId,
) -> Vec<PdfImageCandidate> {
    let mut out = Vec::<PdfImageCandidate>::new();
    let mut visited_xobjects = HashSet::<ObjectId>::new();
    let mut seen_images = HashSet::<ObjectId>::new();
    let mut seen_resource_refs = HashSet::<ObjectId>::new();

    if let Ok(page) = doc.get_dictionary(page_id) {
        if let Ok(resources_obj) = page.get(b"Resources") {
            collect_images_from_resources_object(
                doc,
                resources_obj,
                &mut visited_xobjects,
                &mut seen_images,
                &mut out,
            );
        }
    }

    if let Ok((resource_dict, resource_ids)) = doc.get_page_resources(page_id) {
        if let Some(resources) = resource_dict {
            collect_images_from_resources_dict(
                doc,
                resources,
                &mut visited_xobjects,
                &mut seen_images,
                &mut out,
            );
        }

        for resource_id in resource_ids {
            if !seen_resource_refs.insert(resource_id) {
                continue;
            }
            if let Ok(resource_obj) = doc.get_object(resource_id) {
                collect_images_from_resources_object(
                    doc,
                    resource_obj,
                    &mut visited_xobjects,
                    &mut seen_images,
                    &mut out,
                );
            }
        }
    }

    out
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(super) enum PdfImageDecodeFailureReason {
    InvalidDimensions,
    StreamUnavailable,
    UnsupportedColorSpace,
    UnsupportedBitsPerComponent,
    DecodeFailed,
}

pub(super) fn decode_pdf_image_to_rgb_with_reason(
    doc: &Document,
    candidate: PdfImageCandidate,
) -> Result<RgbImage, PdfImageDecodeFailureReason> {
    if candidate.width <= 0 || candidate.height <= 0 {
        return Err(PdfImageDecodeFailureReason::InvalidDimensions);
    }

    let width_u32 = u32::try_from(candidate.width)
        .map_err(|_| PdfImageDecodeFailureReason::InvalidDimensions)?;
    let height_u32 = u32::try_from(candidate.height)
        .map_err(|_| PdfImageDecodeFailureReason::InvalidDimensions)?;
    if width_u32 == 0 || height_u32 == 0 {
        return Err(PdfImageDecodeFailureReason::InvalidDimensions);
    }
    if width_u32 > 40_000 || height_u32 > 40_000 {
        return Err(PdfImageDecodeFailureReason::InvalidDimensions);
    }

    let stream = doc
        .get_object(candidate.object_id)
        .ok()
        .and_then(|o| o.as_stream().ok())
        .ok_or(PdfImageDecodeFailureReason::StreamUnavailable)?;

    let filters = stream
        .dict
        .get(b"Filter")
        .ok()
        .and_then(extract_filter_names)
        .unwrap_or_default();

    let has_encoded_filter = filters.iter().any(|f| f == "DCTDecode" || f == "JPXDecode");
    let decoded_stream_bytes = decode_image_stream_bytes(stream);
    if has_encoded_filter {
        if let Ok(decoded) = image::load_from_memory(&stream.content) {
            return Ok(decoded.to_rgb8());
        }
        if decoded_stream_bytes.as_slice() != stream.content.as_slice() {
            if let Ok(decoded) = image::load_from_memory(&decoded_stream_bytes) {
                return Ok(decoded.to_rgb8());
            }
        }
    }

    let bits_per_component = stream
        .dict
        .get(b"BitsPerComponent")
        .ok()
        .and_then(|v| v.as_i64().ok())
        .unwrap_or(8);

    let color_space = color_space_name(doc, &stream.dict);
    let raw = decoded_stream_bytes;

    let decoded = match color_space.as_deref() {
        Some("DeviceRGB") => {
            if bits_per_component != 8 {
                return Err(PdfImageDecodeFailureReason::UnsupportedBitsPerComponent);
            }
            decode_device_rgb_8bit(&raw, width_u32, height_u32)
        }
        Some("DeviceCMYK") => {
            if bits_per_component != 8 {
                return Err(PdfImageDecodeFailureReason::UnsupportedBitsPerComponent);
            }
            decode_device_cmyk_8bit(&raw, width_u32, height_u32)
        }
        Some("DeviceGray") => {
            let invert = is_gray_decode_inverted(&stream.dict);
            match bits_per_component {
                8 => decode_device_gray_8bit(&raw, width_u32, height_u32, invert),
                1 => decode_device_gray_1bit(&raw, width_u32, height_u32, invert),
                _ => return Err(PdfImageDecodeFailureReason::UnsupportedBitsPerComponent),
            }
        }
        _ => return Err(PdfImageDecodeFailureReason::UnsupportedColorSpace),
    };

    decoded.ok_or(PdfImageDecodeFailureReason::DecodeFailed)
}

fn collect_images_from_resources_object(
    doc: &Document,
    resources_obj: &Object,
    visited_xobjects: &mut HashSet<ObjectId>,
    seen_images: &mut HashSet<ObjectId>,
    out: &mut Vec<PdfImageCandidate>,
) {
    let Some(resources_dict) = resolve_dict_object(doc, resources_obj) else {
        return;
    };
    collect_images_from_resources_dict(doc, resources_dict, visited_xobjects, seen_images, out);
}

fn collect_images_from_resources_dict(
    doc: &Document,
    resources: &Dictionary,
    visited_xobjects: &mut HashSet<ObjectId>,
    seen_images: &mut HashSet<ObjectId>,
    out: &mut Vec<PdfImageCandidate>,
) {
    let Some(xobject_obj) = resources.get(b"XObject").ok() else {
        return;
    };
    let Some(xobject_dict) = resolve_dict_object(doc, xobject_obj) else {
        return;
    };

    for (_, xobject_value) in xobject_dict.iter() {
        let object_id = match xobject_value.as_reference() {
            Ok(id) => id,
            Err(_) => continue,
        };

        if !visited_xobjects.insert(object_id) {
            continue;
        }

        let stream = match doc.get_object(object_id).and_then(|o| o.as_stream()) {
            Ok(v) => v,
            Err(_) => continue,
        };
        let subtype = stream
            .dict
            .get(b"Subtype")
            .ok()
            .and_then(|v| v.as_name().ok());

        match subtype {
            Some(b"Image") => {
                if !seen_images.insert(object_id) {
                    continue;
                }
                let width = stream
                    .dict
                    .get(b"Width")
                    .ok()
                    .and_then(|v| v.as_i64().ok())
                    .unwrap_or(0);
                let height = stream
                    .dict
                    .get(b"Height")
                    .ok()
                    .and_then(|v| v.as_i64().ok())
                    .unwrap_or(0);
                if width > 0 && height > 0 {
                    out.push(PdfImageCandidate {
                        object_id,
                        width,
                        height,
                    });
                }
            }
            Some(b"Form") => {
                if let Ok(form_resources_obj) = stream.dict.get(b"Resources") {
                    collect_images_from_resources_object(
                        doc,
                        form_resources_obj,
                        visited_xobjects,
                        seen_images,
                        out,
                    );
                }
            }
            _ => {}
        }
    }
}

fn resolve_dict_object<'a>(doc: &'a Document, object: &'a Object) -> Option<&'a Dictionary> {
    match object {
        Object::Dictionary(dict) => Some(dict),
        Object::Reference(id) => doc.get_object(*id).ok().and_then(|o| o.as_dict().ok()),
        _ => None,
    }
}

fn decode_image_stream_bytes(stream: &Stream) -> Vec<u8> {
    // lopdf intentionally refuses `decompressed_content()` for `/Subtype /Image`.
    // Strip subtype on a cloned stream so filter-chain decoding still works.
    let mut candidate = stream.clone();
    candidate.dict.remove(b"Subtype");
    match candidate.decompressed_content() {
        Ok(bytes) => bytes,
        Err(_) => stream.content.clone(),
    }
}

fn extract_filter_names(value: &Object) -> Option<Vec<String>> {
    match value {
        Object::Name(name) => Some(vec![String::from_utf8_lossy(name).to_string()]),
        Object::Array(arr) => {
            let mut out = Vec::<String>::new();
            for item in arr {
                if let Ok(name) = item.as_name() {
                    out.push(String::from_utf8_lossy(name).to_string());
                }
            }
            Some(out)
        }
        _ => None,
    }
}

fn color_space_name(doc: &Document, dict: &Dictionary) -> Option<String> {
    let value = dict.get(b"ColorSpace").ok()?;
    color_space_name_from_object(doc, value)
}

fn color_space_name_from_object(doc: &Document, value: &Object) -> Option<String> {
    match value {
        Object::Name(name) => Some(normalize_pdf_name(name)),
        Object::Reference(id) => doc
            .get_object(*id)
            .ok()
            .and_then(|obj| color_space_name_from_object(doc, obj)),
        Object::Array(arr) => {
            let first_name = arr.first()?.as_name().ok()?;
            let first = normalize_pdf_name(first_name);
            if first == "ICCBased" {
                let channels = arr
                    .get(1)
                    .and_then(|profile| iccbased_channel_count(doc, profile));
                return match channels {
                    Some(1) => Some("DeviceGray".to_string()),
                    Some(3) => Some("DeviceRGB".to_string()),
                    Some(4) => Some("DeviceCMYK".to_string()),
                    _ => None,
                };
            }
            Some(first)
        }
        _ => None,
    }
}

fn iccbased_channel_count(doc: &Document, object: &Object) -> Option<i64> {
    match object {
        Object::Reference(id) => doc
            .get_object(*id)
            .ok()
            .and_then(|obj| iccbased_channel_count(doc, obj)),
        Object::Stream(stream) => stream.dict.get(b"N").ok().and_then(|v| v.as_i64().ok()),
        Object::Dictionary(dict) => dict.get(b"N").ok().and_then(|v| v.as_i64().ok()),
        _ => None,
    }
}

fn normalize_pdf_name(name: &[u8]) -> String {
    let raw = String::from_utf8_lossy(name);
    raw.strip_prefix('/').unwrap_or(&raw).to_string()
}

fn is_gray_decode_inverted(dict: &Dictionary) -> bool {
    let decode = match dict.get(b"Decode").ok().and_then(|v| v.as_array().ok()) {
        Some(v) if v.len() >= 2 => v,
        _ => return false,
    };
    let first = match decode.first().and_then(|v| v.as_float().ok()) {
        Some(v) => v,
        None => return false,
    };
    let second = match decode.get(1).and_then(|v| v.as_float().ok()) {
        Some(v) => v,
        None => return false,
    };
    first > second
}

fn decode_device_rgb_8bit(raw: &[u8], width: u32, height: u32) -> Option<RgbImage> {
    let pixel_count = usize::try_from(width)
        .ok()?
        .saturating_mul(usize::try_from(height).ok()?);
    let expected = pixel_count.saturating_mul(3);
    if raw.len() < expected {
        return None;
    }
    RgbImage::from_raw(width, height, raw[..expected].to_vec())
}

fn decode_device_cmyk_8bit(raw: &[u8], width: u32, height: u32) -> Option<RgbImage> {
    let pixel_count = usize::try_from(width)
        .ok()?
        .saturating_mul(usize::try_from(height).ok()?);
    let expected = pixel_count.saturating_mul(4);
    if raw.len() < expected {
        return None;
    }

    let mut rgb = Vec::<u8>::with_capacity(pixel_count.saturating_mul(3));
    for chunk in raw[..expected].chunks_exact(4) {
        let c = u16::from(chunk[0]);
        let m = u16::from(chunk[1]);
        let y = u16::from(chunk[2]);
        let k = u16::from(chunk[3]);
        let inv_k = 255u16.saturating_sub(k);
        let r = ((255u16.saturating_sub(c)).saturating_mul(inv_k) + 127) / 255;
        let g = ((255u16.saturating_sub(m)).saturating_mul(inv_k) + 127) / 255;
        let b = ((255u16.saturating_sub(y)).saturating_mul(inv_k) + 127) / 255;
        rgb.push(u8::try_from(r).unwrap_or(0));
        rgb.push(u8::try_from(g).unwrap_or(0));
        rgb.push(u8::try_from(b).unwrap_or(0));
    }

    RgbImage::from_raw(width, height, rgb)
}

fn decode_device_gray_8bit(raw: &[u8], width: u32, height: u32, invert: bool) -> Option<RgbImage> {
    let pixel_count = usize::try_from(width)
        .ok()?
        .saturating_mul(usize::try_from(height).ok()?);
    if raw.len() < pixel_count {
        return None;
    }

    let mut gray = raw[..pixel_count].to_vec();
    if invert {
        for value in &mut gray {
            *value = 255u8.saturating_sub(*value);
        }
    }
    let luma = image::GrayImage::from_raw(width, height, gray)?;
    Some(DynamicImage::ImageLuma8(luma).to_rgb8())
}

fn decode_device_gray_1bit(raw: &[u8], width: u32, height: u32, invert: bool) -> Option<RgbImage> {
    let width_usize = usize::try_from(width).ok()?;
    let height_usize = usize::try_from(height).ok()?;
    let row_bytes = width_usize.div_ceil(8);
    let expected = row_bytes.saturating_mul(height_usize);
    if raw.len() < expected {
        return None;
    }

    let mut rgb =
        Vec::<u8>::with_capacity(width_usize.saturating_mul(height_usize).saturating_mul(3));
    for y in 0..height_usize {
        let row_start = y.saturating_mul(row_bytes);
        for x in 0..width_usize {
            let byte = raw[row_start + (x / 8)];
            let bit_index = 7u8.saturating_sub((x % 8) as u8);
            let bit_set = ((byte >> bit_index) & 1) == 1;
            let mut value = if bit_set { 255u8 } else { 0u8 };
            if invert {
                value = 255u8.saturating_sub(value);
            }
            rgb.push(value);
            rgb.push(value);
            rgb.push(value);
        }
    }

    RgbImage::from_raw(width, height, rgb)
}

#[cfg(test)]
mod tests {
    use super::*;
    use lopdf::{Object, Stream};

    #[test]
    fn decode_device_gray_1bit_supports_tight_rows() {
        let raw = [0b1010_0000u8];
        let rgb = decode_device_gray_1bit(&raw, 4, 1, false).expect("decode 1-bit gray");
        assert_eq!(rgb.width(), 4);
        assert_eq!(rgb.height(), 1);
        assert_eq!(rgb.get_pixel(0, 0).0, [255, 255, 255]);
        assert_eq!(rgb.get_pixel(1, 0).0, [0, 0, 0]);
        assert_eq!(rgb.get_pixel(2, 0).0, [255, 255, 255]);
        assert_eq!(rgb.get_pixel(3, 0).0, [0, 0, 0]);
    }

    #[test]
    fn decode_device_gray_1bit_honors_invert() {
        let raw = [0b1010_0000u8];
        let rgb = decode_device_gray_1bit(&raw, 4, 1, true).expect("decode inverted 1-bit gray");
        assert_eq!(rgb.get_pixel(0, 0).0, [0, 0, 0]);
        assert_eq!(rgb.get_pixel(1, 0).0, [255, 255, 255]);
        assert_eq!(rgb.get_pixel(2, 0).0, [0, 0, 0]);
        assert_eq!(rgb.get_pixel(3, 0).0, [255, 255, 255]);
    }

    #[test]
    fn decode_pdf_image_to_rgb_supports_flate_encoded_image_stream() {
        let mut doc = Document::new();
        let image_id: ObjectId = (20, 0);

        let width = 10i64;
        let height = 10i64;
        let raw = vec![137u8; usize::try_from(width * height).expect("raw size")];

        let mut image_dict = Dictionary::new();
        image_dict.set("Subtype", Object::Name(b"Image".to_vec()));
        image_dict.set("Width", Object::Integer(width));
        image_dict.set("Height", Object::Integer(height));
        image_dict.set("ColorSpace", Object::Name(b"DeviceGray".to_vec()));
        image_dict.set("BitsPerComponent", Object::Integer(8));

        let mut stream = Stream::new(image_dict, raw);
        stream.compress().expect("compress image stream");
        assert!(stream.dict.get(b"Filter").is_ok());
        doc.objects.insert(image_id, Object::Stream(stream));

        let rgb = decode_pdf_image_to_rgb_with_reason(
            &doc,
            PdfImageCandidate {
                object_id: image_id,
                width,
                height,
            },
        )
        .expect("decode compressed image stream");
        assert_eq!(rgb.width(), 10);
        assert_eq!(rgb.height(), 10);
        assert_eq!(rgb.get_pixel(0, 0).0, [137, 137, 137]);
    }

    #[test]
    fn collect_page_image_candidates_walks_form_xobjects() {
        let mut doc = Document::new();

        let page_id: ObjectId = (1, 0);
        let form_id: ObjectId = (2, 0);
        let image_id: ObjectId = (3, 0);

        let mut image_dict = Dictionary::new();
        image_dict.set("Subtype", Object::Name(b"Image".to_vec()));
        image_dict.set("Width", Object::Integer(120));
        image_dict.set("Height", Object::Integer(80));
        doc.objects
            .insert(image_id, Object::Stream(Stream::new(image_dict, vec![])));

        let mut form_xobjects = Dictionary::new();
        form_xobjects.set("Im1", Object::Reference(image_id));
        let mut form_resources = Dictionary::new();
        form_resources.set("XObject", Object::Dictionary(form_xobjects));

        let mut form_dict = Dictionary::new();
        form_dict.set("Subtype", Object::Name(b"Form".to_vec()));
        form_dict.set("Resources", Object::Dictionary(form_resources));
        doc.objects
            .insert(form_id, Object::Stream(Stream::new(form_dict, vec![])));

        let mut page_xobjects = Dictionary::new();
        page_xobjects.set("Fm1", Object::Reference(form_id));
        let mut page_resources = Dictionary::new();
        page_resources.set("XObject", Object::Dictionary(page_xobjects));

        let mut page = Dictionary::new();
        page.set("Type", Object::Name(b"Page".to_vec()));
        page.set("Resources", Object::Dictionary(page_resources));
        doc.objects.insert(page_id, Object::Dictionary(page));

        let candidates = collect_page_image_candidates(&doc, page_id);
        assert_eq!(candidates.len(), 1);
        assert_eq!(candidates[0].object_id, image_id);
        assert_eq!(candidates[0].width, 120);
        assert_eq!(candidates[0].height, 80);
    }

    #[test]
    fn decode_pdf_image_to_rgb_supports_iccbased_rgb_stream() {
        let mut doc = Document::new();
        let image_id: ObjectId = (30, 0);
        let profile_id: ObjectId = (31, 0);

        let mut profile_dict = Dictionary::new();
        profile_dict.set("N", Object::Integer(3));
        doc.objects.insert(
            profile_id,
            Object::Stream(Stream::new(profile_dict, vec![])),
        );

        let width = 1i64;
        let height = 1i64;
        let raw = vec![12u8, 34u8, 56u8];

        let mut image_dict = Dictionary::new();
        image_dict.set("Subtype", Object::Name(b"Image".to_vec()));
        image_dict.set("Width", Object::Integer(width));
        image_dict.set("Height", Object::Integer(height));
        image_dict.set(
            "ColorSpace",
            Object::Array(vec![
                Object::Name(b"ICCBased".to_vec()),
                Object::Reference(profile_id),
            ]),
        );
        image_dict.set("BitsPerComponent", Object::Integer(8));

        doc.objects
            .insert(image_id, Object::Stream(Stream::new(image_dict, raw)));

        let rgb = decode_pdf_image_to_rgb_with_reason(
            &doc,
            PdfImageCandidate {
                object_id: image_id,
                width,
                height,
            },
        )
        .expect("decode ICCBased rgb image stream");

        assert_eq!(rgb.width(), 1);
        assert_eq!(rgb.height(), 1);
        assert_eq!(rgb.get_pixel(0, 0).0, [12, 34, 56]);
    }

    #[test]
    fn collect_page_image_candidates_includes_parent_resource_chain() {
        let mut doc = Document::new();

        let page_id: ObjectId = (10, 0);
        let parent_id: ObjectId = (11, 0);
        let resources_id: ObjectId = (12, 0);
        let image_id: ObjectId = (13, 0);

        let mut image_dict = Dictionary::new();
        image_dict.set("Subtype", Object::Name(b"Image".to_vec()));
        image_dict.set("Width", Object::Integer(64));
        image_dict.set("Height", Object::Integer(64));
        doc.objects
            .insert(image_id, Object::Stream(Stream::new(image_dict, vec![])));

        let mut xobjects = Dictionary::new();
        xobjects.set("ImParent", Object::Reference(image_id));
        let mut resources = Dictionary::new();
        resources.set("XObject", Object::Dictionary(xobjects));
        doc.objects
            .insert(resources_id, Object::Dictionary(resources));

        let mut parent = Dictionary::new();
        parent.set("Resources", Object::Reference(resources_id));
        doc.objects.insert(parent_id, Object::Dictionary(parent));

        let mut page = Dictionary::new();
        page.set("Type", Object::Name(b"Page".to_vec()));
        page.set("Parent", Object::Reference(parent_id));
        doc.objects.insert(page_id, Object::Dictionary(page));

        let candidates = collect_page_image_candidates(&doc, page_id);
        assert_eq!(candidates.len(), 1);
        assert_eq!(candidates[0].object_id, image_id);
    }
}

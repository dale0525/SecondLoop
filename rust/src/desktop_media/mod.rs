pub mod ocr;
#[cfg(any(target_os = "windows", target_os = "macos", target_os = "linux"))]
mod pdf_page_image_decode;

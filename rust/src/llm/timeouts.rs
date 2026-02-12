use std::time::Duration;

const ASK_AI_TIMEOUT_MIN_SECONDS: u64 = 180;
const ASK_AI_TIMEOUT_MAX_SECONDS: u64 = 900;
const ASK_AI_TIMEOUT_CHARS_PER_SECOND: u64 = 250;

const MEDIA_TIMEOUT_MIN_SECONDS: u64 = 300;
const MEDIA_TIMEOUT_MAX_SECONDS: u64 = 1200;
const MEDIA_TIMEOUT_BASE_SECONDS: u64 = 240;
const MEDIA_TIMEOUT_SECONDS_PER_MIB: u64 = 90;
const MEDIA_TIMEOUT_OCR_BONUS_SECONDS: u64 = 180;

const AUDIO_TIMEOUT_MIN_SECONDS: u64 = 240;
const AUDIO_TIMEOUT_MAX_SECONDS: u64 = 900;
const AUDIO_TIMEOUT_BASE_SECONDS: u64 = 180;
const AUDIO_TIMEOUT_SECONDS_PER_MIB: u64 = 75;
const AUDIO_TIMEOUT_MULTIMODAL_BONUS_SECONDS: u64 = 180;

const BYTES_PER_MIB: u64 = 1024 * 1024;

fn clamp_timeout_seconds(seconds: u64, min_seconds: u64, max_seconds: u64) -> u64 {
    seconds.clamp(min_seconds, max_seconds)
}

fn ceil_mib(bytes: usize) -> u64 {
    let bytes_u64 = u64::try_from(bytes).unwrap_or(u64::MAX);
    bytes_u64.saturating_add(BYTES_PER_MIB - 1) / BYTES_PER_MIB
}

pub fn ask_ai_timeout_for_prompt_chars(prompt_chars: usize) -> Duration {
    let prompt_chars_u64 = u64::try_from(prompt_chars).unwrap_or(u64::MAX);
    let adaptive_seconds = ASK_AI_TIMEOUT_MIN_SECONDS
        .saturating_add(prompt_chars_u64 / ASK_AI_TIMEOUT_CHARS_PER_SECOND);

    Duration::from_secs(clamp_timeout_seconds(
        adaptive_seconds,
        ASK_AI_TIMEOUT_MIN_SECONDS,
        ASK_AI_TIMEOUT_MAX_SECONDS,
    ))
}

pub fn media_annotation_timeout_for_image_bytes(
    image_bytes: usize,
    ocr_markdown: bool,
) -> Duration {
    let size_mib = ceil_mib(image_bytes);
    let ocr_bonus = if ocr_markdown {
        MEDIA_TIMEOUT_OCR_BONUS_SECONDS
    } else {
        0
    };
    let adaptive_seconds = MEDIA_TIMEOUT_BASE_SECONDS
        .saturating_add(size_mib.saturating_mul(MEDIA_TIMEOUT_SECONDS_PER_MIB))
        .saturating_add(ocr_bonus);

    Duration::from_secs(clamp_timeout_seconds(
        adaptive_seconds,
        MEDIA_TIMEOUT_MIN_SECONDS,
        MEDIA_TIMEOUT_MAX_SECONDS,
    ))
}

pub fn audio_transcribe_timeout_for_audio_bytes(audio_bytes: usize, multimodal: bool) -> Duration {
    let size_mib = ceil_mib(audio_bytes);
    let multimodal_bonus = if multimodal {
        AUDIO_TIMEOUT_MULTIMODAL_BONUS_SECONDS
    } else {
        0
    };
    let adaptive_seconds = AUDIO_TIMEOUT_BASE_SECONDS
        .saturating_add(size_mib.saturating_mul(AUDIO_TIMEOUT_SECONDS_PER_MIB))
        .saturating_add(multimodal_bonus);

    Duration::from_secs(clamp_timeout_seconds(
        adaptive_seconds,
        AUDIO_TIMEOUT_MIN_SECONDS,
        AUDIO_TIMEOUT_MAX_SECONDS,
    ))
}

#[cfg(test)]
mod tests {
    use super::{
        ask_ai_timeout_for_prompt_chars, audio_transcribe_timeout_for_audio_bytes,
        media_annotation_timeout_for_image_bytes,
    };

    #[test]
    fn ask_ai_timeout_scales_with_prompt_size() {
        assert_eq!(ask_ai_timeout_for_prompt_chars(4_000).as_secs(), 196);
        assert_eq!(ask_ai_timeout_for_prompt_chars(32_000).as_secs(), 308);
        assert_eq!(ask_ai_timeout_for_prompt_chars(180_000).as_secs(), 900);
        assert_eq!(ask_ai_timeout_for_prompt_chars(320_000).as_secs(), 900);
    }

    #[test]
    fn media_timeout_scales_with_payload_and_ocr_mode() {
        assert_eq!(
            media_annotation_timeout_for_image_bytes(200_000, false).as_secs(),
            330
        );
        assert_eq!(
            media_annotation_timeout_for_image_bytes(2_000_000, false).as_secs(),
            420
        );
        assert_eq!(
            media_annotation_timeout_for_image_bytes(300_000, true).as_secs(),
            510
        );
        assert_eq!(
            media_annotation_timeout_for_image_bytes(20 * 1024 * 1024, true).as_secs(),
            1200
        );
    }

    #[test]
    fn audio_timeout_scales_with_payload_and_multimodal_mode() {
        assert_eq!(
            audio_transcribe_timeout_for_audio_bytes(500_000, false).as_secs(),
            255
        );
        assert_eq!(
            audio_transcribe_timeout_for_audio_bytes(8_000_000, false).as_secs(),
            780
        );
        assert_eq!(
            audio_transcribe_timeout_for_audio_bytes(800_000, true).as_secs(),
            435
        );
        assert_eq!(
            audio_transcribe_timeout_for_audio_bytes(40 * 1024 * 1024, true).as_secs(),
            900
        );
    }
}

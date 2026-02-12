use std::time::Duration;

const ASK_AI_TIMEOUT_BASE_SECONDS: u64 = 180;
const ASK_AI_TIMEOUT_LONG_SECONDS: u64 = 420;
const ASK_AI_TIMEOUT_EXTENDED_SECONDS: u64 = 720;

const MEDIA_TIMEOUT_BASE_SECONDS: u64 = 300;
const MEDIA_TIMEOUT_LONG_SECONDS: u64 = 540;
const MEDIA_TIMEOUT_EXTENDED_SECONDS: u64 = 900;

const AUDIO_TIMEOUT_BASE_SECONDS: u64 = 240;
const AUDIO_TIMEOUT_LONG_SECONDS: u64 = 600;
const AUDIO_TIMEOUT_EXTENDED_SECONDS: u64 = 900;

pub fn ask_ai_timeout_for_prompt_chars(prompt_chars: usize) -> Duration {
    let seconds = if prompt_chars >= 120_000 {
        ASK_AI_TIMEOUT_EXTENDED_SECONDS
    } else if prompt_chars >= 32_000 {
        ASK_AI_TIMEOUT_LONG_SECONDS
    } else {
        ASK_AI_TIMEOUT_BASE_SECONDS
    };
    Duration::from_secs(seconds)
}

pub fn media_annotation_timeout_for_image_bytes(
    image_bytes: usize,
    ocr_markdown: bool,
) -> Duration {
    let seconds = if image_bytes >= 4 * 1024 * 1024 || ocr_markdown {
        MEDIA_TIMEOUT_EXTENDED_SECONDS
    } else if image_bytes >= 1 * 1024 * 1024 {
        MEDIA_TIMEOUT_LONG_SECONDS
    } else {
        MEDIA_TIMEOUT_BASE_SECONDS
    };
    Duration::from_secs(seconds)
}

pub fn audio_transcribe_timeout_for_audio_bytes(audio_bytes: usize, multimodal: bool) -> Duration {
    let seconds = if audio_bytes >= 20 * 1024 * 1024 || multimodal {
        AUDIO_TIMEOUT_EXTENDED_SECONDS
    } else if audio_bytes >= 5 * 1024 * 1024 {
        AUDIO_TIMEOUT_LONG_SECONDS
    } else {
        AUDIO_TIMEOUT_BASE_SECONDS
    };
    Duration::from_secs(seconds)
}

#[cfg(test)]
mod tests {
    use super::{
        ask_ai_timeout_for_prompt_chars, audio_transcribe_timeout_for_audio_bytes,
        media_annotation_timeout_for_image_bytes,
    };

    #[test]
    fn ask_ai_timeout_scales_with_prompt_size() {
        assert_eq!(ask_ai_timeout_for_prompt_chars(4_000).as_secs(), 180);
        assert_eq!(ask_ai_timeout_for_prompt_chars(32_000).as_secs(), 420);
        assert_eq!(ask_ai_timeout_for_prompt_chars(180_000).as_secs(), 720);
    }

    #[test]
    fn media_timeout_scales_with_payload_and_ocr_mode() {
        assert_eq!(
            media_annotation_timeout_for_image_bytes(200_000, false).as_secs(),
            300
        );
        assert_eq!(
            media_annotation_timeout_for_image_bytes(2_000_000, false).as_secs(),
            540
        );
        assert_eq!(
            media_annotation_timeout_for_image_bytes(300_000, true).as_secs(),
            900
        );
    }

    #[test]
    fn audio_timeout_scales_with_payload_and_multimodal_mode() {
        assert_eq!(
            audio_transcribe_timeout_for_audio_bytes(500_000, false).as_secs(),
            240
        );
        assert_eq!(
            audio_transcribe_timeout_for_audio_bytes(8_000_000, false).as_secs(),
            600
        );
        assert_eq!(
            audio_transcribe_timeout_for_audio_bytes(800_000, true).as_secs(),
            900
        );
    }
}

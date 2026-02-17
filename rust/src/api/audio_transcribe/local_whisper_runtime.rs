use anyhow::{anyhow, Result};

pub(super) fn local_whisper_context_use_gpu_attempts() -> Vec<bool> {
    if cfg!(any(
        target_os = "macos",
        target_os = "windows",
        target_os = "linux"
    )) {
        vec![true, false]
    } else {
        vec![false]
    }
}

pub(super) fn build_local_whisper_context_parameters(
    use_gpu: bool,
) -> whisper_rs::WhisperContextParameters<'static> {
    let mut context_params = whisper_rs::WhisperContextParameters::default();
    context_params.use_gpu(use_gpu);
    context_params.gpu_device(0);
    context_params
}

pub(super) fn create_local_whisper_context(model_path: &str) -> Result<whisper_rs::WhisperContext> {
    let mut gpu_load_error: Option<String> = None;

    for use_gpu in local_whisper_context_use_gpu_attempts() {
        let context_params = build_local_whisper_context_parameters(use_gpu);
        match whisper_rs::WhisperContext::new_with_params(model_path, context_params) {
            Ok(context) => return Ok(context),
            Err(err) if use_gpu => {
                gpu_load_error = Some(err.to_string());
                continue;
            }
            Err(err) => {
                if let Some(gpu_error) = gpu_load_error {
                    return Err(anyhow!(
                        "audio_transcribe_local_runtime_load_model_failed:gpu:{gpu_error};cpu:{err}"
                    ));
                }
                return Err(anyhow!(
                    "audio_transcribe_local_runtime_load_model_failed:{err}"
                ));
            }
        }
    }

    Err(anyhow!(
        "audio_transcribe_local_runtime_load_model_failed:no_attempt"
    ))
}

#[cfg(test)]
mod tests {
    use super::{build_local_whisper_context_parameters, local_whisper_context_use_gpu_attempts};

    #[test]
    fn build_local_whisper_context_parameters_respects_use_gpu_input() {
        let gpu_params = build_local_whisper_context_parameters(true);
        let cpu_params = build_local_whisper_context_parameters(false);

        assert!(gpu_params.use_gpu);
        assert_eq!(gpu_params.gpu_device, 0);

        assert!(!cpu_params.use_gpu);
        assert_eq!(cpu_params.gpu_device, 0);
    }

    #[test]
    fn local_whisper_context_use_gpu_attempts_match_platform_policy() {
        let attempts = local_whisper_context_use_gpu_attempts();
        #[cfg(any(target_os = "macos", target_os = "windows", target_os = "linux"))]
        {
            assert_eq!(attempts, vec![true, false]);
        }
        #[cfg(not(any(target_os = "macos", target_os = "windows", target_os = "linux")))]
        {
            assert_eq!(attempts, vec![false]);
        }
    }
}

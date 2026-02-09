enum AudioRecordingDispatch {
  transcribeAsText,
  sendAsAudioFile,
}

const Duration kAudioRecordingTranscribeThreshold = Duration(seconds: 30);

AudioRecordingDispatch decideAudioRecordingDispatch(
  Duration duration,
) {
  if (duration < kAudioRecordingTranscribeThreshold) {
    return AudioRecordingDispatch.transcribeAsText;
  }
  return AudioRecordingDispatch.sendAsAudioFile;
}

import 'dart:convert';

const _kTodoFollowupEnvelopeTag = 'secondloop_todo_followup';

String encodeTodoFollowupPromptEnvelope(
  String prompt, {
  required String generationModeWireValue,
}) {
  final metadata = jsonEncode(<String, String>{
    'generation_mode': generationModeWireValue.trim(),
  });
  return '<$_kTodoFollowupEnvelopeTag>$metadata</$_kTodoFollowupEnvelopeTag>\n${prompt.trim()}';
}

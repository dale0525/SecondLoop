import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:secondloop/web_app/web_app_service.dart';

void main() {
  test('WebAppServiceHttp reads and writes task priority assessments',
      () async {
    final client = _RecordingClient();
    final service = WebAppServiceHttp(client: client);

    final fetched = await service.fetchTaskPriorityAssessments(
      idToken: 'token-1',
      scope: 'scope-1',
    );

    expect(fetched['scope'], 'scope-1');
    expect((fetched['entries'] as List).single['todo_id'], 'focus');

    await service.upsertTaskPriorityAssessments(
      idToken: 'token-1',
      payload: <String, Object?>{
        'scope': 'scope-1',
        'entries': <Object?>[
          <String, Object?>{
            'todo_id': 'focus',
            'semantic_adjustment': 12,
            'reason': 'write back',
            'confidence': 'high',
            'request_signature': 'sig-1',
            'computed_at_ms': 1710000000000,
          },
        ],
      },
    );

    expect(client.requests, hasLength(2));
    expect(client.requests.first.method, 'GET');
    expect(
        client.requests.first.url.path, '/api/app/task-priority/assessments');
    expect(client.requests.first.url.queryParameters['scope'], 'scope-1');
    expect(client.requests.last.method, 'POST');
    expect(client.requests.last.url.path, '/api/app/task-priority/assessments');
    expect(jsonDecode(client.requests.last.body!)['scope'], 'scope-1');
  });
}

final class _RecordingClient extends http.BaseClient {
  final List<_RecordedRequest> requests = <_RecordedRequest>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    String? body;
    if (request is http.Request) {
      body = request.body;
    }
    requests.add(_RecordedRequest(request.method, request.url, body));
    if (request.method == 'GET') {
      return http.StreamedResponse(
        Stream<List<int>>.value(
          utf8.encode(jsonEncode(<String, Object?>{
            'scope': request.url.queryParameters['scope'],
            'entries': <Object?>[
              <String, Object?>{
                'todo_id': 'focus',
                'semantic_adjustment': 18,
                'reason': 'server cached',
                'confidence': 'high',
                'request_signature': 'sig-1',
                'computed_at_ms': 1710000000000,
              },
            ],
          })),
        ),
        200,
        headers: const <String, String>{'content-type': 'application/json'},
      );
    }
    return http.StreamedResponse(
      Stream<List<int>>.value(utf8.encode('{"ok":true}')),
      200,
      headers: const <String, String>{'content-type': 'application/json'},
    );
  }
}

final class _RecordedRequest {
  const _RecordedRequest(this.method, this.url, this.body);

  final String method;
  final Uri url;
  final String? body;
}

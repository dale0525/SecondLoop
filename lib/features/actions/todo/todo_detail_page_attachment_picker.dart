part of 'todo_detail_page.dart';

Future<void> _pickTodoDetailAttachment(_TodoDetailPageState state) async {
  final backend = AppBackendScope.of(state.context);
  if (backend is! AttachmentsBackend) return;
  final attachmentsBackend = backend as AttachmentsBackend;
  final sessionKey = SessionScope.of(state.context).sessionKey;

  final selected = await showModalBottomSheet<Attachment>(
    context: state.context,
    showDragHandle: true,
    builder: (context) {
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.t.actions.todoDetail.pickAttachment,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 12),
              FutureBuilder<List<Attachment>>(
                future: attachmentsBackend.listRecentAttachments(
                  sessionKey,
                  limit: 50,
                ),
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Padding(
                      padding: EdgeInsets.all(16),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }
                  if (snapshot.hasError) {
                    return Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        context.t.errors.loadFailed(error: '${snapshot.error}'),
                      ),
                    );
                  }

                  final items = snapshot.data ?? const <Attachment>[];
                  if (items.isEmpty) {
                    return Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(context.t.actions.todoDetail.noAttachments),
                    );
                  }

                  return SingleChildScrollView(
                    child: Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final attachment in items)
                          AttachmentCard(
                            attachment: attachment,
                            onTap: () => Navigator.of(context).pop(attachment),
                          ),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      );
    },
  );
  if (!state.mounted) return;
  if (selected == null) return;

  state._appendPendingAttachment(selected);
}

import 'package:flutter/material.dart';

import '../../core/cloud/self_managed_setup_controller.dart';
import '../../core/cloud/self_managed_setup_models.dart';
import '../../i18n/strings.g.dart';
import 'self_managed_setup_sections.dart';

class SelfManagedSetupPage extends StatefulWidget {
  const SelfManagedSetupPage({
    super.key,
    this.controller,
  });

  final SelfManagedSetupController? controller;

  @override
  State<SelfManagedSetupPage> createState() => _SelfManagedSetupPageState();
}

class _SelfManagedSetupPageState extends State<SelfManagedSetupPage> {
  late final SelfManagedSetupController _controller;
  final _cloudflareAccountController = TextEditingController();
  final _providerController = TextEditingController(text: 'openai');
  final _apiKeyController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _controller = widget.controller ?? SelfManagedSetupController();
  }

  @override
  void dispose() {
    _cloudflareAccountController.dispose();
    _providerController.dispose();
    _apiKeyController.dispose();
    if (widget.controller == null) {
      _controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const ValueKey('self_managed_setup_root'),
      appBar: AppBar(
        title: Text(context.t.settings.selfManagedSetup.title),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(context.t.settings.selfManagedSetup.subtitle),
            const SizedBox(height: 16),
            SelfManagedSetupSections(
              controller: _controller,
              cloudflareAccountController: _cloudflareAccountController,
              providerController: _providerController,
              apiKeyController: _apiKeyController,
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                OutlinedButton(
                  key: const ValueKey('self_managed_authorize'),
                  onPressed: _controller.beginCloudflareAuthorization,
                  child: Text(
                      context.t.settings.selfManagedSetup.actions.authorize),
                ),
                FilledButton(
                  key: const ValueKey('self_managed_deploy'),
                  onPressed: () {
                    _controller.deploy(
                      SelfManagedSetupRequest(
                        cloudflareAccountLabel:
                            _cloudflareAccountController.text,
                        provider: _providerController.text,
                        apiKey: _apiKeyController.text,
                      ),
                    );
                  },
                  child:
                      Text(context.t.settings.selfManagedSetup.actions.deploy),
                ),
                TextButton(
                  key: const ValueKey('self_managed_retry'),
                  onPressed: () {
                    _controller.deploy(
                      SelfManagedSetupRequest(
                        cloudflareAccountLabel:
                            _cloudflareAccountController.text,
                        provider: _providerController.text,
                        apiKey: _apiKeyController.text,
                      ),
                    );
                  },
                  child:
                      Text(context.t.settings.selfManagedSetup.actions.retry),
                ),
                TextButton(
                  key: const ValueKey('self_managed_reset'),
                  onPressed: _controller.reset,
                  child:
                      Text(context.t.settings.selfManagedSetup.actions.reset),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

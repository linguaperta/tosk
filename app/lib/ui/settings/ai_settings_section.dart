import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ai/ai_config.dart';
import '../../ai/ai_errors.dart';
import '../../ai/llm_explainer.dart';
import '../../providers.dart';
import 'app_settings.dart' show languageName;

/// Settings → "AI explanations": provider, API key (secure storage), model,
/// base URL (OpenAI-compatible), reply language and "Test connection".
/// Without a provider and key the explain buttons don't exist anywhere.
class AiSettingsSection extends ConsumerStatefulWidget {
  const AiSettingsSection({super.key});

  @override
  ConsumerState<AiSettingsSection> createState() => _AiSettingsSectionState();
}

enum _Test { idle, running, ok, failed }

class _AiSettingsSectionState extends ConsumerState<AiSettingsSection> {
  final _key = TextEditingController();
  final _model = TextEditingController();
  final _baseUrl = TextEditingController();
  bool _loaded = false;
  bool _showKey = false;
  _Test _test = _Test.idle;
  String? _testMessage;

  @override
  void dispose() {
    _key.dispose();
    _model.dispose();
    _baseUrl.dispose();
    super.dispose();
  }

  void _fill(AiConfig c) {
    _key.text = c.apiKey;
    _model.text = c.model;
    _baseUrl.text = c.baseUrl;
    _loaded = true;
  }

  /// Saves the text fields (key, model, base URL).
  Future<void> _commit() => ref
      .read(aiConfigProvider.notifier)
      .change((c) => c.copyWith(apiKey: _key.text.trim(), model: _model.text.trim(), baseUrl: _baseUrl.text.trim()));

  Future<void> _testConnection() async {
    await _commit();
    final config = ref.read(aiConfigProvider).value;
    setState(() {
      _test = _Test.running;
      _testMessage = null;
    });
    final llm = config == null ? null : llmExplainerFor(config, ref.read(httpClientProvider), browser: kIsWeb);
    if (llm == null) {
      setState(() {
        _test = _Test.failed;
        _testMessage = 'Fill in the API key (and the base URL and model for a compatible server) first.';
      });
      return;
    }
    try {
      await llm.testConnection();
      if (mounted) {
        setState(() {
          _test = _Test.ok;
          _testMessage = 'Connected to ${llm.model}.';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _test = _Test.failed;
          _testMessage = e is AiException ? e.userMessage : 'Connection failed.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final async = ref.watch(aiConfigProvider);
    final config = async.value;
    if (config == null) {
      return const Padding(padding: EdgeInsets.all(16), child: LinearProgressIndicator());
    }
    if (!_loaded) _fill(config);
    final ctl = ref.read(aiConfigProvider.notifier);
    final p = config.provider;
    final source = ref.watch(sourceLangProvider);
    final muted = theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant);

    Widget field(Widget child) => Padding(padding: const EdgeInsets.fromLTRB(16, 6, 16, 6), child: child);

    return Column(
      key: const ValueKey('ai-settings'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
          child: Text(
            'Explain any checked answer with an AI model, using your own API key. Replies are cached on this '
            'device, so they also work offline later.',
            style: muted,
          ),
        ),
        field(
          DropdownButtonFormField<AiProvider>(
            key: const ValueKey('ai-provider'),
            initialValue: p,
            isExpanded: true,
            decoration: const InputDecoration(labelText: 'Provider', border: OutlineInputBorder()),
            items: [
              for (final v in AiProvider.values)
                DropdownMenuItem(value: v, child: Text(v.label, overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (v) {
              if (v == null) return;
              if (v == p) return;
              // Model names are per provider: a new provider starts on its default.
              _model.clear();
              setState(() {
                _test = _Test.idle;
                _testMessage = null;
              });
              unawaited(_commit().then((_) => ctl.change((c) => c.copyWith(provider: v, model: ''))));
            },
          ),
        ),
        if (p != AiProvider.none) ...[
          if (p == AiProvider.openaiCompatible)
            field(
              TextField(
                key: const ValueKey('ai-base-url'),
                controller: _baseUrl,
                keyboardType: TextInputType.url,
                autocorrect: false,
                decoration: InputDecoration(
                  labelText: 'Base URL',
                  hintText: 'https://host/v1',
                  helperText: 'The server\'s OpenAI-style API root (…/v1)',
                  errorText: AiConfig.baseUrlProblem(_baseUrl.text),
                  border: const OutlineInputBorder(),
                ),
                onEditingComplete: () => unawaited(_commit()),
                onTapOutside: (_) => unawaited(_commit()),
              ),
            ),
          field(
            TextField(
              key: const ValueKey('ai-api-key'),
              controller: _key,
              obscureText: !_showKey,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: p.needsKey ? 'API key' : 'API key (if the server needs one)',
                helperText: kIsWeb
                    ? 'On the web the key is kept in this browser\'s storage.'
                    : 'Kept in this device\'s secure storage.',
                helperMaxLines: 2,
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  tooltip: _showKey ? 'Hide key' : 'Show key',
                  icon: Icon(_showKey ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                  onPressed: () => setState(() => _showKey = !_showKey),
                ),
              ),
              onEditingComplete: () => unawaited(_commit()),
              onTapOutside: (_) => unawaited(_commit()),
            ),
          ),
          field(
            TextField(
              key: const ValueKey('ai-model'),
              controller: _model,
              autocorrect: false,
              decoration: InputDecoration(
                labelText: 'Model',
                hintText: p.defaultModel.isEmpty ? 'model name' : p.defaultModel,
                helperText: switch (p) {
                  AiProvider.anthropic => 'Empty uses ${p.defaultModel} (small and fast).',
                  AiProvider.openai => 'Empty uses ${p.defaultModel}; pick a current small model.',
                  _ => 'The model name your server expects.',
                },
                helperMaxLines: 2,
                border: const OutlineInputBorder(),
              ),
              onEditingComplete: () => unawaited(_commit()),
              onTapOutside: (_) => unawaited(_commit()),
            ),
          ),
          field(
            DropdownButtonFormField<String>(
              key: const ValueKey('ai-explain-lang'),
              initialValue: const ['auto', 'en', 'nl'].contains(config.explainLang) ? config.explainLang : 'auto',
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Explanations in', border: OutlineInputBorder()),
              items: [
                DropdownMenuItem(
                  value: 'auto',
                  child: Text('Same as translations (${languageName(source)})', overflow: TextOverflow.ellipsis),
                ),
                for (final l in const ['en', 'nl']) DropdownMenuItem(value: l, child: Text(languageName(l))),
              ],
              onChanged: (v) {
                if (v != null) unawaited(ctl.change((c) => c.copyWith(explainLang: v)));
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
            child: Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                OutlinedButton.icon(
                  key: const ValueKey('ai-test'),
                  onPressed: _test == _Test.running ? null : () => unawaited(_testConnection()),
                  icon: _test == _Test.running
                      ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.wifi_tethering, size: 18),
                  label: const Text('Test connection'),
                ),
                if (_key.text.isNotEmpty)
                  TextButton.icon(
                    key: const ValueKey('ai-remove-key'),
                    onPressed: () {
                      _key.clear();
                      setState(() => _test = _Test.idle);
                      unawaited(_commit());
                    },
                    icon: const Icon(Icons.key_off_outlined, size: 18),
                    label: const Text('Remove key'),
                  ),
              ],
            ),
          ),
          if (_testMessage != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
              child: Row(
                key: ValueKey('ai-test-${_test.name}'),
                children: [
                  Icon(_test == _Test.ok ? Icons.check_circle_outline : Icons.error_outline, size: 18),
                  const SizedBox(width: 6),
                  Expanded(child: Text(_testMessage!, style: theme.textTheme.bodyMedium)),
                ],
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
            child: Text(
              config.isConfigured
                  ? 'On: "Explain answer with AI" appears after you check an answer.'
                  : 'Add your API key to turn AI explanations on.',
              key: const ValueKey('ai-status'),
              style: muted,
            ),
          ),
        ],
      ],
    );
  }
}

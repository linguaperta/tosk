/// AI explanation settings: provider, model, base URL and reply language are
/// ordinary settings in the progress store; the API key lives in a
/// [SecretStore] (the platform's secure storage). See docs/feedback.md.
library;

import 'package:meta/meta.dart';

import '../core/core.dart';
import 'secret_store.dart';

enum AiProvider {
  none('none', 'Off'),
  anthropic('anthropic', 'Anthropic Claude'),
  openai('openai', 'OpenAI'),
  openaiCompatible('openai_compatible', 'OpenAI-compatible');

  const AiProvider(this.id, this.label);
  final String id;
  final String label;

  static AiProvider byId(String? id) => values.firstWhere((p) => p.id == id, orElse: () => none);

  /// The model used when the user didn't type one. Claude: the small, fast
  /// Haiku. OpenAI: a small model; users should pick a current one.
  String get defaultModel => switch (this) {
    AiProvider.anthropic => 'claude-haiku-5-5',
    AiProvider.openai => 'gpt-5-mini',
    AiProvider.openaiCompatible => '',
    AiProvider.none => '',
  };

  String get defaultBaseUrl => switch (this) {
    AiProvider.anthropic => 'https://api.anthropic.com',
    AiProvider.openai => 'https://api.openai.com/v1',
    _ => '',
  };

  /// Whether this provider needs an API key (a local OpenAI-compatible server may not).
  bool get needsKey => this == AiProvider.anthropic || this == AiProvider.openai;
}

/// Setting keys (stored through `ProgressStore.setSetting`) and the secret key name.
abstract final class AiSettingKeys {
  static const provider = 'ai.provider';
  static const model = 'ai.model';
  static const baseUrl = 'ai.base_url';

  /// `auto` (follow the app's source language) or a language code.
  static const explainLang = 'ai.explain_lang';

  /// Name of the API key in the [SecretStore].
  static const apiKeySecret = 'tosk.ai.api_key';
}

@immutable
class AiConfig {
  const AiConfig({
    this.provider = AiProvider.none,
    this.model = '',
    this.baseUrl = '',
    this.apiKey = '',
    this.explainLang = 'auto',
  });

  final AiProvider provider;

  /// As typed; empty means [AiProvider.defaultModel].
  final String model;

  /// As typed; empty means [AiProvider.defaultBaseUrl].
  final String baseUrl;

  /// Never persisted with the other settings, never logged.
  final String apiKey;
  final String explainLang;

  String get effectiveModel => model.trim().isEmpty ? provider.defaultModel : model.trim();
  String get effectiveBaseUrl {
    final b = baseUrl.trim().isEmpty ? provider.defaultBaseUrl : baseUrl.trim();
    return b.endsWith('/') ? b.substring(0, b.length - 1) : b;
  }

  /// Everything needed to call the provider is set. Without it the AI buttons don't exist.
  bool get isConfigured {
    if (provider == AiProvider.none) return false;
    if (provider.needsKey && apiKey.trim().isEmpty) return false;
    if (effectiveModel.isEmpty) return false;
    final uri = Uri.tryParse(effectiveBaseUrl);
    return uri != null && (uri.scheme == 'https' || uri.scheme == 'http') && uri.host.isNotEmpty;
  }

  /// The language replies are written in: the setting, or [sourceLang] for `auto`.
  String replyLang(String sourceLang) => explainLang == 'auto' || explainLang.isEmpty ? sourceLang : explainLang;

  AiConfig copyWith({AiProvider? provider, String? model, String? baseUrl, String? apiKey, String? explainLang}) =>
      AiConfig(
        provider: provider ?? this.provider,
        model: model ?? this.model,
        baseUrl: baseUrl ?? this.baseUrl,
        apiKey: apiKey ?? this.apiKey,
        explainLang: explainLang ?? this.explainLang,
      );

  static Future<AiConfig> load(ProgressStore store, SecretStore secrets) async {
    String? key;
    try {
      key = await secrets.read(AiSettingKeys.apiKeySecret);
    } catch (_) {
      key = null; // secure storage unavailable: behave as "no key"
    }
    return AiConfig(
      provider: AiProvider.byId(await store.getSetting(AiSettingKeys.provider)),
      model: await store.getSetting(AiSettingKeys.model) ?? '',
      baseUrl: await store.getSetting(AiSettingKeys.baseUrl) ?? '',
      explainLang: await store.getSetting(AiSettingKeys.explainLang) ?? 'auto',
      apiKey: key ?? '',
    );
  }

  /// Writes what differs from [old] (everything when null). The key goes to [secrets].
  Future<void> save(ProgressStore store, SecretStore secrets, {AiConfig? old}) async {
    Future<void> put(String k, String v, String? o) async {
      if (old == null || v != o) await store.setSetting(k, v.isEmpty ? null : v);
    }

    await put(AiSettingKeys.provider, provider == AiProvider.none ? '' : provider.id, old?.provider.id);
    await put(AiSettingKeys.model, model, old?.model);
    await put(AiSettingKeys.baseUrl, baseUrl, old?.baseUrl);
    await put(AiSettingKeys.explainLang, explainLang == 'auto' ? '' : explainLang, old?.explainLang);
    if (old == null || apiKey != old.apiKey) {
      if (apiKey.isEmpty) {
        await secrets.delete(AiSettingKeys.apiKeySecret);
      } else {
        await secrets.write(AiSettingKeys.apiKeySecret, apiKey);
      }
    }
  }

  @override
  bool operator ==(Object other) =>
      other is AiConfig &&
      other.provider == provider &&
      other.model == model &&
      other.baseUrl == baseUrl &&
      other.apiKey == apiKey &&
      other.explainLang == explainLang;

  @override
  int get hashCode => Object.hash(provider, model, baseUrl, apiKey, explainLang);

  /// Never prints the key.
  @override
  String toString() =>
      'AiConfig(${provider.id}, model: $effectiveModel, base: $effectiveBaseUrl, key: ${apiKey.isEmpty ? 'none' : 'set'})';
}

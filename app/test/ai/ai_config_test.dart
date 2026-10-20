import 'package:tosk/ai/ai_config.dart';
import 'package:tosk/ai/secret_store.dart';
import 'package:flutter_test/flutter_test.dart';

import '../ui/helpers.dart' show TestProgressStore;
import 'ai_fixtures.dart';

class _BrokenSecrets implements SecretStore {
  @override
  Future<String?> read(String key) => throw StateError('no keychain');
  @override
  Future<void> write(String key, String value) => throw StateError('no keychain');
  @override
  Future<void> delete(String key) => throw StateError('no keychain');
}

void main() {
  test('defaults: off and not configured', () async {
    final c = await AiConfig.load(TestProgressStore(), MemorySecretStore());
    expect(c.provider, AiProvider.none);
    expect(c.isConfigured, isFalse);
    expect(c.explainLang, 'auto');
    expect(c.replyLang('nl'), 'nl');
  });

  test('round trip: settings in the progress store, the key only in the secret store', () async {
    final store = TestProgressStore();
    final secrets = MemorySecretStore();
    const c = AiConfig(provider: AiProvider.anthropic, apiKey: fakeKey, explainLang: 'nl');
    await c.save(store, secrets);
    expect(store.settings[AiSettingKeys.provider], 'anthropic');
    expect(store.settings.values, isNot(contains(fakeKey)));
    expect(await secrets.read(AiSettingKeys.apiKeySecret), fakeKey);
    final back = await AiConfig.load(store, secrets);
    expect(back, c);
    expect(back.effectiveModel, 'claude-haiku-5-5');
    expect(back.replyLang('en'), 'nl');

    // Removing the key deletes the secret.
    await back.copyWith(apiKey: '').save(store, secrets, old: back);
    expect(await secrets.read(AiSettingKeys.apiKeySecret), isNull);
  });

  test('isConfigured', () {
    expect(const AiConfig(provider: AiProvider.anthropic).isConfigured, isFalse);
    expect(const AiConfig(provider: AiProvider.openai, apiKey: fakeKey).isConfigured, isTrue);
    expect(const AiConfig(provider: AiProvider.openaiCompatible, model: 'm').isConfigured, isFalse, reason: 'no URL');
    expect(
      const AiConfig(
        provider: AiProvider.openaiCompatible,
        model: 'm',
        baseUrl: 'http://localhost:1234/v1',
      ).isConfigured,
      isTrue,
    );
    expect(const AiConfig(provider: AiProvider.openai, apiKey: fakeKey, baseUrl: 'not a url').isConfigured, isFalse);
  });

  test('toString never shows the key', () {
    expect(const AiConfig(provider: AiProvider.anthropic, apiKey: fakeKey).toString(), isNot(contains(fakeKey)));
  });

  test('a broken secure storage reads as "no key"', () async {
    final c = await AiConfig.load(TestProgressStore(settings: {AiSettingKeys.provider: 'openai'}), _BrokenSecrets());
    expect(c.provider, AiProvider.openai);
    expect(c.apiKey, '');
    expect(c.isConfigured, isFalse);
  });

  test('a key stored under the pre-rename name is read and moved', () async {
    final secrets = MemorySecretStore({AiSettingKeys.legacyApiKeySecret: 'k-old'});
    final c = await AiConfig.load(TestProgressStore(), secrets);
    expect(c.apiKey, 'k-old');
    expect(await secrets.read(AiSettingKeys.apiKeySecret), 'k-old');
    expect(await secrets.read(AiSettingKeys.legacyApiKeySecret), isNull);
  });
}

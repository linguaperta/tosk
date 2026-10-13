import '../../core/core.dart';

/// UI-side placeholder for the engine's `Explainer` hook (AI "Why?" explanations).
///
/// TODO(integration): the engine adds `Explainer`, `NullExplainer` and
/// `MistakeContext` to `core/interfaces/hooks.dart`. At integration, replace
/// [WhyExplainer] with that interface (or adapt it), and make
/// `explainerAvailableProvider` return `explainer is! NullExplainer`.
abstract interface class WhyExplainer {
  /// False hides the "Why?" button.
  bool get available;

  /// Streams the explanation text in chunks.
  Stream<String> explain(WhyContext context);
}

/// What the explainer gets about a wrong answer (mirrors the spec's `MistakeContext`).
class WhyContext {
  const WhyContext({required this.exercise, required this.expected, required this.given, this.note});
  final Exercise exercise;
  final String expected;
  final String given;

  /// Grammar note markdown of the exercise's skill, if any.
  final String? note;
}

/// The only implementation in v1: no explanations, button hidden.
class UnavailableWhyExplainer implements WhyExplainer {
  const UnavailableWhyExplainer();
  @override
  bool get available => false;
  @override
  Stream<String> explain(WhyContext context) => const Stream.empty();
}

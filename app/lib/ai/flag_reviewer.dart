/// "Confer with AI" on a flag: asks the configured model whether the exercise
/// is wrong, ambiguous or correct, and parses its verdict.
library;

import '../core/core.dart';
import 'llm_explainer.dart';
import 'prompts.dart';

class FlagReviewer {
  const FlagReviewer(this.llm);
  final LlmExplainer llm;

  /// The model's verdict and reasoning. Errors are `AiException`s.
  Future<ParsedVerdict> review({
    required ExplainContext context,
    required List<FlagReason> reasons,
    required String comment,
    Map<String, Object?>? snapshot,
  }) async {
    final reply = await llm
        .complete(flagReviewPrompt(context: context, reasons: reasons, comment: comment, snapshot: snapshot))
        .join();
    return parseVerdict(reply);
  }
}

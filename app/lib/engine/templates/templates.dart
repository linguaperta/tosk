/// All exercise templates.
library;

import '../template.dart';
import 'cloze.dart';
import 'conj_grid.dart';
import 'conj_pick.dart';
import 'flashcard.dart';
import 'listen_pick.dart';
import 'match_pairs.dart';
import 'multiple_choice.dart';
import 'sentence_builder.dart';
import 'spot_error.dart';
import 'transform.dart';

export 'cloze.dart';
export 'conj_grid.dart';
export 'conj_pick.dart';
export 'flashcard.dart';
export 'listen_pick.dart';
export 'match_pairs.dart';
export 'multiple_choice.dart';
export 'sentence_builder.dart';
export 'spot_error.dart' show SpotErrorTemplate, renderSpotError;
export 'transform.dart';

/// One instance of every template, in [ExerciseType] order.
List<ExerciseTemplate> defaultTemplates() => const [
      FlashcardTemplate(),
      MultipleChoiceTemplate(),
      MatchPairsTemplate(),
      ConjPickTemplate(),
      ConjGridTemplate(),
      SentenceBuilderTemplate(),
      ClozeTemplate(),
      SpotErrorTemplate(),
      TransformTemplate(),
      ListenPickTemplate(),
    ];

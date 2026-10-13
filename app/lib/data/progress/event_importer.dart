/// Merging events into a progress store (sync pulls, file imports). Pure Dart.
library;

import '../../core/core.dart';

/// Implemented by `ProgressRepo` and `InMemoryProgressStore`: inserts events
/// whose ids are new and replays only the facets they touch. Returns how many
/// events were new.
abstract interface class EventImporter {
  Future<int> importEvents(Iterable<ReviewEvent> events);
}

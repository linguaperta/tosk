// Driver for the integration benchmarks (`integration_test/map_scroll_perf_test.dart`):
// writes the test's report data to build/integration_response_data.json and,
// when the test traced a phase (`--dart-define=MAP_PERF_TRACE=true`), the
// timeline summary to build/map_scroll_<course>.timeline_summary.json.
import 'package:flutter_driver/flutter_driver.dart';
import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver(
  responseDataCallback: (data) async {
    if (data == null) return;
    for (final key in data.keys.where((k) => k.startsWith('timeline:')).toList()) {
      final timeline = Timeline.fromJson(data.remove(key) as Map<String, dynamic>);
      final summary = TimelineSummary.summarize(timeline);
      await summary.writeTimelineToFile('map_scroll_${key.substring('timeline:'.length)}', pretty: true);
    }
    await writeResponseData(data);
  },
);

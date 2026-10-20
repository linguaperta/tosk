// Scroll benchmark for the skill map: the real Italian and Spanish packs,
// dark theme, motion on (twinkles and swaying leaves) and a medal-heavy
// progress mix, scrolled top to bottom and back with flings and with a
// steady 1200 px/s scroll, in profile mode:
//
//   flutter drive --profile -d windows --driver=test_driver/perf_driver.dart \
//     --target=integration_test/map_scroll_perf_test.dart [--enable-impeller]
//
// On Windows the window is resized to a phone-shaped 412 x ~800 dp at a
// device pixel ratio of 1.3 (`phone_window.dart`); on a phone it runs at the
// phone's own size. Each phase prints a line with the frame build and raster
// times (average, 90th / 99th percentile, worst) and the frames over the
// 16.7 ms budget, and puts them in the report data
// (`build/integration_response_data.json`, written by the driver).
//
// Options (--dart-define): MAP_PERF_COURSES=it (one course),
// MAP_PERF_TRACE=true (a timeline of the steady phase, summarized by the
// driver into build/map_scroll_<course>.timeline_summary.json),
// MAP_PERF_NO_MOTION=true (twinkles and leaves off).
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:tosk/app.dart';
import 'package:tosk/app_bootstrap.dart';
import 'package:tosk/data/bootstrap.dart' show AppDataOptions;
import 'package:tosk/providers.dart';
import 'package:tosk/ui/map/skill_stats.dart';
import 'package:tosk/ui/settings/setting_keys.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'phone_window.dart';

/// A medal-heavy progress mix in course order: the first 40 % medals
/// (gold, silver, bronze, some cracked), then started, available and locked.
SkillStats benchStats(int i, int n, DateTime now) {
  final f = i / math.max(1, n);
  if (f < 0.4) {
    return SkillStats(
      tier: const [MapTier.gold, MapTier.silver, MapTier.bronze][i % 3],
      strength: 0.85,
      lastPracticed: now.subtract(Duration(days: i % 6)),
      fading: (i % 4) * 0.22,
      practicedFacets: 20,
      totalFacets: 20,
    );
  }
  if (f < 0.55) {
    return SkillStats(
      tier: MapTier.started,
      strength: 0.2 + 0.6 * ((i * 7) % 10) / 10,
      lastPracticed: now.subtract(Duration(days: i % 3)),
      fading: (i % 3) * 0.2,
      practicedFacets: 5,
      totalFacets: 20,
    );
  }
  if (f < 0.65) return const SkillStats(tier: MapTier.available);
  return const SkillStats(tier: MapTier.locked);
}

class FrameStats {
  FrameStats(this.name, List<ui.FrameTiming> t)
    : count = t.length,
      build = [for (final f in t) f.buildDuration.inMicroseconds / 1000]..sort(),
      raster = [for (final f in t) f.rasterDuration.inMicroseconds / 1000]..sort(),
      missed = t.where((f) => f.buildDuration.inMicroseconds > 16667 || f.rasterDuration.inMicroseconds > 16667).length;

  final String name;
  final int count;
  final List<double> build;
  final List<double> raster;
  final int missed;

  static double _avg(List<double> v) => v.isEmpty ? 0 : v.reduce((a, b) => a + b) / v.length;
  static double _pct(List<double> v, double p) => v.isEmpty ? 0 : v[math.min(v.length - 1, (v.length * p).floor())];

  Map<String, Object> toJson() => {
    'frames': count,
    'missed': missed,
    'build_avg': _avg(build),
    'build_p90': _pct(build, 0.9),
    'build_p99': _pct(build, 0.99),
    'build_max': build.isEmpty ? 0 : build.last,
    'raster_avg': _avg(raster),
    'raster_p90': _pct(raster, 0.9),
    'raster_p99': _pct(raster, 0.99),
    'raster_max': raster.isEmpty ? 0 : raster.last,
  };

  @override
  String toString() {
    String f(double x) => x.toStringAsFixed(2);
    return '[perf] $name: frames $count, missed $missed | build avg ${f(_avg(build))} p90 ${f(_pct(build, .9))} '
        'p99 ${f(_pct(build, .99))} max ${f(build.isEmpty ? 0 : build.last)} | raster avg ${f(_avg(raster))} '
        'p90 ${f(_pct(raster, .9))} p99 ${f(_pct(raster, .99))} max ${f(raster.isEmpty ? 0 : raster.last)} ms';
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;
  final results = <String, Object>{};

  // --dart-define=MAP_PERF_COURSES=it to run one course only.
  for (final courseId in const String.fromEnvironment('MAP_PERF_COURSES', defaultValue: 'it,es').split(',')) {
    testWidgets('map scroll: $courseId', (tester) async {
      if (Platform.isWindows) tester.view.devicePixelRatio = kPhoneWindowDpr;
      final dir = await Directory.systemTemp.createTemp('tosk-map-perf-');
      final boot = await bootApp(options: AppDataOptions(dataDirectory: dir.path));
      final store = boot.app.progress;
      await store.setSetting(SettingKeys.coursesAdded, 'it,es');
      await store.setSetting(SettingKeys.course, courseId);
      await store.setSetting(SettingKeys.themeMode, 'dark');
      final now = DateTime.now();

      await tester.pumpWidget(
        ProviderScope(
          retry: (_, _) => null,
          overrides: [
            ...boot.overrides,
            twinkleProvider.overrideWithValue(!const bool.fromEnvironment('MAP_PERF_NO_MOTION')),
            skillStatsProvider.overrideWith((ref) async {
              final course = await ref.watch(courseDataProvider.future);
              final ids = [
                for (final u in course.units)
                  for (final s in course.skills)
                    if (s.unitId == u.id) s.id,
              ];
              return {for (var i = 0; i < ids.length; i++) ids[i]: benchStats(i, ids.length, now)};
            }),
          ],
          child: const ToskApp(),
        ),
      );
      // The packs install and open; the motion ticker never settles, so pump by hand.
      for (var i = 0; i < 100 && find.byKey(const ValueKey('map-scroll')).evaluate().isEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      if (Platform.isWindows) await resizePhoneWindow();
      await tester.pump(const Duration(seconds: 1));
      final scroll = find.byKey(const ValueKey('map-scroll'));
      expect(scroll, findsOneWidget);
      final scrollable = find.descendant(of: scroll, matching: find.byType(Scrollable)).first;
      final position = tester.state<ScrollableState>(scrollable).position;
      final max = position.maxScrollExtent;
      debugPrint('[perf] $courseId: map ${max.round()} px of scroll, viewport ${position.viewportDimension.round()} px, '
          'window ${tester.view.physicalSize.width.round()}x${tester.view.physicalSize.height.round()} @ ${tester.view.devicePixelRatio}');

      Future<FrameStats> measure(String phase, Future<void> Function() action) async {
        final timings = <ui.FrameTiming>[];
        void collect(List<ui.FrameTiming> t) => timings.addAll(t);
        // Let the previous phase's frames drain first.
        await tester.pump(const Duration(milliseconds: 500));
        SchedulerBinding.instance.addTimingsCallback(collect);
        if (const bool.fromEnvironment('MAP_PERF_TRACE') && phase == 'steady') {
          await binding.traceAction(action, reportKey: 'timeline:$courseId');
        } else {
          await action();
        }
        // Timings are reported in batches (about every 100 ms in profile).
        await tester.pump(const Duration(milliseconds: 600));
        SchedulerBinding.instance.removeTimingsCallback(collect);
        final s = FrameStats('$courseId/$phase', timings);
        debugPrint(s.toString());
        results['$courseId/$phase'] = s.toJson();
        return s;
      }

      // A steady scroll down and back up (the most repeatable phase).
      await measure('steady', () async {
        final d = Duration(milliseconds: (max / 1.2).round());
        await position.animateTo(max, duration: d, curve: Curves.linear);
        await position.animateTo(0, duration: d, curve: Curves.linear);
      });

      // Flings and drags, like a thumb.
      await measure('fling', () async {
        for (var k = 0; k < 40 && position.pixels < max - 1; k++) {
          await tester.fling(scrollable, const Offset(0, -350), 2500);
          await tester.pump(const Duration(milliseconds: 700));
        }
        for (var k = 0; k < 40 && position.pixels > 1; k++) {
          await tester.timedDrag(scrollable, const Offset(0, 500), const Duration(milliseconds: 400));
          await tester.pump(const Duration(milliseconds: 300));
        }
      });

      // Idle on screen, motion running (twinkles in view): the ticker's cost.
      await measure('idle', () => tester.pump(const Duration(seconds: 2)));

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(milliseconds: 200));
      await boot.close();
      try {
        await dir.delete(recursive: true);
      } catch (_) {}
      binding.reportData = {...?binding.reportData, ...results};
    });
  }
}

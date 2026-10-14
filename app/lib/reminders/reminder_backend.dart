/// Local notifications for the daily reminder, behind a small interface so
/// the scheduling logic stays pure (`progression/daily_goal.dart`) and tests
/// use [FakeReminderBackend]-style fakes.
///
/// The real backend ([LocalNotificationsReminderBackend]) uses
/// flutter_local_notifications on Android, iOS and macOS. Elsewhere (Windows,
/// Linux, web) [ReminderBackend.supported] is false and Settings hides the
/// reminder. Every plugin call is guarded: a failure never breaks the app.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import '../progression/daily_goal.dart';
import 'test_env.dart';

abstract interface class ReminderBackend {
  /// Whether reminders work on this platform.
  bool get supported;

  /// Asks for permission to notify (Android 13+, iOS, macOS). True when granted.
  Future<bool> requestPermission();

  /// Replaces every scheduled reminder with [slots].
  Future<void> replaceAll(List<ReminderSlot> slots, {required String title, required String body});
}

/// Does nothing (unsupported platforms, `flutter test`).
class NullReminderBackend implements ReminderBackend {
  const NullReminderBackend();
  @override
  bool get supported => false;
  @override
  Future<bool> requestPermission() async => false;
  @override
  Future<void> replaceAll(List<ReminderSlot> slots, {required String title, required String body}) async {}
}

/// Notification ids used for reminders: [kReminderIdBase] + day offset.
const int kReminderIdBase = 4100;
const int kReminderMaxSlots = 14;

/// flutter_local_notifications on Android, iOS and macOS.
///
/// * Android: an inexact alarm (`inexactAllowWhileIdle`, so no
///   SCHEDULE_EXACT_ALARM permission); POST_NOTIFICATIONS is requested when
///   the user switches the reminder on; the plugin's boot receiver restores
///   scheduled reminders after a reboot (see AndroidManifest.xml).
/// * iOS / macOS: permission is requested when switching on, not at start.
/// * Times are absolute instants (UTC `TZDateTime`), computed from the local
///   wall clock with the device's zone rules, so no timezone database is needed.
class LocalNotificationsReminderBackend implements ReminderBackend {
  LocalNotificationsReminderBackend({FlutterLocalNotificationsPlugin? plugin})
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  Future<bool>? _init;

  static bool get platformSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS);

  @override
  bool get supported => platformSupported;

  Future<bool> _ensureInit() => _init ??= () async {
    try {
      const darwin = DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: darwin,
          macOS: darwin,
        ),
      );
      return true;
    } catch (e) {
      debugPrint('[reminder] init failed: $e');
      return false;
    }
  }();

  @override
  Future<bool> requestPermission() async {
    if (!supported || !await _ensureInit()) return false;
    try {
      switch (defaultTargetPlatform) {
        case TargetPlatform.android:
          final android = _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
          return await android?.requestNotificationsPermission() ?? false;
        case TargetPlatform.iOS:
          final ios = _plugin.resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>();
          return await ios?.requestPermissions(alert: true, sound: true) ?? false;
        case TargetPlatform.macOS:
          final mac = _plugin.resolvePlatformSpecificImplementation<MacOSFlutterLocalNotificationsPlugin>();
          return await mac?.requestPermissions(alert: true, sound: true) ?? false;
        default:
          return false;
      }
    } catch (e) {
      debugPrint('[reminder] permission request failed: $e');
      return false;
    }
  }

  @override
  Future<void> replaceAll(List<ReminderSlot> slots, {required String title, required String body}) async {
    if (!supported || !await _ensureInit()) return;
    try {
      for (var i = 0; i < kReminderMaxSlots; i++) {
        await _plugin.cancel(id: kReminderIdBase + i);
      }
      const details = NotificationDetails(
        android: AndroidNotificationDetails(
          'daily_reminder',
          'Daily reminder',
          channelDescription: 'A reminder on days your practice goal is not met yet',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
        iOS: DarwinNotificationDetails(),
        macOS: DarwinNotificationDetails(),
      );
      for (var i = 0; i < slots.length && i < kReminderMaxSlots; i++) {
        await _plugin.zonedSchedule(
          id: kReminderIdBase + i,
          scheduledDate: tz.TZDateTime.from(slots[i].at.toUtc(), tz.UTC),
          notificationDetails: details,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          title: title,
          body: body,
        );
      }
    } catch (e) {
      debugPrint('[reminder] scheduling failed: $e');
    }
  }
}

/// The backend for this platform ([NullReminderBackend] under `flutter test`,
/// which has no plugin; tests inject fakes).
ReminderBackend defaultReminderBackend() =>
    isFlutterTest ? const NullReminderBackend() : LocalNotificationsReminderBackend();

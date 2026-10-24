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
import 'package:url_launcher/url_launcher.dart';

import '../device/device_info.dart' as device;
import '../progression/daily_goal.dart';
import 'test_env.dart';

/// Whether tosk may show notifications.
enum NotificationAccess {
  /// Allowed (also Android 12 and older, unless turned off in the settings).
  granted,

  /// Not allowed: refused, not asked yet (Android 13+, iOS), or turned off in
  /// the system settings.
  denied,

  /// Can't tell (no plugin, a failure).
  unknown,
}

abstract interface class ReminderBackend {
  /// Whether reminders work on this platform.
  bool get supported;

  /// Whether notifications are allowed right now, without asking.
  Future<NotificationAccess> checkPermission();

  /// Asks for permission to notify (Android 13+, iOS, macOS). True when
  /// granted. When the system no longer shows its dialog (refused twice on
  /// Android), this returns false at once.
  Future<bool> requestPermission();

  /// Opens the system settings where notifications for tosk are turned on.
  Future<bool> openSettings();

  /// Replaces every scheduled reminder with [slots].
  Future<void> replaceAll(List<ReminderSlot> slots, {required String title, required String body});
}

/// Does nothing (unsupported platforms, `flutter test`).
class NullReminderBackend implements ReminderBackend {
  const NullReminderBackend();
  @override
  bool get supported => false;
  @override
  Future<NotificationAccess> checkPermission() async => NotificationAccess.unknown;
  @override
  Future<bool> requestPermission() async => false;
  @override
  Future<bool> openSettings() async => false;
  @override
  Future<void> replaceAll(List<ReminderSlot> slots, {required String title, required String body}) async {}
}

/// Notification ids used for reminders: [kReminderIdBase] + day offset.
const int kReminderIdBase = 4100;
const int kReminderMaxSlots = 14;

/// The Android notification channel of the daily reminder.
const AndroidNotificationChannel kReminderChannel = AndroidNotificationChannel(
  'daily_reminder',
  'Daily reminder',
  description: 'A reminder on days your practice goal is not met yet',
  importance: Importance.defaultImportance,
);

/// flutter_local_notifications on Android, iOS and macOS.
///
/// * Android: an inexact alarm (`inexactAllowWhileIdle`, which is
///   `AlarmManager.setAndAllowWhileIdle`): no SCHEDULE_EXACT_ALARM or
///   USE_EXACT_ALARM permission (Android 12-14 keep those for alarm-clock and
///   calendar apps), and it still fires in Doze, within the system's batching
///   window (usually minutes), which suits a daily nudge. POST_NOTIFICATIONS
///   (Android 13+) is requested when the user switches the reminder on. The
///   channel is created at init, so it is in the system settings before the
///   first reminder. The plugin's boot receiver restores scheduled reminders
///   after a reboot or an app update (see AndroidManifest.xml). Time zone and
///   date changes: the app re-plans on every resume.
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

  AndroidFlutterLocalNotificationsPlugin? get _android =>
      _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

  Future<bool> _ensureInit() => _init ??= () async {
    try {
      const darwin = DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );
      await _plugin.initialize(
        settings: const InitializationSettings(
          // A monochrome small icon (the colour launcher icon shows as a blob).
          android: AndroidInitializationSettings('@drawable/ic_launcher_monochrome'),
          iOS: darwin,
          macOS: darwin,
        ),
      );
      if (defaultTargetPlatform == TargetPlatform.android) {
        await _android?.createNotificationChannel(kReminderChannel);
      }
      return true;
    } catch (e) {
      debugPrint('[reminder] init failed: $e');
      return false;
    }
  }();

  @override
  Future<NotificationAccess> checkPermission() async {
    if (!supported || !await _ensureInit()) return NotificationAccess.unknown;
    try {
      final bool? enabled = switch (defaultTargetPlatform) {
        TargetPlatform.android => await _android?.areNotificationsEnabled(),
        TargetPlatform.iOS =>
          (await _plugin
                  .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
                  ?.checkPermissions())
              ?.isEnabled,
        TargetPlatform.macOS =>
          (await _plugin
                  .resolvePlatformSpecificImplementation<MacOSFlutterLocalNotificationsPlugin>()
                  ?.checkPermissions())
              ?.isEnabled,
        _ => null,
      };
      return switch (enabled) {
        true => NotificationAccess.granted,
        false => NotificationAccess.denied,
        null => NotificationAccess.unknown,
      };
    } catch (e) {
      debugPrint('[reminder] permission check failed: $e');
      return NotificationAccess.unknown;
    }
  }

  @override
  Future<bool> requestPermission() async {
    if (!supported || !await _ensureInit()) return false;
    try {
      switch (defaultTargetPlatform) {
        case TargetPlatform.android:
          return await _android?.requestNotificationsPermission() ?? false;
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
  Future<bool> openSettings() async {
    try {
      switch (defaultTargetPlatform) {
        case TargetPlatform.android:
          return await device.openNotificationSettings();
        case TargetPlatform.iOS:
          return await launchUrl(Uri.parse('app-settings:'));
        case TargetPlatform.macOS:
          return await launchUrl(Uri.parse('x-apple.systempreferences:com.apple.preference.notifications'));
        default:
          return false;
      }
    } catch (e) {
      debugPrint('[reminder] no notification settings: $e');
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
      final details = NotificationDetails(
        android: AndroidNotificationDetails(
          kReminderChannel.id,
          kReminderChannel.name,
          channelDescription: kReminderChannel.description,
          importance: kReminderChannel.importance,
          priority: Priority.defaultPriority,
          category: AndroidNotificationCategory.reminder,
        ),
        iOS: const DarwinNotificationDetails(),
        macOS: const DarwinNotificationDetails(),
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

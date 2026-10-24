/// The reports a learner can send the developer (flags, general feedback,
/// crash reports) as [OutgoingReport]s: the fields the Firestore rules accept
/// (`firebase/firestore.rules`), clipped to their limits. Only app version,
/// platform and (for crashes) the device model are added; nothing else about
/// the learner. Format: docs/feedback.md, "Reports to the developer".
library;

import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../app_version.dart';
import '../core/core.dart';
import '../sync/report_outbox.dart';
import 'flags_export.dart';

/// Limits, the same as the rules'.
abstract final class ReportLimits {
  static const text = 4000;
  static const email = 200;
  static const flag = 60000;
  static const crash = 20000;
  static const device = 200;
}

/// Where a general feedback email goes (`--dart-define=TOSK_FEEDBACK_EMAIL=…`,
/// or in `firebase-config.json`); empty hides the email option.
const kFeedbackEmail = String.fromEnvironment('TOSK_FEEDBACK_EMAIL');

/// `web`, `android`, `ios`, `windows`, …
String reportPlatform() => kIsWeb ? 'web' : defaultTargetPlatform.name;

String clip(String s, int max) => s.length <= max ? s : s.substring(0, max);

/// A crash report keeps its start (the error) and its end (where it was
/// thrown from the app's own code, usually near the top anyway).
String clipReport(String s, int max) {
  if (s.length <= max) return s;
  const cut = '\n…\n';
  final head = (max * 3) ~/ 4;
  return '${s.substring(0, head)}$cut${s.substring(s.length - (max - head - cut.length))}';
}

Map<String, Object> _base({required DateTime at, required String app, required String platform}) => {
  'v': 1,
  'app': clip(app, 40),
  'platform': clip(platform, 20),
  'at': at.toUtc().millisecondsSinceEpoch,
};

/// A submitted flag: the comment as `text`, the whole flag (`tosk-flag/1`,
/// as exported) as `flag`.
OutgoingReport flagReport(FlagRecord f, {String? platform}) {
  var json = jsonEncode(flagToJson(f));
  if (json.length > ReportLimits.flag) {
    // Too big (a huge AI reasoning): keep the exercise, drop the reasoning.
    json = jsonEncode({...flagToJson(f), 'ai_reasoning': null});
    if (json.length > ReportLimits.flag) json = jsonEncode({...flagToJson(f), 'ai_reasoning': null, 'exercise': {}});
  }
  return OutgoingReport(
    id: f.id,
    collection: ReportCollections.feedback,
    createdAtMs: f.createdAt.toUtc().millisecondsSinceEpoch,
    fields: {
      ..._base(at: f.createdAt, app: f.appVersion ?? kAppVersion, platform: platform ?? reportPlatform()),
      'kind': 'flag',
      'text': clip(f.comment, ReportLimits.text),
      'flag': json,
      if (f.courseId.isNotEmpty) 'course': clip(f.courseId, 64),
    },
  );
}

/// Settings → Send feedback: free text and, if given, an email for a reply.
OutgoingReport generalFeedbackReport({
  required String text,
  String email = '',
  required DateTime now,
  String? id,
  String? platform,
  String? courseId,
}) => OutgoingReport(
  id: id ?? const Uuid().v4(),
  collection: ReportCollections.feedback,
  createdAtMs: now.toUtc().millisecondsSinceEpoch,
  fields: {
    ..._base(at: now, app: kAppVersion, platform: platform ?? reportPlatform()),
    'kind': 'general',
    'text': clip(text.trim(), ReportLimits.text),
    if (email.trim().isNotEmpty) 'email': clip(email.trim(), ReportLimits.email),
    if (courseId != null && courseId.isNotEmpty) 'course': clip(courseId, 64),
  },
);

/// A crash report from the previous run, exactly as the learner saw it.
OutgoingReport crashReport({
  required String report,
  required DateTime now,
  String device = '',
  String? id,
  String? platform,
}) => OutgoingReport(
  id: id ?? const Uuid().v4(),
  collection: ReportCollections.crashes,
  createdAtMs: now.toUtc().millisecondsSinceEpoch,
  fields: {
    ..._base(at: now, app: kAppVersion, platform: platform ?? reportPlatform()),
    'device': clip(device.trim(), ReportLimits.device),
    'report': clipReport(report.trim().isEmpty ? '(empty report)' : report.trim(), ReportLimits.crash),
  },
);

/// The text for a copy or an email draft (no account): the message plus the
/// app version and platform, so the developer knows where it came from.
String feedbackPlainText(String text, {String? platform}) =>
    '${text.trim()}\n\n— tosk $kAppVersion · ${platform ?? reportPlatform()}';

/// A `mailto:` link to [to] with [subject] and [body] (null when [to] is empty).
Uri? feedbackMailto(String to, {required String subject, required String body}) {
  if (to.trim().isEmpty) return null;
  // Uri's queryParameters encode spaces as '+', which mail apps show literally.
  String enc(String s) => Uri.encodeComponent(s);
  return Uri.parse('mailto:${to.trim()}?subject=${enc(subject)}&body=${enc(body)}');
}

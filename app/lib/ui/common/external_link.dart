/// Opening a web page outside the app: the system browser natively, a new
/// tab on the web. Behind a provider so tests can watch what was opened.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens [url]; false when nothing could open it.
typedef ExternalLinkOpener = Future<bool> Function(Uri url);

final externalLinkOpenerProvider = Provider<ExternalLinkOpener>((ref) => openExternalLink);

Future<bool> openExternalLink(Uri url) async {
  try {
    return await launchUrl(url, mode: LaunchMode.externalApplication, webOnlyWindowName: '_blank');
  } on Object {
    return false;
  }
}

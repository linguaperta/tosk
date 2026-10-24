/// Which URLs the app may fetch packs from or send the AI key to. Pure Dart
/// (no `dart:io`, so the web build uses the same rules).
///
/// * Course indexes and packs: `https` only, plus plain `http` to this
///   machine (loopback, for development) or to the page's own origin on the
///   web (the app itself came from there). See [isAllowedPackUrl].
/// * The AI endpoint: `https`, or `http` to this machine or the local network
///   (a self-hosted OpenAI-compatible server). See [isAllowedAiUrl].
library;

/// `localhost`, `*.localhost`, 127.0.0.0/8 and `::1`.
bool isLoopbackHost(String host) {
  final h = _bare(host);
  if (h == 'localhost' || h.endsWith('.localhost')) return true;
  final v4 = _ipv4(h);
  if (v4 != null) return v4[0] == 127;
  final v6 = _ipv6(h);
  if (v6 != null) {
    if (_isV4Mapped(v6)) return v6[12] == 127;
    return v6.sublist(0, 15).every((b) => b == 0) && v6[15] == 1;
  }
  return false;
}

/// Loopback, private IPv4 ranges (10/8, 172.16/12, 192.168/16), link-local
/// (169.254/16, fe80::/10), unique-local IPv6 (fc00::/7), and `.local` /
/// `.lan` / `.home.arpa` names.
bool isLocalNetworkHost(String host) {
  if (isLoopbackHost(host)) return true;
  final h = _bare(host);
  if (h.endsWith('.local') || h.endsWith('.lan') || h.endsWith('.home.arpa')) return true;
  var v4 = _ipv4(h);
  final v6 = _ipv6(h);
  if (v6 != null && _isV4Mapped(v6)) v4 = v6.sublist(12);
  if (v4 != null) {
    return v4[0] == 10 ||
        (v4[0] == 172 && v4[1] >= 16 && v4[1] <= 31) ||
        (v4[0] == 192 && v4[1] == 168) ||
        (v4[0] == 169 && v4[1] == 254);
  }
  if (v6 != null) return (v6[0] & 0xfe) == 0xfc || (v6[0] == 0xfe && (v6[1] & 0xc0) == 0x80);
  return false;
}

/// A course index or pack may be fetched from [url]: `https`, or `http` to
/// loopback or to [sameOrigin] (the web page's own origin).
bool isAllowedPackUrl(Uri url, {Uri? sameOrigin}) {
  if (url.host.isEmpty || url.userInfo.isNotEmpty) return false;
  if (url.scheme == 'https') return true;
  if (url.scheme != 'http') return false;
  if (isLoopbackHost(url.host)) return true;
  return sameOrigin != null &&
      sameOrigin.scheme == url.scheme &&
      sameOrigin.host.toLowerCase() == url.host.toLowerCase() &&
      sameOrigin.port == url.port;
}

/// The AI key may be sent to [url]: `https`, or `http` to this machine or the local network.
bool isAllowedAiUrl(Uri url) {
  if (url.host.isEmpty || url.userInfo.isNotEmpty) return false;
  if (url.scheme == 'https') return true;
  return url.scheme == 'http' && isLocalNetworkHost(url.host);
}

String _bare(String host) {
  var h = host.toLowerCase();
  if (h.startsWith('[') && h.endsWith(']')) h = h.substring(1, h.length - 1);
  if (h.endsWith('.')) h = h.substring(0, h.length - 1);
  return h;
}

final RegExp _dottedQuad = RegExp(r'^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$');

List<int>? _ipv4(String h) {
  if (!_dottedQuad.hasMatch(h)) return null;
  try {
    return Uri.parseIPv4Address(h);
  } on FormatException {
    return null;
  }
}

List<int>? _ipv6(String h) {
  if (!h.contains(':')) return null;
  try {
    return Uri.parseIPv6Address(h.split('%').first);
  } on FormatException {
    return null;
  }
}

bool _isV4Mapped(List<int> v6) =>
    v6.sublist(0, 10).every((b) => b == 0) && v6[10] == 0xff && v6[11] == 0xff;

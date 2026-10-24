// web/index.html carries a Content-Security-Policy that allows its inline
// scripts by hash: editing one of them (or regenerating the splash screen)
// must update the hash, or the browser blocks the script.
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_test/flutter_test.dart';

void main() {
  final html = File('web/index.html').readAsStringSync().replaceAll('\r\n', '\n');
  final csp = RegExp(r'<meta http-equiv="Content-Security-Policy" content="([^"]+)">').firstMatch(html)?.group(1);

  test('index.html has a Content-Security-Policy before any script', () {
    expect(csp, isNotNull);
    expect(html.indexOf('Content-Security-Policy'), lessThan(html.indexOf('<script')));
    final directives = {
      for (final d in csp!.split(';').map((d) => d.trim()).where((d) => d.isNotEmpty))
        d.split(' ').first: d.split(' ').skip(1).toList(),
    };
    expect(directives['default-src'], ["'self'"]);
    expect(directives['object-src'], ["'none'"]);
    expect(directives['base-uri'], ["'self'"]);
    expect(directives['script-src'], isNot(contains("'unsafe-inline'")));
    expect(directives['script-src'], isNot(contains("'unsafe-eval'")));
  });

  test('every inline script is allowed by its hash', () {
    final inline = RegExp(r'<script(?![^>]*\bsrc=)[^>]*>(.*?)</script>', dotAll: true).allMatches(html).toList();
    expect(inline, isNotEmpty);
    for (final m in inline) {
      final hash = base64.encode(crypto.sha256.convert(utf8.encode(m.group(1)!)).bytes);
      expect(csp, contains("'sha256-$hash'"), reason: 'update the CSP hash of:\n${m.group(1)}');
    }
  });
}

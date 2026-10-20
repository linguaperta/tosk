// Typed answers take the keyboard focus as their exercise appears on desktops
// (native and desktop browsers), even though the lesson player grabs the
// focus for its shortcuts at the same moment; not on phones and tablets.
import 'package:tosk/ui/lesson/typing.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Like the player: a Focus for shortcuts that is asked for the focus
/// whenever the next exercise (here: the field) is shown.
class _Host extends StatefulWidget {
  const _Host();
  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  final player = FocusNode(debugLabel: 'player');
  bool showing = false;

  void next() {
    setState(() => showing = true);
    player.requestFocus();
  }

  @override
  void dispose() {
    player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Focus(
    focusNode: player,
    autofocus: true,
    child: Column(children: [if (showing) TypedAnswerField(autofocus: true, onChanged: (_) {})]),
  );
}

Future<bool> _fieldFocusedOn(WidgetTester tester, TargetPlatform platform) async {
  debugDefaultTargetPlatformOverride = platform;
  try {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: _Host())));
    tester.state<_HostState>(find.byType(_Host)).next();
    await tester.pump();
    await tester.pump();
    final focused = tester.state<EditableTextState>(find.byType(EditableText)).widget.focusNode.hasFocus;
    await tester.pumpWidget(const SizedBox());
    return focused;
  } finally {
    debugDefaultTargetPlatformOverride = null;
  }
}

void main() {
  testWidgets('desktops: the field has the focus, despite the player taking it', (tester) async {
    for (final p in [TargetPlatform.windows, TargetPlatform.macOS, TargetPlatform.linux]) {
      expect(await _fieldFocusedOn(tester, p), isTrue, reason: '$p');
    }
  });

  testWidgets('phones and tablets: no focus (no on-screen keyboard over the exercise)', (tester) async {
    for (final p in [TargetPlatform.android, TargetPlatform.iOS]) {
      expect(await _fieldFocusedOn(tester, p), isFalse, reason: '$p');
    }
  });

  testWidgets('a disabled field is never focused', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    try {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: TypedAnswerField(autofocus: true, enabled: false, onChanged: (_) {})),
        ),
      );
      await tester.pump();
      expect(tester.state<EditableTextState>(find.byType(EditableText)).widget.focusNode.hasFocus, isFalse);
      await tester.pumpWidget(const SizedBox());
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}

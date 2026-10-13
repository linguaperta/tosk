import 'dart:async';

import 'package:flutter/material.dart';

/// Shows an explainer's streamed reply ("Why?") in a bottom sheet.
Future<void> showWhySheet(BuildContext context, Stream<String> stream) => showModalBottomSheet<void>(
  context: context,
  showDragHandle: true,
  isScrollControlled: true,
  builder: (context) => WhySheet(stream: stream),
);

/// The "Why?" sheet: the explanation as it streams in.
class WhySheet extends StatelessWidget {
  const WhySheet({super.key, required this.stream});
  final Stream<String> stream;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
        child: StreamBuilder<String>(
          stream: stream.transform(_accumulate()),
          builder: (context, snap) {
            if (snap.hasError) return Text('Could not get an explanation: ${snap.error}');
            final text = snap.data ?? '';
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Why?', style: Theme.of(context).textTheme.titleLarge),
                const SizedBox(height: 8),
                if (text.isEmpty && snap.connectionState != ConnectionState.done)
                  const LinearProgressIndicator()
                else
                  Text(text),
              ],
            );
          },
        ),
      ),
    );
  }

  static StreamTransformer<String, String> _accumulate() {
    var acc = '';
    return StreamTransformer.fromHandlers(
      handleData: (chunk, sink) {
        acc += chunk;
        sink.add(acc);
      },
    );
  }
}

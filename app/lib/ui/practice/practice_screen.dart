import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers.dart';
import '../lab/lab_screen.dart';
import '../nonstop/nonstop_screen.dart';

/// The Practice tab: non-stop and the exercise lab, as two tabs. [tab] is
/// `nonstop` (default) or `lab`.
class PracticeScreen extends ConsumerStatefulWidget {
  const PracticeScreen({super.key, this.tab});
  final String? tab;

  @override
  ConsumerState<PracticeScreen> createState() => _PracticeScreenState();
}

class _PracticeScreenState extends ConsumerState<PracticeScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(
    length: 2,
    vsync: this,
    initialIndex: widget.tab == 'lab' ? 1 : 0,
    animationDuration: ref.read(reduceMotionProvider) ? Duration.zero : null,
  );

  @override
  void didUpdateWidget(PracticeScreen old) {
    super.didUpdateWidget(old);
    if (old.tab != widget.tab && widget.tab != null) _tabs.index = widget.tab == 'lab' ? 1 : 0;
  }

  @override
  void dispose() {
    _tabs.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Practice'),
        bottom: TabBar(
          key: const ValueKey('practice-tabs'),
          controller: _tabs,
          tabs: const [
            Tab(key: ValueKey('practice-tab-nonstop'), text: 'Non-stop'),
            Tab(key: ValueKey('practice-tab-lab'), text: 'Lab'),
          ],
        ),
      ),
      // Tabs switch without a swipeable page view (no sideways animation on
      // e-ink, no accidental swipes); both pages keep their state.
      body: AnimatedBuilder(
        animation: _tabs,
        builder: (context, _) => IndexedStack(
          index: _tabs.index,
          children: const [NonStopScreen(embedded: true), LabScreen(embedded: true)],
        ),
      ),
    );
  }
}

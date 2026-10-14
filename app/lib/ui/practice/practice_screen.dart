import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers.dart';
import '../lab/lab_screen.dart';
import '../nonstop/nonstop_screen.dart';
import '../stories/stories_view.dart';

/// The Practice tab: non-stop, the exercise lab and the graded stories, as
/// three tabs. [tab] is `nonstop` (default), `lab` or `stories`.
class PracticeScreen extends ConsumerStatefulWidget {
  const PracticeScreen({super.key, this.tab});
  final String? tab;

  @override
  ConsumerState<PracticeScreen> createState() => _PracticeScreenState();
}

const _tabIds = ['nonstop', 'lab', 'stories'];

int _indexOf(String? tab) => tab == null ? 0 : _tabIds.indexOf(tab).clamp(0, _tabIds.length - 1);

class _PracticeScreenState extends ConsumerState<PracticeScreen> with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(
    length: _tabIds.length,
    vsync: this,
    initialIndex: _indexOf(widget.tab),
    animationDuration: ref.read(reduceMotionProvider) ? Duration.zero : null,
  );

  @override
  void didUpdateWidget(PracticeScreen old) {
    super.didUpdateWidget(old);
    if (old.tab != widget.tab && widget.tab != null) _tabs.index = _indexOf(widget.tab);
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
            Tab(key: ValueKey('practice-tab-stories'), text: 'Stories'),
          ],
        ),
      ),
      // Tabs switch without a swipeable page view (no sideways animation on
      // e-ink, no accidental swipes); every page keeps its state.
      body: AnimatedBuilder(
        animation: _tabs,
        builder: (context, _) => IndexedStack(
          index: _tabs.index,
          children: const [NonStopScreen(embedded: true), LabScreen(embedded: true), StoriesView()],
        ),
      ),
    );
  }
}

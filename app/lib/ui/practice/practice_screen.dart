import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers.dart';
import '../chat/chat_home_view.dart';
import '../chat/chat_providers.dart';
import '../lab/lab_screen.dart';
import '../nonstop/nonstop_screen.dart';
import '../reading/reading_home.dart';
import '../stories/stories_view.dart';

/// The Practice tab: non-stop, the exercise lab, the graded stories, reading
/// any text and (v0.4, only with AI configured) AI conversation, as tabs.
/// [tab] is `nonstop` (default), `lab`, `stories`, `read` or `chat`.
class PracticeScreen extends ConsumerWidget {
  const PracticeScreen({super.key, this.tab});
  final String? tab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chat = ref.watch(chatAvailableProvider);
    final ids = [..._baseTabs, if (chat) 'chat'];
    // A new tab count needs a new TabController: key the tabs by it.
    return _PracticeTabs(key: ValueKey(ids.length), ids: ids, tab: tab);
  }
}

const _baseTabs = ['nonstop', 'lab', 'stories', 'read'];

class _PracticeTabs extends ConsumerStatefulWidget {
  const _PracticeTabs({super.key, required this.ids, this.tab});
  final List<String> ids;
  final String? tab;

  @override
  ConsumerState<_PracticeTabs> createState() => _PracticeTabsState();
}

class _PracticeTabsState extends ConsumerState<_PracticeTabs> with SingleTickerProviderStateMixin {
  int _indexOf(String? tab) => tab == null || !widget.ids.contains(tab) ? 0 : widget.ids.indexOf(tab);

  late final TabController _tabs = TabController(
    length: widget.ids.length,
    vsync: this,
    initialIndex: _indexOf(widget.tab),
    animationDuration: ref.read(reduceMotionProvider) ? Duration.zero : null,
  );

  @override
  void didUpdateWidget(_PracticeTabs old) {
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
    const labels = {'nonstop': 'Non-stop', 'lab': 'Lab', 'stories': 'Stories', 'read': 'Read', 'chat': 'Chat'};
    final scroll = widget.ids.length > 3 && MediaQuery.sizeOf(context).width < 520;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Practice'),
        bottom: TabBar(
          key: const ValueKey('practice-tabs'),
          controller: _tabs,
          // Four tabs don't fit a phone at full label width: let them scroll.
          isScrollable: scroll,
          tabAlignment: scroll ? TabAlignment.start : null,
          tabs: [for (final id in widget.ids) Tab(key: ValueKey('practice-tab-$id'), text: labels[id])],
        ),
      ),
      // Tabs switch without a swipeable page view (no sideways animation on
      // e-ink, no accidental swipes); every page keeps its state.
      body: AnimatedBuilder(
        animation: _tabs,
        builder: (context, _) => IndexedStack(
          index: _tabs.index,
          children: [
            for (final id in widget.ids)
              switch (id) {
                'nonstop' => const NonStopScreen(embedded: true),
                'lab' => const LabScreen(embedded: true),
                'stories' => const StoriesView(),
                'read' => const ReadingHomeView(),
                _ => const ChatHomeView(),
              },
          ],
        ),
      ),
    );
  }
}

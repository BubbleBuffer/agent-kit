// The outline scene: a chat laid out in chapters, as a host would show it. Two
// closed chapters (the first opened to its face, the second folded) and an
// open one with its sections and messages, under the where-am-I strip. The
// data is hand-built; the scene owns an OutlineController the way a chat
// would. Tap a card to open it, "Show messages" to unfold a chapter, the strip
// for the contents and the dots for a chapter's menu.

import 'package:agent_kit/agent_kit.dart';
import 'package:agent_kit_core/agent_kit_core.dart'
    show AssistantMessage, TranscriptItem, UserMessage;
import 'package:bb_ui/bb_ui.dart' show Ico;
import 'package:flutter/widgets.dart';

/// One message of the fixture: the anchor `m$n` shown by the item `i$n`.
const _messages = <(bool, String)>[
  (true, 'The quota bar flickers to zero for a moment when the stream drops.'),
  (false, 'It does: the poller clears its last figure on disconnect.'),
  (true, 'Can it keep showing the last figure until a new one arrives?'),
  (false, 'Yes. I will hold it in an Option and clear it only on sign-out.'),
  (false, 'Done, with a test that replays a drop. The bar stays put.'),
  (true, 'Good. Ship that one.'),
  (true, 'What should it do when the reconnect keeps failing?'),
  (false, 'Back off: 1 s, 2 s, 4 s, up to a minute, with a little jitter.'),
  (true, 'Add the jitter, and show nothing new to the user.'),
  (false, 'Added. The bar keeps its last figure through every retry.'),
  (true, 'Now the release notes for this fix.'),
  (false, 'Drafting: **Quota bar** no longer flickers on reconnect.'),
  (true, 'Mention the backoff too.'),
  (false, 'Added a line on the backoff, capped at a minute.'),
  (true, 'Read it through once more before it goes out.'),
  (false, 'Read it twice. One typo fixed, nothing else to change.'),
];

final _items = <String, TranscriptItem>{
  for (final (n, (user, text)) in _messages.indexed)
    'i$n': user
        ? UserMessage(id: 'i$n', text: text)
        : AssistantMessage(id: 'i$n', markdown: text),
};

final _outline = Outline([
  OutlineChapter(
    id: 'c-quota',
    title: 'Quota bar: it flickers on reconnect',
    summary:
        'The bar drops to zero for a frame when the stream reconnects. The '
        'usage poller cleared its last figure on disconnect.',
    decisions: const ['Keep the last figure on disconnect, behind an Option.'],
    first: 'm0',
    last: 'm5',
    startedAt: DateTime.utc(2026, 10, 27, 9),
    endedAt: DateTime.utc(2026, 10, 28, 15),
    messageCount: 6,
    sections: const [
      OutlineSection(
        id: 'quota-cause',
        title: 'Find the cause',
        first: 'm0',
        last: 'm1',
      ),
      OutlineSection(
        id: 'quota-fix',
        title: 'Keep the last figure',
        first: 'm2',
        last: 'm5',
      ),
    ],
  ),
  OutlineChapter(
    id: 'c-backoff',
    title: 'Backoff: retries after a drop',
    summary: 'Reconnects back off from one second to a minute.',
    decisions: const ['Back off with jitter; never show the user a retry.'],
    first: 'm6',
    last: 'm9',
    startedAt: DateTime.utc(2026, 10, 28, 16),
    endedAt: DateTime.utc(2026, 10, 28, 17),
    messageCount: 4,
  ),
  OutlineChapter(
    id: 'c-notes',
    title: 'Release notes',
    first: 'm10',
    last: 'm15',
    startedAt: DateTime.utc(2026, 10, 29, 9),
    ongoing: true,
    messageCount: 6,
    sections: const [
      OutlineSection(
        id: 'notes-draft',
        title: 'Draft',
        first: 'm10',
        last: 'm13',
      ),
      OutlineSection(
        id: 'notes-review',
        title: 'Review',
        first: 'm14',
        last: 'm15',
      ),
    ],
  ),
]);

class OutlineScene extends StatefulWidget {
  const OutlineScene({super.key});

  @override
  State<OutlineScene> createState() => _OutlineSceneState();
}

class _OutlineSceneState extends State<OutlineScene>
    with TickerProviderStateMixin {
  late final OutlineController _controller = OutlineController(
    vsync: this,
    mounted: () => mounted,
    update: setState,
  );

  @override
  void initState() {
    super.initState();
    // The first card starts open on its summary, decision and sections.
    _controller.fold.expanded['m0'] = true;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<OutlineAction> get _actions => [
    OutlineAction(label: 'Add to note…', icon: Ico.plus, onSelected: () {}),
  ];

  @override
  Widget build(BuildContext context) {
    final t = context.bb;
    _controller.sync(
      outline: _outline,
      itemIds: [for (final id in _items.keys) id],
      anchorIds: [for (var n = 0; n < _messages.length; n++) 'm$n'],
      anchorOf: {for (var n = 0; n < _messages.length; n++) 'm$n': 'i$n'},
    );
    return ColoredBox(
      color: t.surface,
      child: SizeClassBuilder(
        builder: (context, sizeClass) {
          final pad = sizeClass.isCompact ? 12.0 : 32.0;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              OutlineWhereStrip(
                where: _controller.where,
                onTap: () => _controller.showContents(context),
                colors: outlineStripColors(context, _outline),
              ),
              Expanded(
                child: OutlineList(
                  controller: _controller,
                  padding: EdgeInsets.fromLTRB(pad, 20, pad, 16),
                  chapterActions: (_) => _actions,
                  sectionActions: (_, _) => _actions,
                  cardActions: (_) => _actions,
                  itemBuilder: (context, row) =>
                      TranscriptItemView(_items[row.itemId]!),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

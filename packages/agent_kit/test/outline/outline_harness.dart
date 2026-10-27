// A host for the outline tests: a stateful widget that owns an
// OutlineController the way a chat would, over a generated chat.

import 'package:agent_kit/agent_kit.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

/// Three closed chapters of [perChapter] messages each; chapter c holds
/// anchors `m(c*perChapter)`..`m(c*perChapter+perChapter-1)`, in two sections
/// of half each. [ongoingLast] makes the last chapter open.
Outline fixtureOutline({
  int chapters = 3,
  int perChapter = 20,
  bool ongoingLast = false,
}) {
  final half = perChapter ~/ 2;
  return Outline([
    for (var c = 0; c < chapters; c++)
      OutlineChapter(
        id: 'c$c',
        title: 'Chapter $c',
        summary: 'Summary for chapter $c. More detail follows.',
        decisions: ['Decision $c'],
        ongoing: ongoingLast && c == chapters - 1,
        first: 'm${c * perChapter}',
        last: 'm${(c + 1) * perChapter - 1}',
        startedAt: DateTime.utc(2026, 10, 9, 12 + c),
        endedAt: DateTime.utc(2026, 10, 9, 12 + c, 30),
        messageCount: perChapter,
        sections: [
          for (var s = 0; s < 2; s++)
            OutlineSection(
              id: 'c${c}s$s',
              title: 'Section $c.$s',
              first: 'm${c * perChapter + s * half}',
              last: 'm${c * perChapter + (s + 1) * half - 1}',
            ),
        ],
      ),
  ]);
}

/// Message `n` is anchor `m$n`, shown by item `i$n`.
List<String> anchorsOf(int count) => [for (var n = 0; n < count; n++) 'm$n'];
List<String> itemsOf(int count) => [for (var n = 0; n < count; n++) 'i$n'];
Map<String, String> anchorMap(int count) => {
  for (var n = 0; n < count; n++) 'm$n': 'i$n',
};

class OutlineHost extends StatefulWidget {
  const OutlineHost({
    super.key,
    required this.outline,
    this.count = 60,
    this.chapterActions,
    this.sectionActions,
    this.cardActions,
  });

  final Outline outline;
  final int count;
  final List<OutlineAction> Function(OutlineChapter chapter)? chapterActions;
  final List<OutlineAction> Function(
    OutlineChapter chapter,
    OutlineSection section,
  )?
  sectionActions;
  final List<OutlineAction> Function(OutlineChapter chapter)? cardActions;

  @override
  State<OutlineHost> createState() => OutlineHostState();
}

class OutlineHostState extends State<OutlineHost>
    with TickerProviderStateMixin {
  late final OutlineController controller = OutlineController(
    vsync: this,
    mounted: () => mounted,
    update: setState,
  );

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    controller.sync(
      outline: widget.outline,
      itemIds: itemsOf(widget.count),
      anchorIds: anchorsOf(widget.count),
      anchorOf: anchorMap(widget.count),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        OutlineWhereStrip(
          where: controller.where,
          onTap: () => controller.showContents(context),
          colors: outlineStripColors(context, widget.outline),
        ),
        Expanded(
          child: OutlineList(
            controller: controller,
            chapterActions: widget.chapterActions,
            sectionActions: widget.sectionActions,
            cardActions: widget.cardActions,
            padding: const EdgeInsets.all(12),
            itemBuilder: (context, row) => SizedBox(
              key: ValueKey('msg-${row.itemId}'),
              height: 40,
              child: Text('Message ${row.itemId.substring(1)}'),
            ),
          ),
        ),
      ],
    );
  }
}

Future<OutlineHostState> pumpOutline(
  WidgetTester tester, {
  Outline? outline,
  int count = 60,
  Size size = const Size(480, 650),
  Brightness brightness = Brightness.light,
  List<OutlineAction> Function(OutlineChapter chapter)? chapterActions,
  List<OutlineAction> Function(OutlineChapter, OutlineSection)? sectionActions,
  List<OutlineAction> Function(OutlineChapter chapter)? cardActions,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  final host = GlobalKey<OutlineHostState>();
  await tester.pumpWidget(
    WidgetsApp(
      color: const Color(0xFF000000),
      debugShowCheckedModeBanner: false,
      pageRouteBuilder: <T>(settings, builder) => PageRouteBuilder<T>(
        settings: settings,
        pageBuilder: (context, _, _) => builder(context),
      ),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: BbThemeScope(brightness: brightness, child: child!),
      ),
      home: OutlineHost(
        key: host,
        outline: outline ?? fixtureOutline(),
        count: count,
        chapterActions: chapterActions,
        sectionActions: sectionActions,
        cardActions: cardActions,
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  return host.currentState!;
}

Finder keyed(String k) => find.byKey(ValueKey(k));

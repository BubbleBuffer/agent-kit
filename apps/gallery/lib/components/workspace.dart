// Gallery entries of the workspace group: AgentWorkspace in each state and
// size class, on fake panes (a browser card, a terminal and a file preview).
// The panes are the host's in a real app; these stand in for them.

import 'package:agent_kit/agent_kit.dart';
import 'package:agent_kit_core/agent_kit_core.dart' show ChatStatus;
import 'package:bb_ui/bb_ui.dart';
import 'package:flutter/widgets.dart';

import '../src/gallery_tokens.dart';

/// The mockup's default tree: the browser on the left at full height, the
/// terminal over the file preview on the right.
WorkspaceLayout galleryWorkspaceLayout() => WorkspaceLayout(
  root: WorkspaceSplit(
    id: 'root',
    axis: SplitAxis.row,
    children: [
      WorkspaceLeaf(
        id: 'browser-pane',
        tabs: const [
          WorkspaceTab(id: 'browser', kind: 'browser', title: 'localhost:5173'),
        ],
      ),
      WorkspaceSplit(
        id: 'right',
        axis: SplitAxis.column,
        weights: const [1.15, 0.85],
        children: [
          WorkspaceLeaf(
            id: 'terminal-pane',
            tabs: const [
              WorkspaceTab(id: 'cargo', kind: 'terminal', title: 'cargo test'),
              WorkspaceTab(id: 'dev', kind: 'terminal', title: 'dev server'),
            ],
            active: 'cargo',
          ),
          WorkspaceLeaf(
            id: 'file-pane',
            tabs: const [
              WorkspaceTab(id: 'usage', kind: 'file', title: 'usage/mod.rs'),
            ],
          ),
        ],
      ),
    ],
  ),
  front: 'browser',
);

/// What each fake pane shows, by kind and tab id.
Widget galleryPaneBuilder(BuildContext context, WorkspaceTab tab) =>
    switch (tab.kind) {
      'browser' => const FakeBrowserPane(),
      'terminal' => FakeTerminalPane(dev: tab.id == 'dev'),
      'file' => const FakeFilePane(),
      'activity' => const FakeActivityPane(),
      _ => Center(
        child: Text(
          tab.kind,
          style: ts(context.bb.typeScale.ui, context.bb.muted),
        ),
      ),
    };

/// The Workspace specimens of the Components scene.
class WorkspaceSpecimens extends StatefulWidget {
  const WorkspaceSpecimens({super.key});

  @override
  State<WorkspaceSpecimens> createState() => _WorkspaceSpecimensState();
}

class _WorkspaceSpecimensState extends State<WorkspaceSpecimens> {
  late final _live = WorkspaceController(galleryWorkspaceLayout());
  late final _collapsed = WorkspaceController(
    galleryWorkspaceLayout().collapse('browser-pane'),
  );
  late final _maximised = WorkspaceController(
    galleryWorkspaceLayout().maximise('file-pane'),
  );
  late final _medium = WorkspaceController(galleryWorkspaceLayout());
  late final _compact = WorkspaceController(
    galleryWorkspaceLayout().activate('usage'),
  );
  late final _empty = WorkspaceController();

  @override
  void dispose() {
    for (final c in [
      _live,
      _collapsed,
      _maximised,
      _medium,
      _compact,
      _empty,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget gap() => const Gap(Space.xl);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Stage(
          title: 'AgentWorkspace · expanded (drag dividers and headers)',
          width: StageWidths.desktop,
          height: Specimen.workspaceLive,
          controller: _live,
        ),
        gap(),
        _Stage(
          title: 'Browser collapsed to its edge tab',
          width: StageWidths.desktop,
          height: Specimen.workspaceCollapsed,
          controller: _collapsed,
        ),
        gap(),
        _Stage(
          title: 'File pane maximised',
          width: StageWidths.desktop,
          height: Specimen.workspaceMaximised,
          controller: _maximised,
        ),
        gap(),
        _Stage(
          title: 'Medium: one column of pane tabs',
          width: StageWidths.medium,
          height: Specimen.workspaceMedium,
          controller: _medium,
        ),
        gap(),
        _Stage(
          title: 'Compact: a full-screen sheet with pane tabs',
          width: StageWidths.phone,
          height: Specimen.workspaceCompact,
          controller: _compact,
          sheet: true,
        ),
        gap(),
        _Stage(
          title: 'Empty',
          width: StageWidths.medium,
          height: Specimen.workspaceEmpty,
          controller: _empty,
        ),
      ],
    );
  }
}

class _Stage extends StatelessWidget {
  const _Stage({
    required this.title,
    required this.width,
    required this.height,
    required this.controller,
    this.sheet = false,
  });

  final String title;
  final double width;
  final double height;
  final WorkspaceController controller;
  final bool sheet;

  @override
  Widget build(BuildContext context) {
    final t = context.bb;
    // The mockup keeps 12 px around the tree; the sheet is edge to edge.
    final pad = sheet ? 0.0 : Space.md;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.only(bottom: Space.sm),
          child: Text(title, style: ts(t.typeScale.uiSmall, t.muted)),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: t.canvas,
              border: Border.all(color: t.seam),
              borderRadius: BorderRadius.circular(t.radii.md),
            ),
            child: Padding(
              padding: EdgeInsets.all(pad),
              child: SizedBox(
                width: width,
                height: height,
                child: Overlay(
                  initialEntries: [
                    OverlayEntry(
                      builder: (_) => AgentWorkspace(
                        controller: controller,
                        kinds: WorkspaceKind.standard,
                        paneBuilder: galleryPaneBuilder,
                        onClose: () {},
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ----- fake panes -----

TextStyle _mono(BbTheme t, Color color, {bool large = false, Weight? weight}) =>
    ts(
      large ? t.typeScale.code : t.typeScale.codeSmall,
      color,
      mono: true,
      weight: weight,
    );

/// A browser card: the address bar is the kit's; the page is the host's.
class FakeBrowserPane extends StatelessWidget {
  const FakeBrowserPane({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.bb;
    Widget navButton(IconData icon) => SizedBox.square(
      dimension: ControlSize.sm.height,
      child: Center(
        child: LucideIcon(icon, size: IconSize.xs.px, color: t.muted),
      ),
    );
    return Column(
      children: [
        ConstrainedBox(
          constraints: BoxConstraints(minHeight: ControlSize.lg.height),
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: t.seam)),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.xs),
              child: Row(
                children: [
                  navButton(WorkspaceIcons.arrowLeft),
                  navButton(WorkspaceIcons.arrowRight),
                  navButton(WorkspaceIcons.rotateCw),
                  const Gap(Space.xxs),
                  Expanded(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: t.surface2,
                        borderRadius: t.radii.pill,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: Space.md,
                        ),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minHeight: ControlSize.sm.height,
                          ),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: Text.rich(
                              TextSpan(
                                style: _mono(t, t.ink),
                                children: [
                                  TextSpan(
                                    text: 'http://',
                                    style: TextStyle(color: t.faint),
                                  ),
                                  const TextSpan(text: 'localhost:5173'),
                                  TextSpan(
                                    text: '/usage',
                                    style: TextStyle(color: t.faint),
                                  ),
                                ],
                              ),
                              maxLines: 1,
                              softWrap: false,
                              overflow: TextOverflow.clip,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        Expanded(
          child: ColoredBox(
            color: t.canvas,
            child: ClipRect(
              child: SingleChildScrollView(
                physics: const ClampingScrollPhysics(),
                padding: const EdgeInsets.all(Space.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: Space.sm,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          'BubblePaw',
                          style: ts(t.typeScale.ui, t.ink, weight: Weight.bold),
                        ),
                        Text(
                          'Sessions',
                          style: ts(t.typeScale.uiSmall, t.muted),
                        ),
                        Text(
                          'Usage',
                          style: ts(
                            t.typeScale.uiSmall,
                            t.ink,
                            weight: Weight.bold,
                          ),
                        ),
                      ],
                    ),
                    const Gap(Space.sm),
                    const StatusMark(
                      ChatStatus.running,
                      label: 'Reconnecting',
                      detail: 'showing the last figure from 14s ago',
                    ),
                    const Gap(Space.md),
                    _AppCard(
                      children: [
                        Text(
                          'This week',
                          style: ts(t.typeScale.uiSmall, t.muted),
                        ),
                        Text(
                          '62%',
                          style: ts(t.typeScale.h2, t.ink, weight: Weight.bold),
                        ),
                        const Gap(Space.xxs),
                        _Meter(fraction: .62, color: t.faint),
                        const Gap(Space.xs),
                        Text(
                          '1.24M of 2M tokens · resets Monday 00:00',
                          style: ts(
                            t.typeScale.uiSmall,
                            t.muted,
                            weight: Weight.regular,
                          ),
                        ),
                        const Gap(Space.xxs),
                        Row(
                          children: [
                            LucideIcon(
                              WorkspaceIcons.clock,
                              size: IconSize.xs.px,
                              color: t.attentionInk,
                            ),
                            const Gap(Space.xxs),
                            Flexible(
                              child: Text(
                                'Stale, last update 14s ago',
                                style: ts(
                                  t.typeScale.uiSmall,
                                  t.attentionInk,
                                  weight: Weight.medium,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const Gap(Space.sm),
                    _AppCard(
                      children: [
                        Text(
                          'By model',
                          style: ts(t.typeScale.uiSmall, t.muted),
                        ),
                        const Gap(Space.xxs),
                        for (final (name, share) in const [
                          ('deepseek-v4.1-flash', '48%'),
                          ('gpt-6.1-sol', '14%'),
                          ('Other', '<1%'),
                        ])
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Flexible(
                                child: Text(
                                  name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: _mono(t, t.ink),
                                ),
                              ),
                              Text(share, style: _mono(t, t.muted)),
                            ],
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _AppCard extends StatelessWidget {
  const _AppCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final t = context.bb;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: t.surface,
        border: Border.all(color: t.seam),
        borderRadius: t.radii.field,
      ),
      child: Padding(
        padding: const EdgeInsets.all(Space.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: children,
        ),
      ),
    );
  }
}

class _Meter extends StatelessWidget {
  const _Meter({required this.fraction, required this.color});

  final double fraction;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final t = context.bb;
    return SizedBox(
      height: FakePane.bar,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: t.surface2,
          borderRadius: BorderRadius.circular(Radii.sm),
        ),
        child: FractionallySizedBox(
          alignment: Alignment.centerLeft,
          widthFactor: fraction,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(Radii.sm),
            ),
          ),
        ),
      ),
    );
  }
}

const _terminal = <(String, String)>[
  ('p', r'$ cargo test -p harbor-runtime usage'),
  ('d', '   Compiling harbor-runtime v0.2.1 (crates/harbor-runtime)'),
  ('d', '    Finished `test` profile [unoptimized + debuginfo] in 6.42s'),
  ('d', '     Running unittests src/lib.rs'),
  ('', ''),
  ('', 'running 14 tests'),
  ('', 'test usage::tests::merge_adds_turn_tokens ... ok'),
  ('', 'test usage::tests::reset_clears_window ... ok'),
  ('b', 'test usage::tests::snapshot_survives_reconnect ... FAILED'),
  ('b', 'test usage::tests::stale_flag_clears_on_update ... FAILED'),
  ('', 'test usage::tests::window_rolls_at_midnight ... ok'),
  ('', ''),
  ('', '---- usage::tests::snapshot_survives_reconnect stdout ----'),
  ('', "thread 'usage::tests::snapshot_survives_reconnect' panicked at"),
  ('', 'crates/harbor-runtime/src/usage/mod.rs:212:9:'),
  ('', 'assertion `left == right` failed'),
  ('', '  left: None'),
  ('', ' right: Some(UsageSnapshot { percent: 62, .. })'),
  ('', ''),
  (
    'b',
    'test result: FAILED. 12 passed; 2 failed; 0 ignored; finished in 0.04s',
  ),
  ('p', r'$ '),
];

/// A terminal-ish mono text pane. [dev] shows the dev server's log instead.
class FakeTerminalPane extends StatelessWidget {
  const FakeTerminalPane({super.key, this.dev = false});

  final bool dev;

  @override
  Widget build(BuildContext context) {
    final t = context.bb;
    final lines = dev
        ? const <(String, String)>[
            ('p', r'$ npm run dev'),
            ('d', '  VITE v6.0.1  ready in 312 ms'),
            ('', '  Local:   http://localhost:5173/'),
            ('d', '  press h + enter to show help'),
          ]
        : _terminal;
    return ColoredBox(
      color: t.surface2,
      child: ClipRect(
        child: SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(
            Space.md,
            Space.md,
            Space.md,
            Space.lg,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final (kind, text) in lines)
                Text(
                  text.isEmpty ? ' ' : text,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.clip,
                  style: _mono(
                    t,
                    switch (kind) {
                      'p' => t.ink,
                      'b' => t.dangerInk,
                      _ => t.muted,
                    },
                    weight: kind == 'b' || kind == 'p' ? Weight.semibold : null,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

const _file = <(int?, String, String)>[
  (176, ' ', 'impl UsageState {'),
  (177, ' ', '    pub fn on_update(&mut self, snap: UsageSnapshot) {'),
  (178, ' ', '        self.last = Some(snap);'),
  (179, ' ', '        self.stale_since = None;'),
  (180, ' ', '    }'),
  (181, ' ', ''),
  (182, ' ', '    pub fn on_disconnect(&mut self, now: Timestamp) {'),
  (null, '-', '        self.last = UsageSnapshot::default();'),
  (183, '+', '        self.stale_since = Some(now);'),
  (184, ' ', '    }'),
  (185, ' ', ''),
  (186, '+', '    pub fn is_stale(&self) -> bool {'),
  (187, '+', '        self.stale_since.is_some()'),
  (188, '+', '    }'),
  (189, ' ', '}'),
];

/// A file preview with a pending edit. A plain mono placeholder for the
/// transcript group's diff view.
class FakeFilePane extends StatelessWidget {
  const FakeFilePane({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.bb;
    return Column(
      children: [
        ConstrainedBox(
          constraints: BoxConstraints(minHeight: ControlSize.lg.height),
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: Border(bottom: BorderSide(color: t.seam)),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(Space.md, 0, Space.sm, 0),
              child: Row(
                children: [
                  Text(
                    'Pending edit',
                    style: ts(
                      t.typeScale.uiSmall,
                      t.attentionInk,
                      weight: Weight.semibold,
                    ),
                  ),
                  const Gap(Space.sm),
                  Flexible(
                    child: Text(
                      '…/src/usage/mod.rs',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: _mono(t, t.muted),
                    ),
                  ),
                  const Gap(Space.sm),
                  Text('+8', style: _mono(t, t.constructiveInk)),
                  const Gap(Space.xs),
                  Text('−3', style: _mono(t, t.dangerInk)),
                ],
              ),
            ),
          ),
        ),
        Expanded(
          child: ClipRect(
            child: SingleChildScrollView(
              physics: const ClampingScrollPhysics(),
              padding: const EdgeInsets.only(top: Space.xs, bottom: Space.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final (n, sign, text) in _file)
                    _FileLine(n: n, sign: sign, text: text),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _FileLine extends StatelessWidget {
  const _FileLine({required this.n, required this.sign, required this.text});

  final int? n;
  final String sign;
  final String text;

  @override
  Widget build(BuildContext context) {
    final t = context.bb;
    final add = sign == '+';
    final del = sign == '-';
    final ink = add
        ? t.constructiveInk
        : del
        ? t.dangerInk
        : t.ink;
    final base = _mono(t, ink, large: true);
    return ColoredBox(
      color: add
          ? t.constructive
          : del
          ? t.danger
          : kTransparent,
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: t.typeScale.code.line),
        child: Row(
          children: [
            SizedBox(
              width: FakePane.diffGutter,
              child: Padding(
                padding: const EdgeInsets.only(right: Space.sm),
                child: Text(
                  n == null ? '' : '$n',
                  textAlign: TextAlign.right,
                  style: base.copyWith(color: t.faint),
                ),
              ),
            ),
            SizedBox(
              width: FakePane.diffSign,
              child: Text(
                sign.trim(),
                textAlign: TextAlign.center,
                style: base.copyWith(color: add || del ? ink : t.faint),
              ),
            ),
            Expanded(
              child: Text(
                text,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.clip,
                style: base.copyWith(
                  decoration: del ? TextDecoration.lineThrough : null,
                  decorationColor: ink,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The Activity pane: what is still running, with the kit's status marks.
class FakeActivityPane extends StatelessWidget {
  const FakeActivityPane({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.bb;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Space.lg,
        vertical: Space.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Still running', style: ts(t.typeScale.uiSmall, t.faint)),
          const Gap(Space.sm),
          const StatusMark(
            ChatStatus.running,
            label: 'Survey quota handling in Codex',
            detail: '1m',
          ),
          const Gap(Space.xs),
          const StatusMark(
            ChatStatus.done,
            label: 'Map UsageState transitions',
            detail: '2m',
          ),
          const Gap(Space.xs),
          const StatusMark(
            ChatStatus.failed,
            label: 'cargo test -p harbor-runtime usage',
            detail: 'exit 101',
          ),
        ],
      ),
    );
  }
}

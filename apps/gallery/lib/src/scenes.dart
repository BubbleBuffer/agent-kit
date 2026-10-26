// The gallery's scenes: the mockup's four (A workbench, B Scratch pane,
// C phone, D workspace) as placeholders that fill in as the compositions are
// built, and a Components scene listing each widget in each state.

import 'package:agent_kit/agent_kit.dart';
import 'package:agent_kit_core/agent_kit_core.dart' show ChatSnapshot;
import 'package:bb_ui/bb_ui.dart';
import 'package:flutter/widgets.dart';

import 'components_scene.dart';

enum GalleryScene {
  workbench('A', 'Workbench', 'AgentWorkbench', 1440, 'a-workbench-*.png', [
    'Rail, chat sheet and the "Still running" ledger side by side.',
    'Folds to rail + crew strip when medium, to a sliding rail when compact.',
  ]),
  scratchPane(
    'B',
    'Scratch pane',
    'AgentChatPane',
    1440,
    'b-scratch-pane-*.png',
    [
      'One chat docked beside a note: about 400 px, so compact by the size rule.',
      'Always the crew strip; never the rail or the ledger.',
    ],
  ),
  phone('C', 'Phone', 'AgentWorkbench, 390 px', 390, 'c-phone-*.png', [
    'The same workbench in a phone-wide container: edge-to-edge sheet,',
    'stacked approval actions, the rail as a sliding screen.',
  ]),
  workspace(
    'D',
    'Workspace',
    'AgentWorkbench + workspace',
    1600,
    'd-workspace-*.png',
    [
      'The split tree of panes beside the chat: browser, terminal, file.',
      'Dividers, docking by drag, collapse to 28 px edge tabs.',
    ],
  ),
  components('+', 'Components', 'Every widget, every state', 1000, '', []);

  const GalleryScene(
    this.tag,
    this.label,
    this.composition,
    this.presetWidth,
    this.mockupShot,
    this.contents,
  );

  /// The mockup's letter ("+" for the components scene).
  final String tag;
  final String label;

  /// What this scene will show once built.
  final String composition;

  /// The width of the mockup shot, in logical px.
  final double presetWidth;

  /// The mockup shots to compare with, in `lab/design/scratch-skin/shots/`.
  final String mockupShot;

  /// Placeholder notes on what the scene will contain.
  final List<String> contents;

  /// The file stem used for screenshots of this scene.
  String get slug => switch (this) {
    workbench => 'a_workbench',
    scratchPane => 'b_scratch_pane',
    phone => 'c_phone',
    workspace => 'd_workspace',
    components => 'components',
  };
}

/// Builds [scene] for the chat state [snapshot] (null until it loads).
Widget buildScene(GalleryScene scene, ChatSnapshot? snapshot) =>
    scene == GalleryScene.components
    ? const ComponentsScene()
    : ScenePlaceholder(scene: scene, snapshot: snapshot);

/// A scene that is not built yet: names the composition and shows the live
/// state of the fake backend's chat, so the plumbing is visible.
class ScenePlaceholder extends StatelessWidget {
  const ScenePlaceholder({super.key, required this.scene, this.snapshot});

  final GalleryScene scene;
  final ChatSnapshot? snapshot;

  @override
  Widget build(BuildContext context) {
    final t = context.bb;
    final s = snapshot;
    final small = ts(t.typeScale.uiSmall, t.muted);
    return ColoredBox(
      color: t.canvas,
      child: Padding(
        padding: EdgeInsets.all(t.spacing.md),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: t.surface,
            borderRadius: BorderRadius.circular(t.radii.sheet),
            border: Border.all(color: t.seam),
            boxShadow: t.colors.stack,
          ),
          child: SizedBox.expand(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(t.spacing.xl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Scene ${scene.tag} · ${scene.composition}',
                    style: small,
                  ),
                  SizedBox(height: t.spacing.sm),
                  Text(
                    s == null || s.title.isEmpty
                        ? 'Loading the scripted chat…'
                        : s.title,
                    style: ts(t.typeScale.h3, t.ink),
                  ),
                  SizedBox(height: t.spacing.sm),
                  if (s != null) ...[
                    StatusMark.pill(s.status),
                    SizedBox(height: t.spacing.sm),
                    Text(
                      '${s.items.length} items · '
                      '${s.children.length} agents · '
                      '${s.jobs.length} jobs · '
                      '${s.queue.length} queued · '
                      '${s.approvals.length} approval',
                      style: small,
                    ),
                  ],
                  SizedBox(height: t.spacing.lg),
                  const _AreaLine(),
                  SizedBox(height: t.spacing.lg),
                  Text('Placeholder. It will contain:', style: small),
                  SizedBox(height: t.spacing.xs),
                  for (final line in scene.contents)
                    Text(line, style: ts(t.typeScale.ui, t.ink, weight: 400)),
                  SizedBox(height: t.spacing.lg),
                  Text(
                    'Compare with shots/${scene.mockupShot} in the mockup.',
                    style: small,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Shows the width of its own area and the size class it gives.
class _AreaLine extends StatelessWidget {
  const _AreaLine();

  @override
  Widget build(BuildContext context) => SizeClassBuilder(
    builder: (context, sizeClass) => LayoutBuilder(
      builder: (context, constraints) => Text(
        'Area ${constraints.maxWidth.round()} px → ${sizeClass.name}',
        style: ts(const TypeSpec(12, 16, 400), context.bb.ink, mono: true),
      ),
    ),
  );
}

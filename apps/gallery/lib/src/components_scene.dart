// The Components scene: each widget in each state. A widget joins the kit
// with a specimen here (see docs/agent-kit.md).

import 'package:agent_kit/agent_kit.dart';
import 'package:agent_kit_core/agent_kit_core.dart' show ChatStatus;
import 'package:bb_ui/bb_ui.dart';
import 'package:flutter/widgets.dart';

import '../components/chrome.dart';
import '../components/composer.dart';
import '../components/transcript.dart';
import '../components/workspace.dart';

class ComponentsScene extends StatelessWidget {
  const ComponentsScene({super.key, this.tall = false});

  /// Whether to size to the content instead of scrolling inside the window.
  final bool tall;

  @override
  Widget build(BuildContext context) {
    final t = context.bb;
    final sheet = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _Heading('StatusMark'),
        const _StatusSpecimens(),
        const TranscriptSpecimens(),
        SizedBox(height: t.spacing.xl),
        const ComposerSpecimens(),
        SizedBox(height: t.spacing.xl),
        const _Heading('Workspace'),
        const WorkspaceSpecimens(),
        SizedBox(height: t.spacing.xl),
        const _Heading('Chrome'),
        const ChromeSpecimens(),
      ],
    );
    final scene = ColoredBox(
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
          child: tall
              ? Padding(padding: EdgeInsets.all(t.spacing.xl), child: sheet)
              : SizedBox.expand(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.all(t.spacing.xl),
                    child: sheet,
                  ),
                ),
        ),
      ),
    );
    // A boundary of its own, so a golden can shoot the whole sheet.
    return tall ? RepaintBoundary(child: scene) : scene;
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final t = context.bb;
    return Padding(
      padding: EdgeInsets.only(bottom: t.spacing.md),
      child: Text(text, style: ts(t.typeScale.h3, t.ink)),
    );
  }
}

/// Every status in the dot form, the dot form with a detail and the pill.
class _StatusSpecimens extends StatelessWidget {
  const _StatusSpecimens();

  @override
  Widget build(BuildContext context) {
    final t = context.bb;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final s in ChatStatus.values)
          Padding(
            padding: EdgeInsets.only(bottom: t.spacing.md),
            child: Wrap(
              spacing: t.spacing.lg,
              runSpacing: t.spacing.sm,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                SizedBox(
                  width: 96,
                  child: Text(
                    s.name,
                    style: ts(const TypeSpec(12, 16, 400), t.faint, mono: true),
                  ),
                ),
                SizedBox(width: 170, child: StatusMark(s)),
                SizedBox(width: 190, child: StatusMark(s, detail: '3 agents')),
                StatusMark.pill(s),
              ],
            ),
          ),
      ],
    );
  }
}

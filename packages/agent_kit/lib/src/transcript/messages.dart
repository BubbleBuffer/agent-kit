// Messages and lines: the user's bubble, the assistant's prose, system and
// notice lines (`.turn-user`, `.bubble`, `.prose` in the mockup).

import 'dart:math' as math;

import 'package:agent_kit_core/agent_kit_core.dart'
    show
        AssistantMessage,
        KitRef,
        NoticeLine,
        NoticeTone,
        SystemLine,
        UserMessage;
import 'package:bb_ui/bb_ui.dart';
import 'package:flutter/widgets.dart';

import '../theme/theme.dart';
import 'markdown.dart';
import 'transcript_support.dart';

/// What the user sent: attached context as chips above, then the bubble,
/// right-aligned.
class UserBubble extends StatelessWidget {
  const UserBubble(this.message, {super.key, this.onRefTap});

  final UserMessage message;

  /// A context chip was tapped.
  final ValueChanged<KitRef>? onRefTap;

  @override
  Widget build(BuildContext context) {
    final t = context.bb;
    final chips = message.refs
        .where((r) => r.start == null)
        .toList(growable: false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (chips.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Wrap(
              alignment: WrapAlignment.end,
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final ref in chips)
                  _ContextChip(ref: ref, onTap: onRefTap),
              ],
            ),
          ),
        LayoutBuilder(
          builder: (context, constraints) {
            final max = constraints.hasBoundedWidth
                ? math.min(560.0, constraints.maxWidth * .85)
                : 560.0;
            return ConstrainedBox(
              constraints: BoxConstraints(maxWidth: max),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: t.surface2,
                  borderRadius: t.radii.panel,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 9,
                  ),
                  child: Text(
                    message.text,
                    style: ts(t.typeScale.body, t.ink),
                  ),
                ),
              ),
            );
          },
        ),
      ],
    );
  }
}

class _ContextChip extends StatelessWidget {
  const _ContextChip({required this.ref, this.onTap});

  final KitRef ref;
  final ValueChanged<KitRef>? onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.bb;
    final tap = onTap;
    return Semantics(
      button: tap != null,
      label: ref.label,
      excludeSemantics: true,
      child: Hover(
        onTap: tap == null ? null : () => tap(ref),
        lift: 0,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: t.colors.borderSubtle),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            glyphIcon(glyphFileText, size: 12, color: t.muted),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                ref.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: ts(t.typeScale.uiSmall, t.muted),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The assistant's prose, rendered by [renderer].
class AssistantProse extends StatelessWidget {
  const AssistantProse(
    this.message, {
    super.key,
    this.renderer = const LeanMarkdownRenderer(),
    this.onLinkTap,
  });

  final AssistantMessage message;
  final MarkdownRenderer renderer;
  final ValueChanged<String>? onLinkTap;

  @override
  Widget build(BuildContext context) => renderer.build(
    context,
    message.markdown,
    streaming: message.streaming,
    onLinkTap: onLinkTap,
  );
}

/// A system line: small, centred, faint ("Context compacted").
class SystemLineView extends StatelessWidget {
  const SystemLineView(this.line, {super.key});

  final SystemLine line;

  @override
  Widget build(BuildContext context) {
    final t = context.bb;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Text(
        line.text,
        textAlign: TextAlign.center,
        style: ts(t.typeScale.uiSmall, t.faint),
      ),
    );
  }
}

/// A notice line: an icon and text in the tone's ink. Only success and
/// danger carry an icon; info is muted text and warning uses the attention
/// ink (the warm accent stays with "needs you").
class NoticeLineView extends StatelessWidget {
  const NoticeLineView(this.line, {super.key});

  final NoticeLine line;

  @override
  Widget build(BuildContext context) {
    final t = context.bb;
    final ink = switch (line.tone) {
      NoticeTone.info => t.muted,
      NoticeTone.success => t.constructiveInk,
      NoticeTone.warning => t.attentionInk,
      NoticeTone.danger => t.dangerInk,
    };
    final glyph = switch (line.tone) {
      NoticeTone.success => glyphCircleCheck,
      NoticeTone.danger => glyphCircleX,
      _ => null,
    };
    return Semantics(
      container: true,
      label: line.text,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (glyph != null)
            Padding(
              padding: const EdgeInsets.only(top: 2, right: 6),
              child: glyphIcon(glyph, size: 12, color: ink),
            ),
          Expanded(
            child: Text(
              line.text,
              style: ts(t.typeScale.uiSmall, ink, weight: 500),
            ),
          ),
        ],
      ),
    );
  }
}

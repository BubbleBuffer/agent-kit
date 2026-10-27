// Tool output (`pre.out` and `.ev-foot` in the mockup): a mono block clamped
// to 12 lines of 18 px with a fade, a footer with the size and the exit status
// (in danger when it failed), "Show all N lines" and "Open full output".

import 'package:agent_kit_core/agent_kit_core.dart' show ToolOutput;
import 'package:bb_ui/bb_ui.dart';
import 'package:flutter/widgets.dart';

import '../theme/theme.dart';
import 'transcript_support.dart';

final _badLine = RegExp(r'\bFAILED\b|^error\b|\bpanicked at\b');

class ExecOutput extends StatefulWidget {
  const ExecOutput({
    super.key,
    required this.output,
    this.exitCode,
    this.clampLines = 12,
    this.onShowAll,
    this.onOpenFull,
  });

  final ToolOutput output;

  /// The process's exit code; a non-zero one shows in danger.
  final int? exitCode;

  /// Lines shown before the fade.
  final int clampLines;

  /// "Show all N lines" was pressed. The block also opens in place.
  final VoidCallback? onShowAll;

  /// "Open full output": show the whole output somewhere else (a terminal
  /// pane). The button is hidden without it.
  final VoidCallback? onOpenFull;

  @override
  State<ExecOutput> createState() => _ExecOutputState();
}

class _ExecOutputState extends State<ExecOutput> {
  bool _expanded = false;

  static const _lineHeight = 18.0;
  static const _fade = 36.0;

  @override
  Widget build(BuildContext context) {
    final t = context.bb;
    final out = widget.output;
    var lines = out.text.split('\n');
    if (lines.isNotEmpty && lines.last.isEmpty) lines.removeLast();
    final total = out.totalLines ?? lines.length;
    final clamped = !_expanded && lines.length > widget.clampLines;
    if (clamped) lines = lines.sublist(0, widget.clampLines);

    const spec = TypeSpec(12, _lineHeight, 400);
    final base = monoStyle(spec, t.muted);
    final bad = base.copyWith(color: t.dangerInk);
    final text = Text.rich(
      TextSpan(
        children: [
          for (var i = 0; i < lines.length; i++)
            TextSpan(
              text: i == lines.length - 1 ? lines[i] : '${lines[i]}\n',
              style: _badLine.hasMatch(lines[i]) ? bad : base,
            ),
        ],
        style: base,
      ),
      softWrap: false,
    );
    Widget block = DecoratedBox(
      decoration: BoxDecoration(
        color: t.surface2,
        borderRadius: BorderRadius.circular(t.radii.sm),
      ),
      child: SizedBox(
        width: double.infinity,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: text,
        ),
      ),
    );
    if (clamped) {
      block = ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (rect) {
          final h = rect.height;
          final stop = h <= _fade ? 0.0 : (h - _fade) / h;
          return LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: const [kMaskOpaque, kMaskOpaque, kTransparent],
            stops: [0, stop, 1],
          ).createShader(rect);
        },
        child: block,
      );
    }

    final exit = widget.exitCode;
    final failed = exit != null && exit != 0;
    final bytes = out.totalBytes;
    final metaStyle = ts(t.typeScale.uiSmall, t.faint);
    final meta = <Widget>[
      if (bytes != null) Text(formatBytes(bytes), style: metaStyle),
      if (bytes != null && failed) Text('·', style: metaStyle),
      if (failed)
        Text('exited $exit', style: metaStyle.copyWith(color: t.dangerInk)),
    ];
    final showAllLabel = _expanded
        ? 'Show fewer lines'
        : 'Show all $total lines';
    final buttons = <Widget>[
      if (lines.isNotEmpty && (clamped || _expanded))
        KitTextButton(
          showAllLabel,
          onTap: () {
            setState(() => _expanded = !_expanded);
            if (_expanded) widget.onShowAll?.call();
          },
        ),
      if (widget.onOpenFull != null)
        KitTextButton(
          'Open full output',
          glyph: glyphTerminal,
          onTap: widget.onOpenFull,
        ),
    ];

    return Semantics(
      container: true,
      label: 'Output, $total lines${failed ? ', exited $exit' : ''}',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          block,
          if (meta.isNotEmpty || buttons.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Wrap(
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 4,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var i = 0; i < meta.length; i++) ...[
                        if (i > 0) const SizedBox(width: 8),
                        meta[i],
                      ],
                    ],
                  ),
                  Row(mainAxisSize: MainAxisSize.min, children: buttons),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

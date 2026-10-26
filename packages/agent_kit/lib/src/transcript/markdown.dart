// Markdown behind an interface. The default renderer is lean: paragraphs,
// headings, bullet and numbered lists, block quotes, fenced code, rules, and
// `code`, **bold**, *italic* and [links](url) inline. Anything richer (tables,
// images, syntax colours) is a host's own MarkdownRenderer.

import 'package:bb_ui/bb_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart';

import '../theme/theme.dart';
import 'code_block.dart';
import 'transcript_support.dart';

/// Turns markdown text into widgets (`.prose` in the mockup). The kit calls
/// it for assistant messages and child results.
abstract interface class MarkdownRenderer {
  /// Builds [markdown]. [streaming] is true while the text is still arriving,
  /// so an unfinished construct (an open code fence) must render as it is.
  /// [onLinkTap] gets the target of a tapped link.
  Widget build(
    BuildContext context,
    String markdown, {
    bool streaming = false,
    ValueChanged<String>? onLinkTap,
  });
}

/// The default [MarkdownRenderer].
class LeanMarkdownRenderer implements MarkdownRenderer {
  const LeanMarkdownRenderer();

  @override
  Widget build(
    BuildContext context,
    String markdown, {
    bool streaming = false,
    ValueChanged<String>? onLinkTap,
  }) => _Prose(blocks: parseMarkdownBlocks(markdown), onLinkTap: onLinkTap);
}

// ---------------------------------------------------------------- blocks

sealed class MdBlock {
  const MdBlock();
}

class MdParagraph extends MdBlock {
  const MdParagraph(this.text);
  final String text;
}

class MdHeading extends MdBlock {
  const MdHeading(this.level, this.text);
  final int level;
  final String text;
}

class MdListItem {
  const MdListItem(this.level, this.text);
  final int level;
  final String text;
}

class MdList extends MdBlock {
  const MdList({required this.ordered, required this.items, this.start = 1});
  final bool ordered;
  final int start;
  final List<MdListItem> items;
}

class MdQuote extends MdBlock {
  const MdQuote(this.text);
  final String text;
}

class MdCode extends MdBlock {
  const MdCode(this.code, this.language);
  final String code;
  final String? language;
}

class MdRule extends MdBlock {
  const MdRule();
}

final _fence = RegExp(r'^\s*(`{3,}|~{3,})\s*([^`\s]*)');
final _heading = RegExp(r'^\s{0,3}(#{1,6})\s+(.*?)\s*#*\s*$');
final _bullet = RegExp(r'^(\s*)[-*+]\s+(.*)$');
final _numbered = RegExp(r'^(\s*)(\d{1,9})[.)]\s+(.*)$');
final _quote = RegExp(r'^\s{0,3}>\s?(.*)$');
final _rule = RegExp(r'^\s{0,3}([-*_])(\s*\1){2,}\s*$');

/// Splits [source] into blocks. An unterminated fence runs to the end, so a
/// streaming message renders its code as it arrives.
List<MdBlock> parseMarkdownBlocks(String source) {
  final lines = source.replaceAll('\r\n', '\n').split('\n');
  final blocks = <MdBlock>[];
  final para = <String>[];
  var i = 0;

  void flushPara() {
    if (para.isEmpty) return;
    blocks.add(MdParagraph(para.join(' ')));
    para.clear();
  }

  while (i < lines.length) {
    final line = lines[i];
    final fence = _fence.firstMatch(line);
    if (fence != null) {
      flushPara();
      final marker = fence.group(1)!;
      final lang = fence.group(2);
      final body = <String>[];
      i++;
      while (i < lines.length &&
          !lines[i].trimLeft().startsWith(marker[0] * marker.length)) {
        body.add(lines[i]);
        i++;
      }
      i++; // the closing fence, or past the end
      blocks.add(
        MdCode(body.join('\n'), lang == null || lang.isEmpty ? null : lang),
      );
      continue;
    }
    if (line.trim().isEmpty) {
      flushPara();
      i++;
      continue;
    }
    if (_rule.hasMatch(line) && !_bullet.hasMatch(line)) {
      flushPara();
      blocks.add(const MdRule());
      i++;
      continue;
    }
    final head = _heading.firstMatch(line);
    if (head != null) {
      flushPara();
      blocks.add(MdHeading(head.group(1)!.length, head.group(2)!));
      i++;
      continue;
    }
    if (_quote.hasMatch(line)) {
      flushPara();
      final quoted = <String>[];
      while (i < lines.length && _quote.hasMatch(lines[i])) {
        quoted.add(_quote.firstMatch(lines[i])!.group(1)!);
        i++;
      }
      blocks.add(MdQuote(quoted.join(' ')));
      continue;
    }
    if (_bullet.hasMatch(line) || _numbered.hasMatch(line)) {
      flushPara();
      final ordered = !_bullet.hasMatch(line);
      final items = <MdListItem>[];
      var start = 1;
      if (ordered) start = int.parse(_numbered.firstMatch(line)!.group(2)!);
      while (i < lines.length) {
        final l = lines[i];
        final b = _bullet.firstMatch(l);
        final n = _numbered.firstMatch(l);
        if (b != null || n != null) {
          final indent = (b?.group(1) ?? n!.group(1)!).length;
          final text = b?.group(2) ?? n!.group(3)!;
          items.add(MdListItem((indent ~/ 2).clamp(0, 3).toInt(), text));
          i++;
        } else if (l.trim().isNotEmpty &&
            l.startsWith('  ') &&
            items.isNotEmpty) {
          final last = items.removeLast();
          items.add(MdListItem(last.level, '${last.text} ${l.trim()}'));
          i++;
        } else {
          break;
        }
      }
      blocks.add(MdList(ordered: ordered, items: items, start: start));
      continue;
    }
    para.add(line.trim());
    i++;
  }
  flushPara();
  return blocks;
}

// ---------------------------------------------------------------- inline

/// A run of inline markdown.
class MdSpan {
  const MdSpan(
    this.text, {
    this.bold = false,
    this.italic = false,
    this.code = false,
    this.link,
  });
  final String text;
  final bool bold, italic, code;
  final String? link;
}

/// Splits one block's text into styled runs.
List<MdSpan> parseMarkdownInline(String s) {
  final out = <MdSpan>[];
  final buf = StringBuffer();
  void flush() {
    if (buf.isEmpty) return;
    out.add(MdSpan(buf.toString()));
    buf.clear();
  }

  var i = 0;
  while (i < s.length) {
    final ch = s[i];
    if (ch == r'\' && i + 1 < s.length && r'\`*_[]()#>-+!'.contains(s[i + 1])) {
      buf.write(s[i + 1]);
      i += 2;
      continue;
    }
    if (ch == '`') {
      var n = 1;
      while (i + n < s.length && s[i + n] == '`') {
        n++;
      }
      final ticks = '`' * n;
      final close = s.indexOf(ticks, i + n);
      if (close > i + n - 1) {
        flush();
        out.add(MdSpan(s.substring(i + n, close).trim(), code: true));
        i = close + n;
        continue;
      }
    }
    if (ch == '*' && i + 1 < s.length) {
      final strong = s.startsWith('**', i);
      final mark = strong ? '**' : '*';
      final close = s.indexOf(mark, i + mark.length);
      if (close > i + mark.length && s[i + mark.length] != ' ') {
        flush();
        final inner = parseMarkdownInline(s.substring(i + mark.length, close));
        for (final m in inner) {
          out.add(
            MdSpan(
              m.text,
              bold: m.bold || strong,
              italic: m.italic || !strong,
              code: m.code,
              link: m.link,
            ),
          );
        }
        i = close + mark.length;
        continue;
      }
    }
    if (ch == '[') {
      final mid = s.indexOf('](', i + 1);
      final end = mid < 0 ? -1 : s.indexOf(')', mid + 2);
      if (mid > 0 && end > 0) {
        flush();
        final label = s.substring(i + 1, mid);
        final target = s.substring(mid + 2, end).trim();
        for (final m in parseMarkdownInline(label)) {
          out.add(
            MdSpan(
              m.text,
              bold: m.bold,
              italic: m.italic,
              code: m.code,
              link: target,
            ),
          );
        }
        i = end + 1;
        continue;
      }
    }
    buf.write(ch);
    i++;
  }
  flush();
  return out;
}

// ---------------------------------------------------------------- widgets

class _Prose extends StatelessWidget {
  const _Prose({required this.blocks, this.onLinkTap});

  final List<MdBlock> blocks;
  final ValueChanged<String>? onLinkTap;

  @override
  Widget build(BuildContext context) {
    final t = context.bb;
    final children = <Widget>[];
    for (final b in blocks) {
      if (children.isNotEmpty) children.add(const SizedBox(height: 10));
      children.add(switch (b) {
        MdParagraph(:final text) => MarkdownText(
          text,
          style: ts(t.typeScale.body, t.ink),
          onLinkTap: onLinkTap,
        ),
        MdHeading(:final level, :final text) => MarkdownText(
          text,
          style: level <= 2
              ? ts(t.typeScale.h3, t.ink)
              : ts(t.typeScale.body, t.ink, weight: 700),
          onLinkTap: onLinkTap,
        ),
        final MdList l => _ListBlock(list: l, onLinkTap: onLinkTap),
        MdQuote(:final text) => DecoratedBox(
          decoration: BoxDecoration(
            border: Border(left: BorderSide(color: t.thread, width: 3)),
          ),
          child: Padding(
            padding: const EdgeInsets.only(left: 12),
            child: MarkdownText(
              text,
              style: ts(t.typeScale.body, t.muted),
              onLinkTap: onLinkTap,
            ),
          ),
        ),
        MdCode(:final code, :final language) => CodeBlock(
          code,
          language: language,
        ),
        MdRule() => SizedBox(
          height: 1,
          width: double.infinity,
          child: ColoredBox(color: t.seam),
        ),
      });
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: children,
    );
  }
}

class _ListBlock extends StatelessWidget {
  const _ListBlock({required this.list, this.onLinkTap});

  final MdList list;
  final ValueChanged<String>? onLinkTap;

  @override
  Widget build(BuildContext context) {
    final t = context.bb;
    final style = ts(t.typeScale.body, t.ink);
    final counters = List<int>.filled(4, 0);
    final rows = <Widget>[];
    for (final item in list.items) {
      final marker = list.ordered
          ? '${list.start + counters[item.level]++}.'
          : '•';
      for (var l = item.level + 1; l < counters.length; l++) {
        counters[l] = 0;
      }
      rows.add(
        Padding(
          padding: EdgeInsets.only(
            left: 6.0 + item.level * 18,
            top: rows.isEmpty ? 0 : 4,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 16,
                child: Text(
                  marker,
                  textAlign: list.ordered ? TextAlign.start : TextAlign.center,
                  style: style.copyWith(color: t.faint),
                ),
              ),
              Expanded(
                child: MarkdownText(
                  item.text,
                  style: style,
                  onLinkTap: onLinkTap,
                ),
              ),
            ],
          ),
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: rows,
    );
  }
}

/// Inline markdown as one paragraph of rich text.
class MarkdownText extends StatefulWidget {
  const MarkdownText(
    this.text, {
    super.key,
    required this.style,
    this.onLinkTap,
  });

  final String text;
  final TextStyle style;
  final ValueChanged<String>? onLinkTap;

  @override
  State<MarkdownText> createState() => _MarkdownTextState();
}

class _MarkdownTextState extends State<MarkdownText> {
  final List<TapGestureRecognizer> _recognizers = [];

  void _disposeRecognizers() {
    for (final r in _recognizers) {
      r.dispose();
    }
    _recognizers.clear();
  }

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final t = context.bb;
    _disposeRecognizers();
    final base = widget.style;
    final size = base.fontSize ?? 16;
    final spans = <InlineSpan>[];
    for (final m in parseMarkdownInline(widget.text)) {
      if (m.code) {
        spans.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.baseline,
            baseline: TextBaseline.alphabetic,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: t.codeBackground,
                borderRadius: BorderRadius.circular(t.radii.sm),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                child: Text(
                  m.text,
                  style: monoStyle(
                    TypeSpec(size * .85, size * 1.2, 400),
                    t.codeInk,
                  ),
                ),
              ),
            ),
          ),
        );
        continue;
      }
      var style = base.copyWith(
        fontWeight: m.bold ? fw(700) : null,
        fontStyle: m.italic ? FontStyle.italic : null,
      );
      TapGestureRecognizer? recognizer;
      final link = m.link;
      if (link != null) {
        style = style.copyWith(
          color: t.accentInk,
          decoration: TextDecoration.underline,
          decorationColor: t.accentInk,
        );
        final tap = widget.onLinkTap;
        if (tap != null) {
          recognizer = TapGestureRecognizer()..onTap = () => tap(link);
          _recognizers.add(recognizer);
        }
      }
      spans.add(TextSpan(text: m.text, style: style, recognizer: recognizer));
    }
    return Text.rich(TextSpan(children: spans, style: base));
  }
}

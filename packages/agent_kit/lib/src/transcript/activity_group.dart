// The activity group (`.activity` in the mockup): one summary line
// ("Worked 48s · thought 6s · 7 tool calls") that opens into evidence rows
// (think, read, grep, exec, spawn), each with a right-aligned meta. One row is
// open at a time. An exec row opens into its clamped output, a thinking row
// into its reasoning text when the backend sends it.

import 'package:agent_kit_core/agent_kit_core.dart'
    show
        ActivityGroup,
        ActivityRow,
        ChatStatus,
        SpawnRow,
        ThinkingRow,
        ToolKind,
        ToolRow,
        WorkState;
import 'package:bb_ui/bb_ui.dart';
import 'package:flutter/widgets.dart';

import '../status/status.dart';
import '../theme/theme.dart';
import 'exec_output.dart';
import 'transcript_support.dart';

/// Builds the summary line of a group; see [activitySummary].
typedef ActivitySummaryBuilder = String Function(ActivityGroup group);

/// The summary line of [group], from verb counts: "Searched 2× · Read 3
/// files · Ran 1 command · 1 failed". Time parts are appended only when the
/// backend sent durations: "· Worked 48s · thought 6s". A group with no calls
/// reads "Working" while it runs, "Worked" (with its time) after. A host that
/// wants other wording passes its own [ActivitySummaryBuilder].
String activitySummary(ActivityGroup group) {
  final tools = group.rows.whereType<ToolRow>().toList();
  int count(bool Function(ToolRow) test) => tools.where(test).length;
  String files(int n, String verb) => '$verb $n ${n == 1 ? 'file' : 'files'}';
  final searched = count((r) => r.kind == ToolKind.search);
  final read = count((r) => r.kind == ToolKind.read);
  final edited = count(
    (r) => r.kind == ToolKind.edit || r.kind == ToolKind.write,
  );
  final ran = count((r) => r.kind == ToolKind.exec);
  final web = count((r) => r.kind == ToolKind.web);
  final other = count((r) => r.kind == ToolKind.other);
  final spawned = group.spawns;
  final failed = count((r) => r.state == WorkState.failed);
  final parts = <String>[
    if (searched > 0) 'Searched $searched×',
    if (read > 0) files(read, 'Read'),
    if (edited > 0) files(edited, 'Edited'),
    if (ran > 0) 'Ran $ran ${ran == 1 ? 'command' : 'commands'}',
    if (web > 0) 'Looked up $web×',
    if (spawned > 0) 'Started $spawned ${spawned == 1 ? 'agent' : 'agents'}',
    if (other > 0) '$other other ${other == 1 ? 'call' : 'calls'}',
    if (failed > 0) '$failed failed',
  ];
  final ms = group.isRunning ? null : _elapsedMs(group);
  if (parts.isEmpty) {
    parts.add(
      group.isRunning
          ? 'Working'
          : ms == null
          ? 'Worked'
          : 'Worked ${formatDuration(ms)}',
    );
  } else if (ms != null) {
    parts.add('Worked ${formatDuration(ms)}');
  }
  if (group.thinkingMs > 0) {
    parts.add('thought ${formatDuration(group.thinkingMs)}');
  }
  return parts.join(' · ');
}

int? _elapsedMs(ActivityGroup group) {
  DateTime? start = group.at;
  DateTime? end;
  for (final row in group.rows.whereType<ToolRow>()) {
    final s = row.startedAt;
    final e = row.endedAt;
    if (s != null && (start == null || s.isBefore(start))) start = s;
    if (e != null && (end == null || e.isAfter(end))) end = e;
  }
  if (start == null || end == null) return null;
  final ms = end.difference(start).inMilliseconds;
  return ms < 0 ? null : ms;
}

class ActivityGroupView extends StatefulWidget {
  const ActivityGroupView(
    this.group, {
    super.key,
    this.initiallyOpen,
    this.initiallyOpenRow,
    this.onOpenOutput,
    this.onOpenChild,
    this.summaryOf,
  });

  final ActivityGroup group;

  /// Whether the evidence starts open; by default while the group runs.
  final bool? initiallyOpen;

  /// The id of the row that starts open.
  final String? initiallyOpenRow;

  /// "Open full output" of an exec row.
  final ValueChanged<ToolRow>? onOpenOutput;

  /// A spawn row was tapped; gets the child's id.
  final ValueChanged<String>? onOpenChild;

  /// Replaces the summary line (see [activitySummary], the default).
  final ActivitySummaryBuilder? summaryOf;

  @override
  State<ActivityGroupView> createState() => _ActivityGroupViewState();
}

class _ActivityGroupViewState extends State<ActivityGroupView> {
  late bool _open = widget.initiallyOpen ?? widget.group.isRunning;
  late String? _openRow = widget.initiallyOpenRow;

  @override
  Widget build(BuildContext context) {
    final t = context.bb;
    final group = widget.group;
    final compact = sizeClassOf(context).isCompact;
    final summary = (widget.summaryOf ?? activitySummary)(group);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: Transform.translate(
            offset: const Offset(-6, 0),
            child: Semantics(
              button: true,
              expanded: _open,
              label: summary,
              excludeSemantics: true,
              child: Hover(
                onTap: () => setState(() => _open = !_open),
                lift: 0,
                padding: EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: isTouch(context) ? 9 : 5,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DisclosureChevron(open: _open),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        summary,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: ts(t.typeScale.uiSmall, t.faint),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (_open && group.rows.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2, left: 6),
            child: DecoratedBox(
              decoration: BoxDecoration(
                border: Border(left: BorderSide(color: t.colors.borderSubtle)),
              ),
              child: Padding(
                padding: const EdgeInsets.only(left: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final row in group.rows)
                      EvidenceRow(
                        key: ValueKey(row.id),
                        row: row,
                        compact: compact,
                        open: _openRow == row.id,
                        onToggle: () => setState(
                          () => _openRow = _openRow == row.id ? null : row.id,
                        ),
                        onOpenOutput: widget.onOpenOutput,
                        onOpenChild: widget.onOpenChild,
                      ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// One evidence row: a mono verb, the target, and a right-aligned meta.
/// Expands when it has a body (output, reasoning text).
class EvidenceRow extends StatelessWidget {
  const EvidenceRow({
    super.key,
    required this.row,
    this.compact = false,
    this.open = false,
    this.onToggle,
    this.onOpenOutput,
    this.onOpenChild,
  });

  final ActivityRow row;
  final bool compact;
  final bool open;
  final VoidCallback? onToggle;
  final ValueChanged<ToolRow>? onOpenOutput;
  final ValueChanged<String>? onOpenChild;

  @override
  Widget build(BuildContext context) {
    final t = context.bb;
    final spec = _specOf(row);
    final expandable = spec.body != null;
    final tap = switch (row) {
      SpawnRow(:final childId) =>
        onOpenChild == null ? null : () => onOpenChild!(childId),
      _ => expandable ? onToggle : null,
    };
    final metaStyle = ts(t.typeScale.uiSmall, t.faint);
    final meta = spec.meta(context, metaStyle);
    final targetStyle = ts(const TypeSpec(13, 16, 500), open ? t.ink : t.muted);
    Widget? body;
    if (open && expandable) {
      body = Padding(
        padding: EdgeInsets.fromLTRB(compact ? 0 : 58, 2, 0, 8),
        child: spec.body!(context),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          button: tap != null,
          expanded: expandable ? open : null,
          label: '${spec.verb} ${spec.target}',
          excludeSemantics: true,
          child: Hover(
            onTap: tap,
            lift: 0,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                minHeight: isTouch(context) ? 36 : 20,
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: compact ? 40 : 44,
                    child: Text(
                      spec.verb,
                      maxLines: 1,
                      style: monoStyle(const TypeSpec(12, 16, 400), t.faint),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      spec.target,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: targetStyle,
                    ),
                  ),
                  if (meta != null) ...[const SizedBox(width: 8), meta],
                ],
              ),
            ),
          ),
        ),
        ?body,
      ],
    );
  }

  _RowSpec _specOf(ActivityRow row) => switch (row) {
    final ThinkingRow r => _thinking(r),
    final ToolRow r => _tool(r),
    final SpawnRow r => _RowSpec(
      verb: 'spawn',
      target: r.task,
      meta: (context, style) =>
          Text('child ${_shortId(r.childId)}', maxLines: 1, style: style),
    ),
  };

  _RowSpec _thinking(ThinkingRow r) {
    final text = r.text?.trim() ?? '';
    final hasText = text.isNotEmpty;
    final ms = r.durationMs;
    return _RowSpec(
      verb: 'think',
      target: hasText
          ? _firstLine(text)
          : r.streaming
          ? 'Thinking…'
          : 'Thought',
      meta: (context, style) {
        if (r.streaming) return const StatusMark(ChatStatus.running);
        if (ms == null) return null;
        return Text(formatDuration(ms), maxLines: 1, style: style);
      },
      body: hasText
          ? (context) {
              final t = context.bb;
              return Text(
                text,
                style: ts(const TypeSpec(13, 20, 400), t.muted),
              );
            }
          : null,
    );
  }

  _RowSpec _tool(ToolRow r) {
    final target = r.target ?? r.arguments ?? r.name;
    final exit = r.exitCode;
    final output = r.output;
    return _RowSpec(
      verb: switch (r.kind) {
        ToolKind.read => 'read',
        ToolKind.search => 'grep',
        ToolKind.exec => 'exec',
        ToolKind.edit => 'edit',
        ToolKind.write => 'write',
        ToolKind.web => 'web',
        ToolKind.other => r.name,
      },
      target: target,
      meta: (context, style) {
        final t = context.bb;
        if (exit != null && exit != 0) {
          return Text(
            'exit $exit',
            maxLines: 1,
            style: style.copyWith(color: t.dangerInk),
          );
        }
        return switch (r.state) {
          WorkState.running => StatusMark(
            ChatStatus.running,
            label: r.meta ?? 'running',
          ),
          WorkState.failed || WorkState.timedOut => StatusMark(
            ChatStatus.failed,
            label: r.meta ?? 'failed',
          ),
          WorkState.cancelled => StatusMark(
            ChatStatus.idle,
            label: r.meta ?? 'cancelled',
          ),
          WorkState.done || WorkState.waitingForAnswer || WorkState.idle =>
            r.meta == null ? null : Text(r.meta!, maxLines: 1, style: style),
        };
      },
      body: output != null && output.text.isNotEmpty
          ? (context) => ExecOutput(
              output: output,
              exitCode: exit,
              onOpenFull: onOpenOutput == null ? null : () => onOpenOutput!(r),
            )
          : null,
    );
  }

  static String _firstLine(String text) {
    final line = text.split('\n').firstWhere((l) => l.trim().isNotEmpty);
    return line.trim();
  }

  static String _shortId(String id) =>
      id.length <= 6 ? id : id.substring(id.length - 4);
}

class _RowSpec {
  const _RowSpec({
    required this.verb,
    required this.target,
    required this.meta,
    this.body,
  });

  final String verb;
  final String target;
  final Widget? Function(BuildContext context, TextStyle style) meta;
  final Widget Function(BuildContext context)? body;
}

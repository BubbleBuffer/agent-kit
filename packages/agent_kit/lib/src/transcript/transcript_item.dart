// One transcript item as a widget, and the callbacks the transcript offers
// its host. Widgets take `agent_kit_core` items and callbacks; they never
// reach a backend.

import 'dart:async' show FutureOr;

import 'package:agent_kit_core/agent_kit_core.dart'
    show
        ActivityGroup,
        AssistantMessage,
        ChildQuestionItem,
        ChildResult,
        CompactionItem,
        FileEdit,
        InterruptedItem,
        KitRef,
        NoticeLine,
        SystemLine,
        ToolRow,
        TranscriptItem,
        UserMessage;
import 'package:flutter/widgets.dart';

import '../context/compaction_marker.dart';
import 'activity_group.dart';
import 'child_question_row.dart';
import 'file_edit_row.dart';
import 'markdown.dart';
import 'messages.dart';
import 'return_line.dart';

/// What the host does when the user acts on a transcript item. Every
/// callback is optional; a control whose callback is missing is not drawn.
@immutable
class TranscriptActions {
  const TranscriptActions({
    this.markdown = const LeanMarkdownRenderer(),
    this.onReviewDiff,
    this.onUndo,
    this.onOpenFile,
    this.onOpenOutput,
    this.onOpenChild,
    this.onLinkTap,
    this.onRefTap,
    this.onViewContext,
    this.onAnswerChildQuestion,
    this.onResume,
    this.summaryOf,
    this.now,
  });

  /// Renders assistant prose.
  final MarkdownRenderer markdown;

  /// "Review diff" on an edit row.
  final ValueChanged<FileEdit>? onReviewDiff;

  /// "Undo" on an edit row. The row shows "Undoing…" until the returned future
  /// completes and "Undo failed" if it throws.
  final FutureOr<void> Function(FileEdit)? onUndo;

  /// "Open" on a created file's row.
  final ValueChanged<FileEdit>? onOpenFile;

  /// "Open full output" on an exec row.
  final ValueChanged<ToolRow>? onOpenOutput;

  /// A spawn row or a return line was opened; gets the child's id.
  final ValueChanged<String>? onOpenChild;

  /// A markdown link was tapped.
  final ValueChanged<String>? onLinkTap;

  /// A context chip of a user message was tapped.
  final ValueChanged<KitRef>? onRefTap;

  /// "View" on a compaction marker: open the Context pane on Now.
  final VoidCallback? onViewContext;

  /// "Send answer" of a pending child question: `(childId, questionId,
  /// text)`. Null leaves "Answer yourself" out.
  final void Function(String childId, String questionId, String text)?
  onAnswerChildQuestion;

  /// "Resume" on an interrupted notice.
  final VoidCallback? onResume;

  /// Replaces the summary line of activity groups (default: verb counts).
  final ActivitySummaryBuilder? summaryOf;

  /// Replaces the wall clock for waiting times (tests, the gallery).
  final DateTime? now;
}

/// The widget for [item].
class TranscriptItemView extends StatelessWidget {
  const TranscriptItemView(
    this.item, {
    super.key,
    this.actions = const TranscriptActions(),
  });

  final TranscriptItem item;
  final TranscriptActions actions;

  @override
  Widget build(BuildContext context) => switch (item) {
    final UserMessage m => UserBubble(m, onRefTap: actions.onRefTap),
    final AssistantMessage m => AssistantProse(
      m,
      renderer: actions.markdown,
      onLinkTap: actions.onLinkTap,
    ),
    final SystemLine l => SystemLineView(l),
    final NoticeLine l => NoticeLineView(l),
    final ActivityGroup g => ActivityGroupView(
      g,
      onOpenOutput: actions.onOpenOutput,
      onOpenChild: actions.onOpenChild,
      summaryOf: actions.summaryOf,
    ),
    final FileEdit e => FileEditRow(
      e,
      onReviewDiff: actions.onReviewDiff == null
          ? null
          : () => actions.onReviewDiff!(e),
      onUndo: actions.onUndo == null ? null : () => actions.onUndo!(e),
      onOpen: actions.onOpenFile == null ? null : () => actions.onOpenFile!(e),
    ),
    final ChildResult r => ReturnLine(r, onOpen: actions.onOpenChild),
    final CompactionItem c => CompactionMarker(
      c,
      onView: actions.onViewContext,
    ),
    final ChildQuestionItem q => ChildQuestionRow(
      q,
      now: actions.now,
      onOpenChild: actions.onOpenChild,
      onAnswer: actions.onAnswerChildQuestion,
    ),
    final InterruptedItem i => InterruptedNotice(
      text: i.reason ?? 'Interrupted by a restart',
      onResume: actions.onResume,
    ),
  };
}

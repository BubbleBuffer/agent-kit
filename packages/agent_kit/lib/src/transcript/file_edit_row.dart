// The files/edit row (Scratch's AgentEditRow, `.edit-row` in the mockup):
// "Edited usage/mod.rs +8 −3" with Review diff and Undo, opening into the
// diff.

import 'dart:async' show FutureOr;

import 'package:agent_kit_core/agent_kit_core.dart' show FileChange, FileEdit;
import 'package:bb_ui/bb_ui.dart';
import 'package:flutter/widgets.dart';

import '../theme/theme.dart';
import 'diff_view.dart';
import 'transcript_support.dart';

class FileEditRow extends StatefulWidget {
  const FileEditRow(
    this.edit, {
    super.key,
    this.initiallyOpen = false,
    this.onReviewDiff,
    this.onUndo,
    this.onOpen,
    this.openEveryEdit = false,
  });

  final FileEdit edit;

  /// Whether the diff starts open.
  final bool initiallyOpen;

  /// "Review diff" (a modified or deleted file).
  final VoidCallback? onReviewDiff;

  /// "Undo"; shown while the edit is undoable and not yet undone. The row
  /// reads "Undoing…" until the returned future completes (a second press does
  /// nothing meanwhile) and "Undo failed" next to Undo if it throws.
  final FutureOr<void> Function()? onUndo;

  /// "Open" (a created file; every edit with [openEveryEdit]).
  final VoidCallback? onOpen;

  /// Show "Open" on modified and deleted files too, beside Review diff.
  final bool openEveryEdit;

  @override
  State<FileEditRow> createState() => _FileEditRowState();
}

class _FileEditRowState extends State<FileEditRow> {
  late bool _open = widget.initiallyOpen;
  bool _undoing = false, _undoFailed = false;
  String? _refusal;

  Future<void> _undo() async {
    final undo = widget.onUndo;
    if (undo == null || _undoing) return;
    setState(() {
      _undoing = true;
      _undoFailed = false;
      _refusal = null;
    });
    var failed = false;
    String? refusal;
    try {
      await undo();
    } on UndoRefused catch (e) {
      refusal = e.message;
    } on Object {
      failed = true;
    }
    if (mounted) {
      setState(() {
        _undoing = false;
        _undoFailed = failed;
        _refusal = refusal;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.bb;
    final edit = widget.edit;
    final diff = edit.diff;
    final compact = sizeClassOf(context).isCompact;
    final hasBody = diff.hunks.isNotEmpty;
    final open = _open && hasBody;
    final created = diff.change == FileChange.created;
    final verb = switch (diff.change) {
      FileChange.modified => 'Edited',
      FileChange.created => 'Created',
      FileChange.deleted => 'Deleted',
    };
    final path = tailPath(diff.path);
    final name = edit.label ?? (compact ? path : '$verb $path');
    final nameStyle =
        ts(const TypeSpec(13, 16, 600), edit.undone ? t.faint : t.ink).copyWith(
          decoration: edit.undone ? TextDecoration.lineThrough : null,
          decorationColor: t.faint,
        );
    final openButton = widget.onOpen == null
        ? null
        : KitTextButton('Open', color: t.ink, onTap: widget.onOpen);
    final reviewButton = widget.onReviewDiff == null
        ? null
        : KitTextButton(
            'Review diff',
            color: t.ink,
            onTap: widget.onReviewDiff,
          );
    final primary = created
        ? [?openButton]
        : [?reviewButton, if (widget.openEveryEdit) ?openButton];
    final countStyle = ts(const TypeSpec(12, 16, 600), t.ink);
    final added = diff.added;
    final removed = diff.removed;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: t.radii.field,
        border: Border.all(color: t.colors.borderSubtle),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 34),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 2, 4, 2),
              child: Row(
                children: [
                  Expanded(
                    child: Semantics(
                      button: hasBody,
                      expanded: hasBody ? open : null,
                      label: '$verb ${diff.path}, +$added −$removed',
                      excludeSemantics: true,
                      child: Hover(
                        onTap: hasBody
                            ? () => setState(() => _open = !_open)
                            : null,
                        lift: 0,
                        radius: t.radii.sm,
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minHeight: isTouch(context) ? 36 : 30,
                          ),
                          child: Row(
                            children: [
                              if (hasBody)
                                DisclosureChevron(open: open, size: 12)
                              else
                                const SizedBox(width: 12),
                              const SizedBox(width: 6),
                              glyphIcon(
                                created ? glyphFilePlus : glyphFilePen,
                                size: 14,
                                color: t.colors.iconSecondary,
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  name,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: nameStyle,
                                ),
                              ),
                              if (added > 0) ...[
                                const SizedBox(width: 6),
                                Text(
                                  '+$added',
                                  style: countStyle.copyWith(
                                    color: t.constructiveInk,
                                  ),
                                ),
                              ],
                              if (removed > 0) ...[
                                const SizedBox(width: 6),
                                Text(
                                  '−$removed',
                                  style: countStyle.copyWith(
                                    color: t.dangerInk,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (edit.undone)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text(
                        'Undone',
                        style: ts(t.typeScale.uiSmall, t.faint),
                      ),
                    )
                  else ...[
                    ...primary,
                    if (edit.undoable && widget.onUndo != null) ...[
                      if (_undoFailed)
                        Text(
                          'Undo failed',
                          style: ts(t.typeScale.uiSmall, t.dangerInk),
                        ),
                      KitTextButton(
                        _undoing ? 'Undoing…' : 'Undo',
                        color: t.ink,
                        onTap: _undoing ? null : _undo,
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ),
          if (_refusal != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
              child: Text(_refusal!, style: ts(t.typeScale.uiSmall, t.faint)),
            ),
          if (open)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
              child: DiffView(diff),
            ),
        ],
      ),
    );
  }
}

/// Thrown by an undo callback that the host refused on purpose (the page
/// changed since): the row shows [message] under it instead of "Undo failed".
class UndoRefused implements Exception {
  /// Creates the refusal.
  const UndoRefused(this.message);

  /// What to tell the user.
  final String message;

  @override
  String toString() => message;
}

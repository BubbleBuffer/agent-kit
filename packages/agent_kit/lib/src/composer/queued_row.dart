// QueuedRow: one message waiting in the queue, above the composer.
//
// A dashed outline around "↓ Queued <text>", then Send now (delivers it at
// once as a steer), Edit and ×. The text truncates first; the buttons never
// shrink. The "Queued" label hides below the medium size (600 px). Edit turns
// the row into an inline field: Enter saves, Esc cancels.

import 'package:agent_kit_core/agent_kit_core.dart' show QueuedInput;
import 'package:bb_ui/bb_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../theme/theme.dart';
import 'composer_parts.dart';

/// A queued message with its three actions.
class QueuedRow extends StatefulWidget {
  /// Creates the row for [input].
  const QueuedRow({
    super.key,
    required this.input,
    this.onSendNow,
    this.onEdit,
    this.onRemove,
    this.initiallyEditing = false,
    this.hideUnavailable = false,
  });

  /// The message (its `id` goes back through the callbacks).
  final QueuedInput input;

  /// Send now: `sendQueuedNow(chatId, input.id)`.
  final ValueChanged<QueuedInput>? onSendNow;

  /// A saved edit: `editQueued(chatId, input.id, text)`.
  final void Function(QueuedInput input, String text)? onEdit;

  /// ×: `removeQueued(chatId, input.id)`.
  final ValueChanged<QueuedInput>? onRemove;

  /// Starts as the inline field (the gallery's specimen of it).
  final bool initiallyEditing;

  /// Leaves out an action whose callback is null instead of drawing it
  /// disabled (a backend without that capability).
  final bool hideUnavailable;

  @override
  State<QueuedRow> createState() => _QueuedRowState();
}

class _QueuedRowState extends State<QueuedRow> {
  late bool _editing = widget.initiallyEditing;
  late final TextEditingController _text = TextEditingController(
    text: widget.input.text,
  );
  final FocusNode _focus = FocusNode(debugLabel: 'queued edit');

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  void _startEdit() {
    setState(() {
      _text.text = widget.input.text;
      _text.selection = TextSelection.collapsed(offset: _text.text.length);
      _editing = true;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _focus.requestFocus();
    });
  }

  void _save() {
    final text = _text.text.trim();
    setState(() => _editing = false);
    if (text.isNotEmpty && text != widget.input.text) {
      widget.onEdit?.call(widget.input, text);
    }
  }

  void _cancel() => setState(() => _editing = false);

  @override
  Widget build(BuildContext context) {
    final t = context.bb;
    return SizeClassBuilder(
      builder: (context, size) => DashedOutline(
        color: t.colors.borderStrong,
        radius: t.radii.field,
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: isTouch(t) ? 40 : 32),
          child: Padding(
            padding: const EdgeInsets.only(left: 10, right: 4),
            child: _editing ? _editRow(t) : _row(t, size),
          ),
        ),
      ),
    );
  }

  bool _show(Object? callback) => callback != null || !widget.hideUnavailable;

  Widget _row(BbTheme t, SizeClass size) {
    const buttonHeight = 24.0;
    final touch = isTouch(t);
    return Semantics(
      container: true,
      label: 'Queued message',
      child: Row(
        children: [
          const KitIcon(ComposerGlyphs.arrowDown),
          const SizedBox(width: 8),
          if (!size.isCompact) ...[
            Text(
              'Queued',
              maxLines: 1,
              style: ts(
                t.typeScale.ui,
                t.faint,
                weight: 700,
              ).copyWith(fontSize: 13),
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Text(
              widget.input.text,
              maxLines: 1,
              softWrap: false,
              overflow: TextOverflow.ellipsis,
              style: ts(
                t.typeScale.ui,
                t.ink,
                weight: 500,
              ).copyWith(fontSize: 13),
            ),
          ),
          if (_show(widget.onSendNow)) ...[
            const SizedBox(width: 8),
            KitTip(
              message: 'Deliver now as a steer',
              child: KitButton(
                label: 'Send now',
                kind: KitButtonKind.quiet,
                icon: ComposerGlyphs.sendHorizontal,
                height: touch ? 40 : buttonHeight,
                fontSize: 13,
                hoverBackground: t.colors.bgSelectedBlock,
                onTap: widget.onSendNow == null
                    ? null
                    : () => widget.onSendNow!(widget.input),
              ),
            ),
          ],
          if (_show(widget.onEdit)) ...[
            const SizedBox(width: 8),
            KitButton(
              label: 'Edit',
              kind: KitButtonKind.quiet,
              height: touch ? 40 : buttonHeight,
              fontSize: 13,
              onTap: widget.onEdit == null ? null : _startEdit,
            ),
          ],
          if (_show(widget.onRemove)) ...[
            const SizedBox(width: 8),
            KitIconButton(
              ComposerGlyphs.x,
              label: 'Remove',
              size: touch ? 40 : buttonHeight,
              onTap: widget.onRemove == null
                  ? null
                  : () => widget.onRemove!(widget.input),
            ),
          ],
        ],
      ),
    );
  }

  Widget _editRow(BbTheme t) {
    final touch = isTouch(t);
    final style = ts(
      touch ? t.typeScale.body : t.typeScale.ui,
      t.ink,
      weight: 400,
    ).copyWith(fontSize: touch ? null : 13);
    return Row(
      children: [
        Expanded(
          child: Focus(
            canRequestFocus: false,
            skipTraversal: true,
            onKeyEvent: (node, event) {
              if (event is KeyDownEvent &&
                  event.logicalKey == LogicalKeyboardKey.escape) {
                _cancel();
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: Semantics(
              label: 'Edit queued message',
              textField: true,
              child: SizedBox(
                height: touch ? 40 : 32,
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: PlainField(
                    controller: _text,
                    focusNode: _focus,
                    style: style,
                    placeholder: 'Message',
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => _save(),
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 8),
        KitButton(
          label: 'Save',
          kind: KitButtonKind.quiet,
          height: touch ? 40 : 24,
          fontSize: 13,
          onTap: _save,
        ),
        const SizedBox(width: 8),
        KitIconButton(
          ComposerGlyphs.x,
          label: 'Cancel edit',
          size: touch ? 40 : 24,
          onTap: _cancel,
        ),
      ],
    );
  }
}

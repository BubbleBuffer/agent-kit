// AgentComposer: the message box at the bottom of a chat. A multiline field,
// reference chips above it, the model and workspace picks, the Steer/Queue
// switch, Stop (while running) and Send. It takes plain values and reports
// intent through callbacks; it never talks to the backend.
//
// Keys (SPEC.md, section 10): Enter sends (while running: steers, or queues in
// Queue mode); Ctrl/Cmd+Enter while running does the other one for this
// message; Shift+Enter adds a newline. With mention suggestions open, the up
// and down arrows move, Enter or Tab picks, Esc closes them.
//
// Look: Scratch's. The box is bb_ui's FieldFrame; Send, Stop, the picks and
// the mention menu are bb_ui's buttons, SelectButton and menu parts. In a bar
// narrower than the compact size class the picks take their own line above the
// buttons, at normal size; wider, they scale down if the bar runs out of room
// so the buttons keep theirs.

import 'dart:async' show FutureOr;
import 'dart:math' as math;

import 'package:agent_kit_core/agent_kit_core.dart' show KitChoice, KitRef;
import 'package:bb_ui/bb_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../theme/theme.dart';
import 'composer_pick.dart';
import 'mention_source.dart';

/// What a message does while the agent is running.
enum ComposerMode {
  /// Delivered into the running turn (the backend's `steer`).
  steer,

  /// Delivered after the run ends (the backend's `followup`).
  queue,
}

/// How a submitted message should reach the backend.
enum ComposerDelivery {
  /// The agent is idle: `send`.
  send,

  /// Into the running turn: `steer`.
  steer,

  /// After the run: `followup`.
  followup,
}

/// A message the user submitted.
class ComposerSubmission {
  /// Creates a submission.
  const ComposerSubmission({
    required this.text,
    required this.delivery,
    this.refs = const [],
  });

  /// The trimmed text.
  final String text;

  /// Which backend command it maps to.
  final ComposerDelivery delivery;

  /// The attached chips first, then the mentions left in [text], each with
  /// its `start` and `end`.
  final List<KitRef> refs;
}

/// The composer. See the library comment for the keys and the fit rule.
class AgentComposer extends StatefulWidget {
  /// Creates a composer.
  const AgentComposer({
    super.key,
    required this.onSubmit,
    this.running = false,
    this.onStop,
    this.models = const [],
    this.modelId,
    this.onModelChanged,
    this.workspaces = const [],
    this.workspaceId,
    this.onWorkspaceChanged,
    this.refs = const [],
    this.onRemoveRef,
    this.mentions,
    this.mode = ComposerMode.steer,
    this.onModeChanged,
    this.showModelPick = true,
    this.showModeToggle = true,
    this.controller,
    this.focusNode,
    this.autofocus = false,
    this.canSend = true,
    this.placeholder = 'Steer the agent…',
    this.maxLines = 8,
    this.maxMentions = 8,
    this.chipMaxWidth = 280,
    this.chipKeyOf,
    this.onMentionPicked,
    this.mentionLook,
    this.mentionSectionOf,
    this.runningSendLabel = 'Send',
    this.workspaceTitle = 'Workspace',
    this.workspaceLocked = false,
    this.keys = const ComposerKeys(),
  });

  /// Called with each submitted message. The composer clears its text, its
  /// picked mentions and nothing else once the host has taken the message:
  /// when [onSubmit] returns (or its future completes with) `true`.
  /// Return `false`, or throw, when the message was not sent: the
  /// text, the mentions and [refs] stay as they were. While a returned future
  /// is pending Send does nothing, and text typed meanwhile is kept.
  final FutureOr<bool> Function(ComposerSubmission) onSubmit;

  /// Whether sending is available. Off, Send is drawn disabled, Enter does
  /// not submit and the field is read-only ([onSubmit] is never called). Stop
  /// follows [onStop] alone: pass null to disable it.
  final bool canSend;

  /// Whether the agent is running: shows Stop and the Steer/Queue switch.
  final bool running;

  /// Stop was pressed (the backend's `cancel`).
  final VoidCallback? onStop;

  /// The models the model pick lists.
  final List<KitChoice> models;
  final String? modelId;
  final ValueChanged<KitChoice>? onModelChanged;

  /// The workspaces the workspace pick lists; hidden when empty.
  final List<KitChoice> workspaces;
  final String? workspaceId;
  final ValueChanged<KitChoice>? onWorkspaceChanged;

  /// Context attached to the next message, shown as chips above the field.
  final List<KitRef> refs;

  /// Called when a chip's × is pressed; the host removes it from [refs].
  final ValueChanged<KitRef>? onRemoveRef;

  /// Where `@` mentions come from; none turns them off.
  final MentionSource? mentions;

  /// The Steer/Queue switch's value.
  final ComposerMode mode;
  final ValueChanged<ComposerMode>? onModeChanged;

  /// Whether the model pick is drawn (off for a backend that cannot switch
  /// models).
  final bool showModelPick;

  /// Whether the Steer/Queue switch is drawn while running (off for a backend
  /// that cannot steer: a message then always queues). [mode] should be
  /// [ComposerMode.queue] with it off.
  final bool showModeToggle;

  /// The text, if the host wants to hold a draft. Created when null.
  final TextEditingController? controller;
  final FocusNode? focusNode;
  final bool autofocus;
  final String placeholder;

  /// The most lines the field grows to before it scrolls.
  final int maxLines;

  /// How many mention suggestions are listed.
  final int maxMentions;

  /// The widest a chip grows (its label truncates).
  final double chipMaxWidth;

  /// The key of a chip; its × gets that key plus `-remove`. The default is
  /// `chip-<kind>-<id>`.
  final Key Function(KitRef)? chipKeyOf;

  /// A suggestion was picked (its `@label` is already in the text). A host
  /// that keeps mentions as chips adds one to [refs] here.
  final ValueChanged<KitRef>? onMentionPicked;

  /// How a suggestion row looks beyond its label; null draws the kind's icon.
  final MentionRowLook Function(BuildContext, KitRef)? mentionLook;

  /// The heading a suggestion is listed under; the default names the kinds
  /// `page`, `chat` and `date` and lists others without one.
  final String? Function(KitRef)? mentionSectionOf;

  /// The send button's label while the agent runs and the Steer/Queue switch
  /// is hidden (a host that always steers says "Steer"). With the switch
  /// shown it reads Send.
  final String runningSendLabel;

  /// What the workspace pick chooses (its menu header).
  final String workspaceTitle;

  /// The workspace is fixed (shown, not changeable), for example once the
  /// chat has messages.
  final bool workspaceLocked;

  /// Keys for the parts a host's tests look up.
  final ComposerKeys keys;

  @override
  State<AgentComposer> createState() => _AgentComposerState();
}

class _AgentComposerState extends State<AgentComposer> {
  TextEditingController? _ownController;
  FocusNode? _ownFocus;
  ComposerMode? _localMode;

  // Mentions.
  final List<KitRef> _picked = [];
  List<KitRef> _suggestions = const [];
  int _active = 0;
  int _tokenStart = 0, _tokenEnd = 0;
  int? _dismissedAt;
  bool _open = false;
  int _fetch = 0;

  TextEditingController get _controller =>
      widget.controller ?? (_ownController ??= TextEditingController());
  FocusNode get _focus =>
      widget.focusNode ?? (_ownFocus ??= FocusNode(debugLabel: 'composer'));
  ComposerMode get _mode => _localMode ?? widget.mode;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onText);
  }

  @override
  void didUpdateWidget(AgentComposer old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      (old.controller ?? _ownController)?.removeListener(_onText);
      _controller.addListener(_onText);
    }
    if (old.mode != widget.mode) _localMode = null;
    if (widget.mentions == null && _open) _clearSuggest();
  }

  @override
  void dispose() {
    _controller.removeListener(_onText);
    _ownController?.dispose();
    _ownFocus?.dispose();
    super.dispose();
  }

  void _onText() {
    _scanMention();
    if (mounted) setState(() {});
  }

  // ---- mentions ----------------------------------------------------------

  void _clearSuggest() {
    _fetch++;
    _suggestions = const [];
    _open = false;
    _active = 0;
  }

  void _scanMention() {
    final source = widget.mentions;
    final v = _controller.value;
    if (source == null || !v.selection.isValid || !v.selection.isCollapsed) {
      _clearSuggest();
      return;
    }
    final caret = math.min(math.max(v.selection.baseOffset, 0), v.text.length);
    final trigger = RegExp.escape(source.trigger);
    final match = RegExp('(^|\\s)$trigger([^\\s$trigger]*)\$')
        .firstMatch(v.text.substring(0, caret));
    if (match == null) {
      _dismissedAt = null;
      _clearSuggest();
      return;
    }
    final query = match.group(2)!;
    final start = caret - query.length - source.trigger.length;
    if (start == _dismissedAt) {
      _clearSuggest();
      return;
    }
    _tokenStart = start;
    _tokenEnd = caret;
    _loadSuggestions(source, query);
  }

  Future<void> _loadSuggestions(MentionSource source, String query) async {
    final id = ++_fetch;
    List<KitRef> found;
    try {
      found = await source.suggest(query);
    } on Object {
      found = const [];
    }
    if (!mounted || id != _fetch) return;
    setState(() {
      _suggestions = found.take(widget.maxMentions).toList();
      _open = true;
      _active = 0;
    });
  }

  void _pick(KitRef ref) {
    final trigger = widget.mentions?.trigger ?? '@';
    final text = _controller.text;
    final insert = '$trigger${ref.label} ';
    final end = math.min(math.max(_tokenEnd, _tokenStart), text.length);
    _picked.add(ref);
    _clearSuggest();
    _controller.value = TextEditingValue(
      text: text.replaceRange(_tokenStart, end, insert),
      selection: TextSelection.collapsed(offset: _tokenStart + insert.length),
    );
    widget.onMentionPicked?.call(ref);
    _focus.requestFocus();
  }

  /// The mentions still present in [text], each with its span.
  List<KitRef> _mentionSpans(String text) {
    final trigger = widget.mentions?.trigger ?? '@';
    final used = <(int, int)>[];
    final spans = <KitRef>[];
    for (final ref in _picked) {
      final token = '$trigger${ref.label}';
      var from = 0;
      while (true) {
        final i = text.indexOf(token, from);
        if (i < 0) break;
        final end = i + token.length;
        if (used.any((u) => i < u.$2 && end > u.$1)) {
          from = i + 1;
          continue;
        }
        used.add((i, end));
        spans.add(
          KitRef(
            kind: ref.kind,
            id: ref.id,
            label: ref.label,
            start: i,
            end: end,
          ),
        );
        break;
      }
    }
    spans.sort((a, b) => a.start!.compareTo(b.start!));
    return spans;
  }

  // ---- sending -----------------------------------------------------------

  bool _sending = false;

  Future<void> _submit({bool invert = false}) async {
    if (!widget.canSend || _sending) return;
    final raw = _controller.text;
    final text = raw.trim();
    if (text.isEmpty) return;
    final ComposerDelivery delivery;
    if (!widget.running) {
      delivery = ComposerDelivery.send;
    } else {
      final steer = (_mode == ComposerMode.steer) != invert;
      delivery = steer ? ComposerDelivery.steer : ComposerDelivery.followup;
    }
    final refs = [...widget.refs, ..._mentionSpans(text)];
    final result = widget.onSubmit(
      ComposerSubmission(text: text, delivery: delivery, refs: refs),
    );
    var taken = result == true;
    if (result is Future<bool>) {
      setState(() => _sending = true);
      try {
        taken = await result;
      } on Object {
        taken = false;
      }
      if (!mounted) return;
      setState(() => _sending = false);
    }
    // Text typed while the host was busy belongs to the next message.
    if (taken && _controller.text == raw) {
      _picked.clear();
      _controller.clear();
    }
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final keys = HardwareKeyboard.instance;
    final isEnter =
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter;
    if (_open && key == LogicalKeyboardKey.escape) {
      setState(() {
        _dismissedAt = _tokenStart;
        _clearSuggest();
      });
      return KeyEventResult.handled;
    }
    if (_suggestions.isNotEmpty) {
      if (key == LogicalKeyboardKey.arrowDown) {
        setState(() => _active = (_active + 1) % _suggestions.length);
        return KeyEventResult.handled;
      }
      if (key == LogicalKeyboardKey.arrowUp) {
        setState(
          () => _active =
              (_active - 1 + _suggestions.length) % _suggestions.length,
        );
        return KeyEventResult.handled;
      }
      if ((isEnter && !keys.isShiftPressed) || key == LogicalKeyboardKey.tab) {
        if (event is KeyDownEvent) _pick(_suggestions[_active]);
        return KeyEventResult.handled;
      }
    }
    if (isEnter) {
      if (keys.isShiftPressed) return KeyEventResult.ignored; // a newline
      final composing = _controller.value.composing;
      if (composing.isValid && !composing.isCollapsed) {
        return KeyEventResult.ignored; // the IME is confirming
      }
      if (event is KeyDownEvent) {
        _submit(invert: keys.isControlPressed || keys.isMetaPressed);
      }
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _setMode(ComposerMode mode) {
    setState(() => _localMode = mode);
    widget.onModeChanged?.call(mode);
  }

  // ---- build -------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_open)
          Padding(
            padding: const EdgeInsets.only(bottom: 5),
            child: _MentionMenu(
              key: widget.keys.mentions,
              refs: _suggestions,
              active: _active,
              look: widget.mentionLook,
              sectionOf: widget.mentionSectionOf ?? _defaultSection,
              onHover: (i) => setState(() => _active = i),
              onPick: _pick,
            ),
          ),
        GestureDetector(
          onTap: _focus.requestFocus,
          child: FieldFrame(
            padding: const EdgeInsets.fromLTRB(12, 10, 8, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.refs.isNotEmpty) ...[
                  Wrap(
                    spacing: 4,
                    runSpacing: 4,
                    children: [
                      for (final r in widget.refs)
                        ComposerRefChip(
                          key:
                              widget.chipKeyOf?.call(r) ??
                              ValueKey('chip-${r.kind}-${r.id}'),
                          ref: r,
                          maxWidth: widget.chipMaxWidth,
                          onRemove: widget.onRemoveRef == null
                              ? null
                              : () => widget.onRemoveRef!(r),
                        ),
                    ],
                  ),
                  const SizedBox(height: 7),
                ],
                _Field(
                  fieldKey: widget.keys.field,
                  controller: _controller,
                  focusNode: _focus,
                  placeholder: widget.placeholder,
                  autofocus: widget.autofocus,
                  readOnly: !widget.canSend,
                  maxLines: widget.maxLines,
                  color: c.textPrimary,
                  onKey: _onKey,
                ),
                const SizedBox(height: 8),
                _bar(context),
              ],
            ),
          ),
        ),
      ],
    );
  }

  KitChoice? _choice(List<KitChoice> choices, String? id) {
    for (final c in choices) {
      if (c.id == id) return c;
    }
    return null;
  }

  Widget _pickFor({
    required Key? key,
    required String title,
    required List<KitChoice> choices,
    required String? selectedId,
    required ValueChanged<KitChoice>? onSelected,
  }) {
    final current = _choice(choices, selectedId);
    if (current == null) {
      return ComposerPick(
        key: key,
        title: title,
        choices: choices,
        selectedId: selectedId,
        placeholder: title,
        onSelected: (c) => onSelected?.call(c),
      );
    }
    return SelectButton<KitChoice>(
      key: key,
      title: title,
      value: current,
      options: choices,
      labelOf: (c) => c.label,
      onChanged: onSelected,
    );
  }

  Widget _bar(BuildContext context) {
    final showWorkspace = widget.workspaces.isNotEmpty;
    final showModel = widget.showModelPick;
    final label = widget.running && !widget.showModeToggle
        ? widget.runningSendLabel
        : 'Send';
    Widget send = PrimaryButton(
      key: widget.keys.send,
      label: label,
      height: 32,
      icon: Ico.arrowUp,
      onTap: _submit,
    );
    send = Semantics(
      container: true,
      excludeSemantics: true,
      button: true,
      enabled: widget.canSend,
      label: label,
      onTap: widget.canSend ? _submit : null,
      child: widget.canSend
          ? send
          : IgnorePointer(child: Opacity(opacity: .5, child: send)),
    );
    final picks = <Widget>[
      if (showWorkspace)
        _pickFor(
          key: widget.keys.workspace,
          title: widget.workspaceTitle,
          choices: widget.workspaces,
          selectedId: widget.workspaceId,
          onSelected: widget.workspaceLocked ? null : widget.onWorkspaceChanged,
        ),
      if (showModel)
        _pickFor(
          key: widget.keys.model,
          title: 'Model',
          choices: widget.models,
          selectedId: widget.modelId,
          onSelected: widget.onModelChanged,
        ),
    ];
    Widget buttons(bool withPicks) => Row(
      children: [
        if (withPicks && picks.isNotEmpty)
          Expanded(
            child: Align(
              alignment: Alignment.centerLeft,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Row(mainAxisSize: MainAxisSize.min, children: picks),
              ),
            ),
          )
        else
          const Spacer(),
        if (widget.running) ...[
          if (widget.showModeToggle) ...[
            ComposerModeToggle(mode: _mode, onChanged: _setMode),
            const SizedBox(width: 8),
          ],
          Semantics(
            container: true,
            excludeSemantics: true,
            button: true,
            enabled: widget.onStop != null,
            label: 'Stop',
            onTap: widget.onStop,
            child: SecondaryButton(
              key: widget.keys.stop,
              label: 'Stop',
              height: 32,
              onTap: widget.onStop,
            ),
          ),
          const SizedBox(width: 8),
        ],
        send,
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact =
            constraints.hasBoundedWidth &&
            SizeClass.forWidth(constraints.maxWidth).isCompact;
        if (!compact || picks.isEmpty) return buttons(true);
        // Compact: the picks keep their size on a line of their own.
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              runSpacing: 4,
              children: picks,
            ),
            const SizedBox(height: 6),
            buttons(false),
          ],
        );
      },
    );
  }
}

String? _defaultSection(KitRef r) => switch (r.kind) {
  'page' => 'Link to page',
  'chat' => 'Link to chat',
  'date' => 'Date',
  _ => null,
};

/// Keys for the parts of the composer a host's tests look up. All optional.
class ComposerKeys {
  /// Creates the keys.
  const ComposerKeys({
    this.field,
    this.send,
    this.stop,
    this.mentions,
    this.model,
    this.workspace,
  });

  /// The text field.
  final Key? field;

  /// The Send (or Steer) button.
  final Key? send;

  /// The Stop button.
  final Key? stop;

  /// The mention list.
  final Key? mentions;

  /// The model pick.
  final Key? model;

  /// The workspace pick.
  final Key? workspace;
}

/// The multiline text field with its placeholder.
class _Field extends StatelessWidget {
  const _Field({
    required this.fieldKey,
    required this.controller,
    required this.focusNode,
    required this.placeholder,
    required this.autofocus,
    required this.maxLines,
    required this.color,
    required this.onKey,
    this.readOnly = false,
  });

  final Key? fieldKey;
  final TextEditingController controller;
  final FocusNode focusNode;
  final String placeholder;
  final bool autofocus;
  final bool readOnly;
  final int maxLines;
  final Color color;
  final FocusOnKeyEventCallback onKey;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    return Semantics(
      label: 'Message to the agent',
      textField: true,
      multiline: true,
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onKeyEvent: onKey,
        child: Stack(
          children: [
            if (controller.text.isEmpty)
              Positioned.fill(
                child: IgnorePointer(
                  child: Text(
                    placeholder,
                    style: ts(context.type.body, c.textTertiary),
                  ),
                ),
              ),
            EditableText(
              key: fieldKey,
              controller: controller,
              focusNode: focusNode,
              style: ts(context.type.body, color),
              cursorColor: color,
              backgroundCursorColor: c.textTertiary,
              selectionColor: c.textSelection,
              cursorWidth: 1.5,
              autofocus: autofocus,
              readOnly: readOnly,
              minLines: 1,
              maxLines: maxLines,
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.newline,
              selectionControls: noteSelectionControls,
            ),
          ],
        ),
      ),
    );
  }
}

/// The Steer/Queue switch (`.seg`).
class ComposerModeToggle extends StatelessWidget {
  /// Creates the switch.
  const ComposerModeToggle({
    super.key,
    required this.mode,
    required this.onChanged,
  });

  final ComposerMode mode;
  final ValueChanged<ComposerMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final t = context.bb;
    return Semantics(
      container: true,
      label: 'While running',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: t.pressed,
          borderRadius: BorderRadius.circular(t.radii.md),
        ),
        child: Padding(
          padding: const EdgeInsets.all(2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _segment(t, 'Steer', ComposerMode.steer),
              _segment(t, 'Queue', ComposerMode.queue),
            ],
          ),
        ),
      ),
    );
  }

  Widget _segment(BbTheme t, String label, ComposerMode value) {
    final on = mode == value;
    return Semantics(
      button: true,
      selected: on,
      label: label,
      excludeSemantics: true,
      onTap: () => onChanged(value),
      child: Hover(
        onTap: () => onChanged(value),
        borderRadius: BorderRadius.circular(5),
        lift: 0,
        background: on ? t.surface : null,
        shadow: on
            ? [
                BoxShadow(
                  color: t.colors.palette.lift,
                  offset: const Offset(0, 1),
                  blurRadius: 2,
                ),
              ]
            : null,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: SizedBox(
          height: 24,
          child: Center(
            widthFactor: 1,
            child: Text(
              label,
              maxLines: 1,
              style: ts(t.typeScale.uiSmall, on ? t.ink : t.muted, weight: 600),
            ),
          ),
        ),
      ),
    );
  }
}

/// A reference chip above the field: an icon for the kind (`selection` a
/// text mark, `chat` a bubble, anything else a page), the label and a ×
/// that removes it.
class ComposerRefChip extends StatelessWidget {
  /// Creates a chip for [ref].
  const ComposerRefChip({
    super.key,
    required this.ref,
    this.onRemove,
    this.maxWidth = 280,
  });

  final KitRef ref;
  final VoidCallback? onRemove;

  /// The widest the label grows.
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final k = key;
    return DecoratedBox(
      decoration: BoxDecoration(color: c.bgSecondary, borderRadius: Radii.pill),
      child: Padding(
        padding: EdgeInsets.only(left: 6, right: onRemove == null ? 8 : 0),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon20(
              switch (ref.kind) {
                'selection' => Ico.text,
                'chat' => Ico.comment,
                _ => Ico.page,
              },
              size: 12,
              color: c.iconTertiary,
            ),
            const SizedBox(width: 4),
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: Text(
                ref.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: ts(context.type.uiSmall, c.textSecondary),
              ),
            ),
            if (onRemove != null)
              IconBtn(
                Ico.close,
                key: k is ValueKey ? ValueKey('${k.value}-remove') : null,
                size: 24,
                glyph: 12,
                semanticLabel: 'Remove context',
                onTap: onRemove,
              ),
          ],
        ),
      ),
    );
  }
}

/// The mention suggestions, listed above the field under a heading per kind.
/// Focus stays in the field; the active row is driven by the composer's keys.
class _MentionMenu extends StatelessWidget {
  const _MentionMenu({
    super.key,
    required this.refs,
    required this.active,
    required this.look,
    required this.sectionOf,
    required this.onHover,
    required this.onPick,
  });

  final List<KitRef> refs;
  final int active;
  final MentionRowLook Function(BuildContext, KitRef)? look;
  final String? Function(KitRef) sectionOf;
  final ValueChanged<int> onHover;
  final ValueChanged<KitRef> onPick;

  @override
  Widget build(BuildContext context) {
    final c = context.colors;
    final m = context.mobile;
    final rows = <Widget>[];
    String? section;
    for (var i = 0; i < refs.length; i++) {
      final r = refs[i];
      final s = sectionOf(r);
      if (s != section) {
        if (section != null) rows.add(const MenuSeparator());
        if (s != null) rows.add(MenuHeader(s));
        section = s;
      }
      final custom = look?.call(context, r);
      rows.add(
        MenuItem(
          key: ValueKey('mention-${r.kind}-${r.id}'),
          label: custom?.label ?? r.label,
          firstLine: custom?.firstLine ?? false,
          leading:
              custom?.leading ??
              Icon20(
                switch (r.kind) {
                  'chat' => Ico.comment,
                  'date' => Ico.clock,
                  _ => Ico.page,
                },
                size: m ? 22 : 20,
                color: c.iconSecondary,
              ),
          selected: i == active,
          onTap: () => onPick(r),
          onHover: () => onHover(i),
        ),
      );
    }
    if (refs.isEmpty) rows.add(const MenuHeader('No results'));
    return Semantics(
      container: true,
      label: 'Mentions',
      child: MenuSurface(
        width: m ? null : 324,
        padding: const EdgeInsets.all(6),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 168),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: rows,
            ),
          ),
        ),
      ),
    );
  }
}

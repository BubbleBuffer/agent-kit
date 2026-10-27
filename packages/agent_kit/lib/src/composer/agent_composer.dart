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
// The composer fits its own width: below `KitLayout.fitComposer` Stop and
// Send drop their labels and the workspace pick hides; the model name then
// truncates first, so the buttons keep their size.

import 'dart:math' as math;

import 'package:agent_kit_core/agent_kit_core.dart' show KitChoice, KitRef;
import 'package:bb_ui/bb_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../theme/theme.dart';
import 'composer_parts.dart';
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
    this.placeholder = 'Steer the agent…',
  });

  /// Called with each submitted message. The composer clears its text.
  final ValueChanged<ComposerSubmission> onSubmit;

  /// Whether the agent is running: shows Stop and the Steer/Queue switch.
  final bool running;

  /// Stop was pressed (the backend's `cancel`).
  final VoidCallback? onStop;

  /// The models the model pick lists.
  final List<KitChoice> models;
  final String? modelId;
  final ValueChanged<KitChoice>? onModelChanged;

  /// The workspaces the workspace pick lists; hidden when empty or tight.
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

  @override
  State<AgentComposer> createState() => _AgentComposerState();
}

class _AgentComposerState extends State<AgentComposer> {
  TextEditingController? _ownController;
  FocusNode? _ownFocus;
  bool _focused = false;
  ComposerMode? _localMode;

  // Mentions.
  final List<KitRef> _picked = [];
  List<KitRef> _suggestions = const [];
  int _active = 0;
  int _tokenStart = 0, _tokenEnd = 0;
  int? _dismissedAt;
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
    if (widget.mentions == null && _suggestions.isNotEmpty) _clearSuggest();
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
      _suggestions = found.take(8).toList();
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

  bool get _canSend => _controller.text.trim().isNotEmpty;

  void _submit({bool invert = false}) {
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
    _picked.clear();
    _controller.clear();
    widget.onSubmit(
      ComposerSubmission(text: text, delivery: delivery, refs: refs),
    );
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    final keys = HardwareKeyboard.instance;
    final isEnter =
        key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter;
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
      if (key == LogicalKeyboardKey.escape) {
        setState(() {
          _dismissedAt = _tokenStart;
          _clearSuggest();
        });
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
    final t = context.bb;
    return LayoutBuilder(
      builder: (context, constraints) {
        final tight = constraints.maxWidth < t.layout.fitComposer;
        return Focus(
          canRequestFocus: false,
          skipTraversal: true,
          onFocusChange: (focused) => setState(() => _focused = focused),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: t.surface2,
              borderRadius: t.radii.panel,
              border: Border.all(
                color: _focused ? t.colors.borderStrong : t.seam,
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 10, 8, 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (widget.refs.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(left: 4, bottom: 6),
                      child: Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          for (final r in widget.refs)
                            ComposerRefChip(
                              key: ValueKey('chip-${r.kind}-${r.id}'),
                              ref: r,
                              onRemove: widget.onRemoveRef == null
                                  ? null
                                  : () => widget.onRemoveRef!(r),
                            ),
                        ],
                      ),
                    ),
                  if (_suggestions.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(left: 4, bottom: 6),
                      child: _MentionList(
                        refs: _suggestions,
                        active: _active,
                        onHover: (i) => setState(() => _active = i),
                        onPick: _pick,
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.only(left: 4, bottom: 10),
                    child: _Field(
                      controller: _controller,
                      focusNode: _focus,
                      placeholder: widget.placeholder,
                      autofocus: widget.autofocus,
                      onKey: _onKey,
                    ),
                  ),
                  _bar(context, t, tight),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _bar(BuildContext context, BbTheme t, bool tight) {
    final h = controlHeight(t);
    return Row(
      children: [
        Expanded(
          child: Row(
            children: [
              if (widget.showModelPick)
                Flexible(
                  child: ComposerPick(
                    title: 'Model',
                    choices: widget.models,
                    selectedId: widget.modelId,
                    placeholder: 'Model',
                    onSelected: (c) => widget.onModelChanged?.call(c),
                  ),
                ),
              if (!tight && widget.workspaces.isNotEmpty) ...[
                if (widget.showModelPick) const SizedBox(width: 6),
                ComposerPick(
                  title: 'Workspace',
                  choices: widget.workspaces,
                  selectedId: widget.workspaceId,
                  placeholder: 'Workspace',
                  onSelected: (c) => widget.onWorkspaceChanged?.call(c),
                ),
              ],
            ],
          ),
        ),
        if (widget.running) ...[
          if (widget.showModeToggle) ...[
            ComposerModeToggle(mode: _mode, onChanged: _setMode),
            const SizedBox(width: 6),
          ],
          KitButton(
            label: 'Stop',
            icon: ComposerGlyphs.square,
            iconOnly: tight,
            height: h,
            onTap: widget.onStop,
          ),
        ],
        const SizedBox(width: 6),
        KitButton(
          label: 'Send',
          kind: KitButtonKind.primary,
          icon: ComposerGlyphs.arrowUp,
          iconSize: 18,
          iconOnly: tight,
          height: h,
          onTap: _canSend ? _submit : null,
        ),
      ],
    );
  }
}

/// The multiline text field with its placeholder.
class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.focusNode,
    required this.placeholder,
    required this.autofocus,
    required this.onKey,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String placeholder;
  final bool autofocus;
  final FocusOnKeyEventCallback onKey;

  @override
  Widget build(BuildContext context) {
    final t = context.bb;
    final style = ts(t.typeScale.body, t.ink, weight: 400);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: focusNode.requestFocus,
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: t.typeScale.body.line),
        child: Stack(
          children: [
            SizedBox(
              width: double.infinity,
              child: Semantics(
                label: 'Message to the agent',
                textField: true,
                multiline: true,
                child: Focus(
                  canRequestFocus: false,
                  skipTraversal: true,
                  onKeyEvent: onKey,
                  child: EditableText(
                    controller: controller,
                    focusNode: focusNode,
                    style: style,
                    cursorColor: t.ink,
                    backgroundCursorColor: t.faint,
                    selectionColor: t.colors.textSelection,
                    selectionControls: noteSelectionControls,
                    cursorWidth: 1.5,
                    autofocus: autofocus,
                    minLines: 1,
                    maxLines: 8,
                    keyboardType: TextInputType.multiline,
                    textInputAction: TextInputAction.newline,
                  ),
                ),
              ),
            ),
            Positioned(
              left: 0,
              top: 0,
              right: 0,
              child: ListenableBuilder(
                listenable: controller,
                builder: (context, _) => controller.text.isEmpty
                    ? IgnorePointer(
                        child: Text(
                          placeholder,
                          maxLines: 1,
                          overflow: TextOverflow.clip,
                          style: style.copyWith(color: t.faint),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
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

/// A reference chip above the field (`.cmp-chip`): an icon, the label and a
/// × that removes it.
class ComposerRefChip extends StatelessWidget {
  /// Creates a chip for [ref].
  const ComposerRefChip({super.key, required this.ref, this.onRemove});

  final KitRef ref;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    final t = context.bb;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 190),
      child: DecoratedBox(
        decoration: BoxDecoration(color: t.surface, borderRadius: t.radii.pill),
        child: SizedBox(
          height: 24,
          child: Padding(
            padding: const EdgeInsets.only(left: 8, right: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                KitIcon(ComposerGlyphs.fileText, size: 12, color: t.ink),
                const SizedBox(width: 5),
                Flexible(
                  child: Text(
                    ref.label,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                    style: ts(t.typeScale.uiSmall, t.ink),
                  ),
                ),
                if (onRemove != null) ...[
                  const SizedBox(width: 2),
                  Semantics(
                    button: true,
                    label: 'Remove ${ref.label}',
                    excludeSemantics: true,
                    onTap: onRemove,
                    child: Hover(
                      onTap: onRemove,
                      borderRadius: t.radii.pill,
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: Center(
                          child: KitIcon(
                            ComposerGlyphs.x,
                            size: 12,
                            color: t.ink,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The mention suggestions, listed above the field. Focus stays in the
/// field; the active row is driven by the composer's keys.
class _MentionList extends StatelessWidget {
  const _MentionList({
    required this.refs,
    required this.active,
    required this.onHover,
    required this.onPick,
  });

  final List<KitRef> refs;
  final int active;
  final ValueChanged<int> onHover;
  final ValueChanged<KitRef> onPick;

  @override
  Widget build(BuildContext context) {
    final t = context.bb;
    final rowHeight = isTouch(t) ? 40.0 : 28.0;
    return Semantics(
      container: true,
      label: 'Mentions',
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: t.surface,
          borderRadius: t.radii.field,
          border: Border.all(color: t.seam),
        ),
        child: Padding(
          padding: const EdgeInsets.all(4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < refs.length; i++)
                MouseRegion(
                  onEnter: (_) => onHover(i),
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => onPick(refs[i]),
                    child: Semantics(
                      button: true,
                      selected: i == active,
                      label: refs[i].label,
                      excludeSemantics: true,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: i == active ? t.colors.bgSelectedBlock : null,
                          borderRadius: BorderRadius.circular(t.radii.md),
                        ),
                        child: SizedBox(
                          height: rowHeight,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            child: Row(
                              children: [
                                KitIcon(
                                  ComposerGlyphs.fileText,
                                  size: 14,
                                  color: t.muted,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    refs[i].label,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: ts(
                                      t.typeScale.ui,
                                      t.ink,
                                      weight: 400,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  refs[i].kind,
                                  maxLines: 1,
                                  style: ts(t.typeScale.uiSmall, t.faint),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

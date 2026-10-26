// QuestionPrompt: a request from the agent with 1 to 5 questions, one card
// (mockup scene E, NOTES.md "Questions").
//
// Each question is pick one (radio rows), pick any (checkbox rows) or text
// only. Option rows are vertical: radio or checkbox, label, an optional muted
// description and a number key. Pick-one and pick-any may end with an "Other"
// row whose text field selects the row once it has text. A request of several
// questions shows a row of tabs (each question's header, a check once it has
// an answer), "N of M", Back and Next; the last step's button is Answer and
// sends every answer at once. Skip declines the current question and is sent
// as `skipped`. Questions never expire: the head shows "waiting 12m".
//
// Keys: 1 to 9 select or toggle the current question's options (the Other
// number focuses its field); Enter sends, or moves to Next; Shift+Enter adds
// a newline in a text answer. Like the approval bar, the digits act while
// focus is inside the card (outside its text fields), while focus is not in a
// text field, or while the composer is empty ([QuestionPrompt.composerEmpty]).
// Tab order: the tabs, the options, Other, Skip, Back, Next/Answer.
//
// The widget keeps its draft answers per question; Next and Back lose
// nothing. It never calls the backend: [QuestionPrompt.onAnswer] gets the map
// for `answerQuestion`, with an entry for every item.

import 'package:agent_kit_core/agent_kit_core.dart'
    show
        ChatStatus,
        Question,
        QuestionAnswer,
        QuestionItem,
        QuestionKind,
        QuestionOption;
import 'package:bb_ui/bb_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../status/status.dart';
import '../theme/theme.dart';
import '../transcript/markdown.dart';
import 'composer_parts.dart';

/// A pending [question] request and its answers.
class QuestionPrompt extends StatefulWidget {
  /// Creates the prompt.
  const QuestionPrompt({
    super.key,
    required this.question,
    required this.onAnswer,
    this.now,
    this.composerEmpty,
    this.captureKeys = true,
    this.initialStep = 0,
    this.initialAnswers = const {},
  });

  /// The request: its questions, their kinds and options, and `requestedAt`.
  final Question question;

  /// The answers for `answerQuestion`, keyed by item id, with an entry for
  /// every item; skipped items have `skipped: true`.
  final ValueChanged<Map<String, QuestionAnswer>> onAnswer;

  /// Replaces the wall clock for "waiting 12m" (tests, the gallery).
  final DateTime? now;

  /// Whether the composer is empty. Pressing a number in a focused, empty
  /// composer acts on the question. Without it, only keys outside text fields
  /// and inside the card do.
  final bool Function()? composerEmpty;

  /// Whether the card listens for the number keys. Turn it off on all but one
  /// card when several are shown at once (the gallery).
  final bool captureKeys;

  /// The step to start on (the gallery's specimens).
  final int initialStep;

  /// Draft answers to start from, keyed by item id (the gallery's specimens).
  final Map<String, QuestionAnswer> initialAnswers;

  @override
  State<QuestionPrompt> createState() => _QuestionPromptState();
}

/// What the user has entered for one item.
class _Draft {
  _Draft(this.item);

  final QuestionItem item;
  final picked = <String>{};
  final entry = TextEditingController();
  final entryFocus = FocusNode(debugLabel: 'question entry');
  bool skipped = false;
  bool visited = false;

  bool get hasEntry => entry.text.trim().isNotEmpty;

  /// Whether the item holds an answer other than a skip.
  bool get hasContent => picked.isNotEmpty || hasEntry;

  /// Whether the item can be sent as it is.
  bool get valid => skipped || item.kind == QuestionKind.pickAny || hasContent;

  /// Whether the tab shows a check.
  bool get done =>
      !skipped &&
      (hasContent || (item.kind == QuestionKind.pickAny && visited));

  QuestionAnswer toAnswer() {
    if (skipped) return QuestionAnswer(skipped: true);
    final typed = entry.text.trim();
    return switch (item.kind) {
      QuestionKind.text => QuestionAnswer(text: typed),
      QuestionKind.pickOne =>
        typed.isNotEmpty
            ? QuestionAnswer(text: typed)
            : QuestionAnswer(choices: picked.toList()),
      QuestionKind.pickAny => QuestionAnswer(
        // Option order, not tick order.
        choices: [
          for (final o in item.options)
            if (picked.contains(o.label)) o.label,
        ],
        text: typed.isEmpty ? null : typed,
      ),
    };
  }

  void dispose() {
    entry.dispose();
    entryFocus.dispose();
  }
}

class _QuestionPromptState extends State<QuestionPrompt> {
  // Takes focus (outside the tab order) when a number key acts, so that Enter
  // right after it reaches the card instead of the composer.
  final _barFocus = FocusNode(debugLabel: 'question card', skipTraversal: true);
  late List<_Draft> _drafts;
  int _step = 0;

  @override
  void initState() {
    super.initState();
    _reset();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void didUpdateWidget(QuestionPrompt old) {
    super.didUpdateWidget(old);
    if (old.question.id != widget.question.id) {
      _disposeDrafts();
      _reset();
    }
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    _barFocus.dispose();
    _disposeDrafts();
    super.dispose();
  }

  void _reset() {
    final items = widget.question.items;
    _step = widget.initialStep.clamp(0, items.length - 1);
    _drafts = [
      for (final item in items) _seeded(item, widget.initialAnswers[item.id]),
    ];
    for (var i = 0; i < _drafts.length; i++) {
      final index = i;
      _drafts[i].entry.addListener(() => _entryChanged(index));
    }
  }

  _Draft _seeded(QuestionItem item, QuestionAnswer? a) {
    final d = _Draft(item);
    if (a == null) return d;
    if (a.skipped) {
      d.skipped = true;
    } else {
      d.picked.addAll(a.choices);
      d.entry.text = a.text ?? '';
    }
    d.visited = true;
    return d;
  }

  void _disposeDrafts() {
    for (final d in _drafts) {
      d.dispose();
    }
  }

  QuestionItem get _item => widget.question.items[_step];
  _Draft get _draft => _drafts[_step];
  bool get _last => _step == _drafts.length - 1;
  bool get _canPrimary => _draft.valid;

  void _entryChanged(int index) {
    final d = _drafts[index];
    if (d.hasEntry) {
      d.skipped = false;
      if (d.item.kind == QuestionKind.pickOne) d.picked.clear();
    }
    if (mounted) setState(() {});
  }

  // ------------------------------------------------------------ editing

  void _selectOne(String label) {
    final d = _draft;
    setState(() {
      d.skipped = false;
      d.picked
        ..clear()
        ..add(label);
    });
    d.entry.clear();
  }

  void _toggle(String label) {
    final d = _draft;
    setState(() {
      d.skipped = false;
      if (!d.picked.remove(label)) d.picked.add(label);
    });
  }

  void _choose(QuestionOption option) {
    if (_item.kind == QuestionKind.pickOne) {
      _selectOne(option.label);
    } else {
      _toggle(option.label);
    }
  }

  // --------------------------------------------------------- navigation

  void _go(int step) {
    if (step < 0 || step >= _drafts.length || step == _step) return;
    setState(() {
      _draft.visited = true;
      _step = step;
    });
    // The row that had focus is gone: keep focus in the card, so that Enter
    // and the number keys still reach it (a text answer takes the caret).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_item.kind == QuestionKind.text) {
        _draft.entryFocus.requestFocus();
      } else {
        _barFocus.requestFocus();
      }
    });
  }

  /// Moves on, or sends the whole request from the last step. A step left
  /// unanswered (reached by a tab) is shown first.
  void _advance() {
    if (!_last) {
      _go(_step + 1);
      return;
    }
    final open = _drafts.indexWhere((d) => !d.valid);
    if (open >= 0) {
      _go(open);
      return;
    }
    widget.onAnswer({for (final d in _drafts) d.item.id: d.toAnswer()});
  }

  void _primary() {
    if (!_canPrimary) return;
    _advance();
  }

  void _skip() {
    final d = _draft;
    setState(() {
      d.picked.clear();
      d.skipped = true;
    });
    d.entry.clear();
    _advance();
  }

  // --------------------------------------------------------------- keys

  bool _isEditing(FocusNode? node) {
    final context = node?.context;
    if (context == null) return false;
    return context.widget is EditableText ||
        context.findAncestorWidgetOfExactType<EditableText>() != null;
  }

  static const _digits = [
    LogicalKeyboardKey.digit1,
    LogicalKeyboardKey.digit2,
    LogicalKeyboardKey.digit3,
    LogicalKeyboardKey.digit4,
    LogicalKeyboardKey.digit5,
    LogicalKeyboardKey.digit6,
    LogicalKeyboardKey.digit7,
    LogicalKeyboardKey.digit8,
    LogicalKeyboardKey.digit9,
  ];
  static const _numpad = [
    LogicalKeyboardKey.numpad1,
    LogicalKeyboardKey.numpad2,
    LogicalKeyboardKey.numpad3,
    LogicalKeyboardKey.numpad4,
    LogicalKeyboardKey.numpad5,
    LogicalKeyboardKey.numpad6,
    LogicalKeyboardKey.numpad7,
    LogicalKeyboardKey.numpad8,
    LogicalKeyboardKey.numpad9,
  ];

  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent ||
        !widget.captureKeys ||
        !widget.question.isPending ||
        !mounted) {
      return false;
    }
    final keys = HardwareKeyboard.instance;
    if (keys.isControlPressed ||
        keys.isMetaPressed ||
        keys.isAltPressed ||
        keys.isShiftPressed) {
      return false;
    }
    var n = _digits.indexOf(event.logicalKey);
    if (n < 0) n = _numpad.indexOf(event.logicalKey);
    if (n < 0) return false;
    final item = _item;
    if (item.kind == QuestionKind.text) return false;
    final other = item.allowOther ? item.options.length : -1;
    if (n >= item.options.length && n != other) return false;
    final focus = FocusManager.instance.primaryFocus;
    if (_isEditing(focus)) {
      if (_barFocus.hasFocus) return false; // typing in the card
      if (widget.composerEmpty?.call() != true) return false;
    }
    if (n == other) {
      _draft.entryFocus.requestFocus();
    } else {
      _choose(item.options[n]);
      if (!_barFocus.hasFocus) _barFocus.requestFocus();
    }
    return true;
  }

  KeyEventResult _onBarKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent ||
        (event.logicalKey != LogicalKeyboardKey.enter &&
            event.logicalKey != LogicalKeyboardKey.numpadEnter)) {
      return KeyEventResult.ignored;
    }
    final keys = HardwareKeyboard.instance;
    if (keys.isShiftPressed ||
        keys.isControlPressed ||
        keys.isMetaPressed ||
        keys.isAltPressed) {
      return KeyEventResult.ignored;
    }
    _primary();
    return KeyEventResult.handled;
  }

  // -------------------------------------------------------------- build

  static const _inset = EdgeInsets.symmetric(horizontal: 4);

  @override
  Widget build(BuildContext context) {
    final t = context.bb;
    final q = widget.question;
    final many = q.items.length > 1;
    final touch = isTouch(t);
    return Focus(
      focusNode: _barFocus,
      onKeyEvent: _onBarKey,
      child: Semantics(
        container: true,
        label: many ? 'Questions from the agent' : 'Question from the agent',
        child: SizeClassBuilder(
          builder: (context, size) => BarSurface(
            // The option list reaches 4 px past the text on both sides, as in
            // the mockup (`.qo-list` has a -4 px margin); everything else
            // takes `_inset` back.
            padding: EdgeInsets.fromLTRB(touch ? 6 : 8, 10, touch ? 6 : 6, 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(padding: _inset, child: _head(t, many)),
                if (many) ...[
                  const SizedBox(height: 6),
                  Padding(padding: _inset, child: _tabs(t)),
                ],
                const SizedBox(height: 6),
                _body(context, t, size, touch),
                const SizedBox(height: 10),
                Padding(padding: _inset, child: _foot(t, many)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _head(BbTheme t, bool many) => Row(
    children: [
      const StatusMark.pill(ChatStatus.needsYou, label: 'Question'),
      const SizedBox(width: 8),
      WaitingLabel(requestedAt: widget.question.requestedAt, now: widget.now),
      if (many) ...[
        const Spacer(),
        Text(
          '${_step + 1} of ${_drafts.length}',
          maxLines: 1,
          style: ts(t.typeScale.uiSmall, t.faint),
        ),
      ],
    ],
  );

  Widget _tabs(BbTheme t) => Semantics(
    container: true,
    label: 'Questions',
    child: Wrap(
      spacing: 4,
      runSpacing: 4,
      children: [
        for (var i = 0; i < _drafts.length; i++)
          _QuestionTab(
            key: ValueKey('question-tab-$i'),
            header: _drafts[i].item.header,
            active: i == _step,
            done: _drafts[i].done,
            skipped: _drafts[i].skipped,
            onTap: () => _go(i),
          ),
      ],
    ),
  );

  Widget _body(BuildContext context, BbTheme t, SizeClass size, bool touch) {
    final item = _item;
    final d = _draft;
    final hideKeys = touch || size.isCompact;
    final textStyle = ts(t.typeScale.body, t.ink, weight: 600);
    final Widget text = item.text.contains('\n')
        ? const LeanMarkdownRenderer().build(context, item.text)
        : MarkdownText(item.text, style: textStyle);
    return Column(
      key: ValueKey('question-step-${item.id}'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(padding: _inset, child: text),
        if (item.kind == QuestionKind.text)
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
            child: _TextAnswer(controller: d.entry, focusNode: d.entryFocus),
          )
        else ...[
          const SizedBox(height: 2),
          Padding(
            padding: _inset,
            child: Text(
              item.kind == QuestionKind.pickOne ? 'Pick one' : 'Pick any',
              style: ts(t.typeScale.uiSmall, t.muted),
            ),
          ),
          const SizedBox(height: 2),
          _options(t, item, d, hideKeys),
        ],
      ],
    );
  }

  Widget _options(BbTheme t, QuestionItem item, _Draft d, bool hideKeys) {
    final one = item.kind == QuestionKind.pickOne;
    String? keyFor(int i) => hideKeys || i >= 9 ? null : '${i + 1}';
    final rows = <Widget>[
      for (var i = 0; i < item.options.length; i++)
        _OptionRow(
          key: ValueKey('question-option-$i'),
          single: one,
          option: item.options[i],
          on: d.picked.contains(item.options[i].label),
          keyHint: keyFor(i),
          onTap: () => _choose(item.options[i]),
        ),
      if (item.allowOther)
        _OtherRow(
          key: const ValueKey('question-other'),
          single: one,
          controller: d.entry,
          focusNode: d.entryFocus,
          keyHint: keyFor(item.options.length),
        ),
    ];
    return Semantics(
      container: true,
      label: one ? 'Pick one' : 'Pick any',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < rows.length; i++) ...[
            if (i > 0) const SizedBox(height: 2),
            rows[i],
          ],
        ],
      ),
    );
  }

  Widget _foot(BbTheme t, bool many) {
    final canPrimary = _canPrimary;
    return Row(
      children: [
        _SkipButton(onTap: _skip),
        const Spacer(),
        if (many && _step > 0) ...[
          KitButton(label: 'Back', onTap: () => _go(_step - 1)),
          const SizedBox(width: 8),
        ],
        KitButton(
          label: _last ? 'Answer' : 'Next',
          kind: KitButtonKind.primary,
          onTap: canPrimary ? _primary : null,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------- pieces

/// A tab of the row of questions: header, and a check once answered.
class _QuestionTab extends StatelessWidget {
  const _QuestionTab({
    super.key,
    required this.header,
    required this.active,
    required this.done,
    required this.skipped,
    required this.onTap,
  });

  final String header;
  final bool active;
  final bool done;
  final bool skipped;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.bb;
    final color = done ? t.constructiveInk : (active ? t.ink : t.muted);
    final style = ts(t.typeScale.uiSmall, color, weight: 600);
    final h = isTouch(t) ? 32.0 : 26.0;
    return Semantics(
      button: true,
      selected: active,
      label: done
          ? '$header, answered'
          : (skipped ? '$header, skipped' : header),
      excludeSemantics: true,
      onTap: onTap,
      child: Hover(
        onTap: onTap,
        borderRadius: t.radii.pill,
        background: active ? t.colors.bgSelectedBlock : null,
        hoverBackground: active ? t.colors.bgSelectedBlock : t.hover,
        lift: 0,
        border: Border.all(color: active ? t.seam : t.colors.borderSubtle),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: SizedBox(
          height: h - 2,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (done) ...[
                KitIcon(ComposerGlyphs.check, size: 12, color: color),
                const SizedBox(width: 4),
              ],
              Text(
                header,
                maxLines: 1,
                softWrap: false,
                style: skipped
                    ? style.copyWith(
                        fontStyle: FontStyle.italic,
                        fontWeight: FontWeight.w400,
                        color: t.faint,
                      )
                    : style,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The radio or checkbox box.
class _Box extends StatelessWidget {
  const _Box({required this.single, required this.on});

  final bool single;
  final bool on;

  @override
  Widget build(BuildContext context) {
    final t = context.bb;
    final BoxDecoration decoration;
    if (single) {
      decoration = BoxDecoration(
        shape: BoxShape.circle,
        color: t.surface,
        border: Border.all(
          color: on ? t.accent : t.colors.borderStrong,
          width: on ? 5 : 1.5,
        ),
      );
    } else {
      decoration = BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        color: on ? t.accent : t.surface,
        border: Border.all(
          color: on ? t.accent : t.colors.borderStrong,
          width: 1.5,
        ),
      );
    }
    return Container(
      width: 16,
      height: 16,
      alignment: Alignment.center,
      decoration: decoration,
      child: !single && on
          ? KitIcon(ComposerGlyphs.check, size: 12, color: t.onAccent)
          : null,
    );
  }
}

/// The look of an option row: selected fill and seam, hover tint.
BoxDecoration _rowDecoration(
  BbTheme t, {
  required bool on,
  required bool hover,
  required bool focus,
}) => BoxDecoration(
  color: on ? t.colors.bgSelectedBlock : (hover ? t.hover : null),
  borderRadius: BorderRadius.circular(t.radii.md),
  border: Border.all(
    color: focus ? t.focus : (on ? t.seam : t.seam.withValues(alpha: 0)),
    width: focus ? 2 : 1,
  ),
);

/// One option: box, label, description and number key. A click selects (or
/// toggles); Space does too; Enter is left to the card, which sends. Up and
/// Down move between rows.
class _OptionRow extends StatefulWidget {
  const _OptionRow({
    super.key,
    required this.single,
    required this.option,
    required this.on,
    required this.keyHint,
    required this.onTap,
  });

  final bool single;
  final QuestionOption option;
  final bool on;
  final String? keyHint;
  final VoidCallback onTap;

  @override
  State<_OptionRow> createState() => _OptionRowState();
}

class _OptionRowState extends State<_OptionRow> {
  late final _focus = FocusNode(
    debugLabel: 'question option',
    onKeyEvent: _onKey,
  );
  bool _hover = false;
  bool _ring = false;

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      node.nextFocus();
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      node.previousFocus();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final t = context.bb;
    final o = widget.option;
    final touch = isTouch(t);
    final label = o.description == null
        ? o.label
        : '${o.label}. ${o.description}';
    return Semantics(
      container: true,
      checked: widget.on,
      inMutuallyExclusiveGroup: widget.single,
      label: label,
      excludeSemantics: true,
      onTap: widget.onTap,
      child: FocusableActionDetector(
        focusNode: _focus,
        onShowFocusHighlight: (v) => setState(() => _ring = v),
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        },
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onTap();
              return null;
            },
          ),
        },
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              _focus.requestFocus();
              widget.onTap();
            },
            child: DecoratedBox(
              decoration: _rowDecoration(
                t,
                on: widget.on,
                hover: _hover,
                focus: _ring,
              ),
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  8,
                  touch ? 10 : 7,
                  6,
                  touch ? 10 : 7,
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: _Box(single: widget.single, on: widget.on),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            o.label,
                            style: ts(t.typeScale.ui, t.ink, weight: 600),
                          ),
                          if (o.description != null) ...[
                            const SizedBox(height: 1),
                            Text(
                              o.description!,
                              style: ts(t.typeScale.uiSmall, t.muted),
                            ),
                          ],
                        ],
                      ),
                    ),
                    if (widget.keyHint != null) ...[
                      const SizedBox(width: 10),
                      Padding(
                        padding: EdgeInsets.only(
                          top: o.description == null ? 1 : 8,
                        ),
                        child: KeyCap(widget.keyHint!, color: t.ink),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The "Other" row: box, a text field and the number key. The row counts as
/// selected once the field has text.
class _OtherRow extends StatefulWidget {
  const _OtherRow({
    super.key,
    required this.single,
    required this.controller,
    required this.focusNode,
    required this.keyHint,
  });

  final bool single;
  final TextEditingController controller;
  final FocusNode focusNode;
  final String? keyHint;

  @override
  State<_OtherRow> createState() => _OtherRowState();
}

class _OtherRowState extends State<_OtherRow> {
  bool _hover = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
    widget.focusNode.addListener(_changed);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    widget.focusNode.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final t = context.bb;
    final touch = isTouch(t);
    final on = widget.controller.text.trim().isNotEmpty;
    final h = touch ? 40.0 : 28.0;
    return Semantics(
      container: true,
      checked: on,
      inMutuallyExclusiveGroup: widget.single,
      child: MouseRegion(
        cursor: SystemMouseCursors.text,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.focusNode.requestFocus,
          child: DecoratedBox(
            decoration: _rowDecoration(
              t,
              on: on,
              hover: _hover && !on,
              focus: false,
            ),
            child: Padding(
              padding: EdgeInsets.fromLTRB(8, touch ? 5 : 3, 6, touch ? 5 : 3),
              child: Row(
                children: [
                  _Box(single: widget.single, on: on),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FieldFrame(
                      height: h,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Semantics(
                        label: 'Other answer',
                        textField: true,
                        child: PlainField(
                          controller: widget.controller,
                          focusNode: widget.focusNode,
                          style: ts(
                            touch ? t.typeScale.body : t.typeScale.ui,
                            t.ink,
                            weight: 400,
                          ),
                          placeholder: 'Something else…',
                          textInputAction: TextInputAction.done,
                        ),
                      ),
                    ),
                  ),
                  if (widget.keyHint != null) ...[
                    const SizedBox(width: 10),
                    KeyCap(widget.keyHint!, color: t.ink),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The text-only answer: a field that grows from two lines.
class _TextAnswer extends StatefulWidget {
  const _TextAnswer({required this.controller, required this.focusNode});

  final TextEditingController controller;
  final FocusNode focusNode;

  @override
  State<_TextAnswer> createState() => _TextAnswerState();
}

class _TextAnswerState extends State<_TextAnswer> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final t = context.bb;
    final style = ts(t.typeScale.body, t.ink, weight: 400);
    return FieldFrame(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Semantics(
        label: 'Answer',
        textField: true,
        multiline: true,
        child: Stack(
          children: [
            if (widget.controller.text.isEmpty)
              Positioned(
                left: 0,
                top: 0,
                right: 0,
                child: IgnorePointer(
                  child: Text(
                    'Type an answer…',
                    maxLines: 1,
                    overflow: TextOverflow.clip,
                    style: style.copyWith(color: t.faint),
                  ),
                ),
              ),
            EditableText(
              controller: widget.controller,
              focusNode: widget.focusNode,
              style: style,
              cursorColor: t.ink,
              backgroundCursorColor: t.faint,
              selectionColor: t.colors.textSelection,
              selectionControls: noteSelectionControls,
              cursorWidth: 1.5,
              minLines: 2,
              maxLines: 8,
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.newline,
            ),
          ],
        ),
      ),
    );
  }
}

/// Skip: muted text on a hover surface (`.btn-text.ask-skip`).
class _SkipButton extends StatelessWidget {
  const _SkipButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = context.bb;
    return Semantics(
      button: true,
      label: 'Skip',
      excludeSemantics: true,
      onTap: onTap,
      child: Hover(
        onTap: onTap,
        borderRadius: BorderRadius.circular(t.radii.md),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: SizedBox(
          height: isTouch(t) ? 40 : 28,
          child: Center(
            widthFactor: 1,
            child: Text(
              'Skip',
              maxLines: 1,
              style: ts(t.typeScale.ui, t.muted, weight: 600),
            ),
          ),
        ),
      ),
    );
  }
}

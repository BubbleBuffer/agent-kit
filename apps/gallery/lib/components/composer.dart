// Gallery specimens of the composer group: the composer, the approval bar,
// the queued row and the question prompt, in every state, at the widths that
// matter (a wide column, a medium pane and a 390 px phone). The phone ones
// run in a nested theme scope with the phone form factor, as a phone window
// would give them (touch sizes, no key hints).

import 'package:agent_kit/agent_kit.dart';
import 'package:agent_kit_core/agent_kit_core.dart'
    show
        Approval,
        DiffHunk,
        DiffLine,
        DiffOp,
        FileDiff,
        KitChoice,
        KitRef,
        Question,
        QuestionAnswer,
        QuestionItem,
        QuestionKind,
        QuestionOption,
        QuestionState,
        QueuedInput,
        ToolKind;
import 'package:bb_ui/bb_ui.dart';
import 'package:flutter/widgets.dart';

/// The specimens, one section per widget.
class ComposerSpecimens extends StatefulWidget {
  const ComposerSpecimens({super.key});

  @override
  State<ComposerSpecimens> createState() => _ComposerSpecimensState();
}

final _now = DateTime.utc(2026, 10, 26, 12, 12);

final _approval = Approval(
  id: 'ap1',
  tool: 'edit',
  kind: ToolKind.edit,
  target: 'crates/bubblepaw-host/src/usage/mod.rs',
  requestedAt: _now.subtract(const Duration(minutes: 12)),
  diff: FileDiff(
    path: 'crates/bubblepaw-host/src/usage/mod.rs',
    hunks: [
      DiffHunk(
        oldStart: 40,
        newStart: 40,
        lines: [
          for (var i = 0; i < 3; i++) DiffLine(DiffOp.del, 'old line $i'),
          for (var i = 0; i < 8; i++) DiffLine(DiffOp.add, 'new line $i'),
        ],
      ),
    ],
  ),
);

final _queued = QueuedInput(
  id: 'q1',
  text: 'Dim the bar while stale, don’t hide it',
  queuedAt: _now.subtract(const Duration(minutes: 2)),
);

final _longQueued = QueuedInput(
  id: 'q2',
  text:
      'Also keep the last known figure through a reconnect, and show its '
      'age only on hover, not in the bar itself',
  queuedAt: _now.subtract(const Duration(minutes: 2)),
);

final _pickOne = QuestionItem(
  id: 'age',
  header: 'Stale figure',
  text: 'Should a stale quota figure show its age?',
  options: const [
    QuestionOption(
      label: 'Only on hover',
      description: 'The bar dims; hovering shows the last update.',
    ),
    QuestionOption(
      label: 'Always',
      description: 'A small age label sits next to the figure.',
    ),
    QuestionOption(
      label: 'Never',
      description: 'Dimming alone marks it stale.',
    ),
  ],
  allowOther: true,
);

final _pickAny = QuestionItem(
  id: 'views',
  header: 'Views',
  text: 'Which views should keep the last known figure?',
  kind: QuestionKind.pickAny,
  options: const [
    QuestionOption(label: 'Web quota bar'),
    QuestionOption(label: 'Desktop tray'),
    QuestionOption(label: 'CLI status line'),
  ],
  allowOther: true,
);

final _textOnly = QuestionItem(
  id: 'label',
  header: 'Label',
  text:
      'What should the stale label say? I’ll use it in the tooltip and the '
      'screen-reader text.',
  kind: QuestionKind.text,
);

Question _request(String id, List<QuestionItem> items, Duration waited) =>
    Question(id: id, requestedAt: _now.subtract(waited), items: items);

final _one = _request('qs1', [_pickOne], const Duration(minutes: 3));
final _any = _request('qs2', [_pickAny], const Duration(minutes: 1));
final _text = _request('qs3', [_textOnly], const Duration(seconds: 40));
final _mixed = _request('qs4', [
  _pickOne,
  _pickAny,
  _textOnly,
], const Duration(minutes: 6));

final _five = _request('qs5', [
  _pickOne,
  _pickAny,
  _textOnly,
  QuestionItem(
    id: 'wait',
    header: 'Reconnect',
    text: 'How long should the bar wait before marking the figure stale?',
    options: const [
      QuestionOption(label: 'Right away'),
      QuestionOption(
        label: 'After 5 seconds',
        description: 'Short blips stay invisible.',
      ),
      QuestionOption(label: 'After 30 seconds'),
    ],
  ),
  QuestionItem(
    id: 'tests',
    header: 'Tests to add',
    text: 'Which tests should I add?',
    kind: QuestionKind.pickAny,
    options: const [
      QuestionOption(label: 'Reconnect keeps the figure'),
      QuestionOption(label: 'Stale clears on update'),
    ],
  ),
], const Duration(minutes: 9));

final _answered = Question(
  id: 'qs6',
  requestedAt: _mixed.requestedAt,
  items: _mixed.items,
  state: QuestionState.answered,
  answers: {
    'age': QuestionAnswer(choices: const ['Only on hover']),
    'views': QuestionAnswer(
      choices: const ['Web quota bar', 'Desktop tray'],
      text: 'Hub dashboard',
    ),
    'label': QuestionAnswer(skipped: true),
  },
);

const _models = [
  KitChoice(id: 'flash', label: 'deepseek-v4.1-flash', detail: 'fast'),
  KitChoice(id: 'sol', label: 'gpt-6.1-sol', detail: 'thorough'),
];

const _workspaces = [
  KitChoice(id: 'base', label: 'BubblePaw-base'),
  KitChoice(id: 'kit', label: 'agent-kit'),
];

const _chip = KitRef(kind: 'page', id: 'p1', label: 'Approval expiry');

const _mentions = StaticMentionSource([
  KitRef(kind: 'file', id: 'f1', label: 'usage/mod.rs'),
  KitRef(kind: 'file', id: 'f2', label: 'usage/quota.rs'),
  KitRef(kind: 'page', id: 'p1', label: 'Approval expiry'),
]);

class _ComposerSpecimensState extends State<ComposerSpecimens> {
  String _last = 'none yet';
  final _filled = TextEditingController(text: 'Keep the last known figure');

  @override
  void dispose() {
    _filled.dispose();
    super.dispose();
  }

  void _log(String what) => setState(() => _last = what);

  Widget _composer({
    bool running = false,
    ComposerMode mode = ComposerMode.steer,
    List<KitRef> refs = const [],
    TextEditingController? controller,
    MentionSource? mentions,
  }) => AgentComposer(
    running: running,
    mode: mode,
    refs: refs,
    controller: controller,
    mentions: mentions,
    models: _models,
    modelId: 'flash',
    workspaces: _workspaces,
    workspaceId: 'base',
    onModelChanged: (c) => _log('model ${c.id}'),
    onWorkspaceChanged: (c) => _log('workspace ${c.id}'),
    onRemoveRef: (r) => _log('remove chip ${r.label}'),
    onStop: () => _log('stop'),
    onSubmit: (s) => _log('${s.delivery.name}: ${s.text}'),
  );

  Widget _approvalBar({bool denying = false, bool keys = false}) => ApprovalBar(
    approval: _approval,
    now: _now,
    initiallyDenying: denying,
    captureKeys: keys,
    onReview: () => _log('review diff'),
    onDecide: (d) => _log('decide ${d.choice.name} ${d.reason ?? ''}'.trim()),
  );

  Widget _queue({QueuedInput? input, bool editing = false}) => QueuedRow(
    input: input ?? _queued,
    initiallyEditing: editing,
    onSendNow: (q) => _log('send now ${q.id}'),
    onEdit: (q, text) => _log('edit ${q.id}: $text'),
    onRemove: (q) => _log('remove ${q.id}'),
  );

  Widget _answer(
    Question q, {
    int step = 0,
    Map<String, QuestionAnswer> answers = const {},
    bool keys = false,
  }) => QuestionPrompt(
    question: q,
    now: _now,
    captureKeys: keys,
    initialStep: step,
    initialAnswers: answers,
    onAnswer: (a) => _log('answer ${_summarize(a)}'),
  );

  static String _summarize(Map<String, QuestionAnswer> answers) => [
    for (final e in answers.entries)
      '${e.key}: ${e.value.skipped ? 'skipped' : [...e.value.choices, ?e.value.text].join('+')}',
  ].join(', ');

  @override
  Widget build(BuildContext context) {
    final t = context.bb;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _Heading('Composer, approval bar, queued row, question'),
        Padding(
          padding: EdgeInsets.only(bottom: t.spacing.md),
          child: Text(
            'Last callback: $_last',
            style: ts(const TypeSpec(12, 16, 400), t.faint, mono: true),
          ),
        ),
        const _Sub('AgentComposer'),
        _Frame('idle, empty, 640', 640, _composer()),
        _Frame(
          'running, steer, chip, text, 640',
          640,
          _composer(running: true, refs: const [_chip], controller: _filled),
        ),
        _Frame(
          'running, Queue mode, 640',
          640,
          _composer(running: true, mode: ComposerMode.queue),
        ),
        _Frame(
          'mentions: type @ (usage, approval), 640',
          640,
          _composer(mentions: _mentions),
        ),
        _Frame(
          'phone 390: labels drop, the workspace hides',
          390,
          _composer(running: true, refs: const [_chip]),
          phone: true,
        ),
        const _Sub('ApprovalBar'),
        _Frame(
          'expanded, 720: two lines, actions beside',
          720,
          _approvalBar(keys: true),
        ),
        _Frame('medium, 520: actions under the request', 520, _approvalBar()),
        _Frame(
          'phone 390: three buttons across, no key hints',
          390,
          _approvalBar(),
          phone: true,
        ),
        _Frame('deny, 520', 520, _approvalBar(denying: true)),
        _Frame(
          'deny, phone 390',
          390,
          _approvalBar(denying: true),
          phone: true,
        ),
        const _Sub('QueuedRow'),
        _Frame('wide, 640', 640, _queue()),
        _Frame(
          'long text truncates first, 640',
          640,
          _queue(input: _longQueued),
        ),
        _Frame('editing, 640', 640, _queue(editing: true)),
        _Frame('phone 390: "Queued" hidden', 390, _queue(), phone: true),
        const _Sub('QuestionPrompt'),
        _Frame(
          'pick one, descriptions and Other, 520',
          520,
          _answer(
            _one,
            answers: {
              'age': QuestionAnswer(choices: const ['Only on hover']),
            },
          ),
        ),
        _Frame(
          'pick any, 520',
          520,
          _answer(
            _any,
            answers: {
              'views': QuestionAnswer(
                choices: const ['Web quota bar', 'Desktop tray'],
                text: 'Hub dashboard',
              ),
            },
          ),
        ),
        _Frame('text only, Answer off while empty, 520', 520, _answer(_text)),
        _Frame(
          'three questions, at step 2, 520',
          520,
          _answer(
            _mixed,
            step: 1,
            answers: {
              'age': QuestionAnswer(choices: const ['Only on hover']),
              'views': QuestionAnswer(choices: const ['Web quota bar']),
            },
          ),
        ),
        _Frame(
          'five questions, at step 4, 520',
          520,
          _answer(
            _five,
            step: 3,
            answers: {
              'age': QuestionAnswer(choices: const ['Always']),
              'views': QuestionAnswer(choices: const ['Desktop tray']),
              'label': QuestionAnswer(skipped: true),
            },
          ),
        ),
        _Frame(
          'answered, in the transcript, 520',
          520,
          QuestionAnswerLines(question: _answered),
        ),
        _Frame(
          'phone 390: pick one, no number keys',
          390,
          _answer(_one),
          phone: true,
        ),
        _Frame(
          'phone 390: five questions, tabs wrap',
          390,
          _answer(_five, step: 3),
          phone: true,
        ),
        _Frame('phone 390: text only', 390, _answer(_text), phone: true),
      ],
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final t = context.bb;
    return Padding(
      padding: EdgeInsets.only(bottom: t.spacing.md),
      child: Text(text, style: ts(t.typeScale.h3, t.ink)),
    );
  }
}

class _Sub extends StatelessWidget {
  const _Sub(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final t = context.bb;
    return Padding(
      padding: EdgeInsets.only(top: t.spacing.md, bottom: t.spacing.sm),
      child: Text(text, style: ts(t.typeScale.ui, t.ink, weight: 700)),
    );
  }
}

/// A labelled specimen at [width] (or the space there is). [phone] gives it
/// the phone form factor.
class _Frame extends StatelessWidget {
  const _Frame(this.label, this.width, this.child, {this.phone = false});

  final String label;
  final double width;
  final Widget child;
  final bool phone;

  @override
  Widget build(BuildContext context) {
    final t = context.bb;
    Widget body = child;
    if (phone) {
      body = BbThemeScope(
        brightness: t.brightness,
        formFactor: FormFactor.mobile,
        child: child,
      );
    }
    return Padding(
      padding: EdgeInsets.only(bottom: t.spacing.lg),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final w = width < constraints.maxWidth ? width : constraints.maxWidth;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: EdgeInsets.only(bottom: t.spacing.xs),
                child: Text(
                  label,
                  style: ts(const TypeSpec(12, 16, 400), t.faint, mono: true),
                ),
              ),
              SizedBox(width: w, child: body),
            ],
          );
        },
      ),
    );
  }
}

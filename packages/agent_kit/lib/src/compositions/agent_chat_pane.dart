// AgentChatPane: one chat, fed by an AgentBackend.
//
// It owns a ChatFeed for [AgentChatPane.chatId] and closes it on dispose; when
// the id (or the backend) changes it closes that feed and opens the next. It
// draws the header, the transcript and the dock (pending approvals, the
// pending question, queued inputs, the composer), and sends every command
// through the backend. This is the only widget in the kit, with
// AgentWorkbench, that calls a backend.
//
// Optional controls the backend lacks (by its capabilities) are left out.
// Sending, stopping and approval decisions stay drawn but disabled when the
// backend lacks their capabilities, unless the host overrides paneActions.
// Controls a host turns off with [AgentPaneActions] (a read-only view) stay
// drawn but disabled, and nothing reaches the backend through them.
// A typed backend error shows as one dismissible line above the composer,
// never a modal.

import 'dart:async';
import 'dart:math' as math;

import 'package:agent_kit_core/agent_kit_core.dart';
import 'package:bb_ui/bb_ui.dart';
import 'package:flutter/widgets.dart';

import '../chrome/chrome.dart';
import '../composer/composer.dart';
import '../composer/composer_parts.dart'
    show ComposerGlyphs, KitButton, KitIconButton;
import '../theme/theme.dart';
import '../transcript/transcript.dart';

/// Overrides which of the pane's actions work. Without an override, the pane
/// derives these actions from the backend's [KitCapabilities]. A host that
/// can show a chat but not drive it passes [readOnly].
///
/// A turned-off action stays on screen, drawn disabled, and cannot be invoked
/// (not by tap, key or the semantics action). Messages, pending approvals and
/// the rest of the dock are still shown. An explicit override takes precedence
/// over the backend's send, cancel and approve capabilities.
///
/// Only the actions named here are covered: the other commands (answering a
/// question, the queue, undo, resume, fork, archive and the model and
/// workspace picks) still follow the capabilities alone, so a read-only host
/// also reports those as missing.
class AgentPaneActions {
  /// Creates the set; everything is on unless turned off.
  const AgentPaneActions({
    this.send = true,
    this.stop = true,
    this.decide = true,
  });

  /// Every action works, regardless of the backend's capabilities.
  static const all = AgentPaneActions();

  /// Messages and approvals are shown; sending, stopping and deciding are off.
  static const readOnly = AgentPaneActions(
    send: false,
    stop: false,
    decide: false,
  );

  /// Whether the composer can send (Send and Enter).
  final bool send;

  /// Whether Stop, shown while the agent runs, can cancel the run.
  final bool stop;

  /// Whether a pending approval can be approved, approved for the session or
  /// denied.
  final bool decide;
}

/// A chat: header, transcript and dock, driven by [backend].
class AgentChatPane extends StatefulWidget {
  /// Creates the pane for [chatId].
  const AgentChatPane({
    super.key,
    required this.backend,
    required this.chatId,
    this.now,
    this.showCrewStrip = true,
    this.sideBuilder,
    this.workspaceShown = false,
    this.onToggleWorkspace,
    this.onSnapshot,
    this.onOpenChat,
    this.onChatsChanged,
    this.statusDetail,
    this.transcriptActions = const TranscriptActions(),
    this.mentions,
    this.onReviewApproval,
    this.onOpenAgent,
    this.onOpenJob,
    this.onOpenContext,
    this.contentWidth = 720,
    this.turnLayout = TurnLayout.chronological,
    AgentPaneActions? paneActions,
  }) : _paneActionsOverride = paneActions;

  /// Where the chat lives.
  final AgentBackend backend;

  /// The chat to show. Changing it switches feeds.
  final String chatId;

  /// Replaces the wall clock for ages (tests, the gallery).
  final DateTime? now;

  /// Whether the crew strip shows under the header when the chat has child
  /// agents or jobs.
  final bool showCrewStrip;

  /// The column beside the transcript at the expanded size (the crew ledger).
  /// It gets the snapshot; null from the builder, or no builder, means no
  /// column. The pane sizes the grid as the mockup does: the content column
  /// and a 252 px side column, 40 px apart.
  final Widget? Function(BuildContext context, ChatSnapshot snapshot)?
  sideBuilder;

  /// The state of the header's workspace toggle.
  final bool workspaceShown;

  /// Called by the header's workspace button; null leaves the button out.
  final VoidCallback? onToggleWorkspace;

  /// Called with each new snapshot, for a host that mirrors the chat's state.
  final ValueChanged<ChatSnapshot>? onSnapshot;

  /// A fork was made: open this chat.
  final ValueChanged<String>? onOpenChat;

  /// The chat list may have changed (the chat was archived).
  final VoidCallback? onChatsChanged;

  /// The text after the status pill's label. By default, "edit approval" for
  /// a pending approval and "3 agents" for a run with child agents.
  final String? Function(ChatSnapshot snapshot)? statusDetail;

  /// What the transcript's rows open. The pane adds Undo itself, from the
  /// backend's `editUndo` capability.
  final TranscriptActions transcriptActions;

  /// Where `@` mentions in the composer come from.
  final MentionSource? mentions;

  /// "Review diff" on an approval.
  final ValueChanged<Approval>? onReviewApproval;

  /// A crew strip chip was opened.
  final ValueChanged<ChildAgent>? onOpenAgent;
  final ValueChanged<BackgroundJob>? onOpenJob;

  /// Opens the Context pane on Now: the header's context meter and the
  /// compaction marker's View call it. Null leaves both inert (the meter is
  /// then a plain readout).
  final VoidCallback? onOpenContext;

  /// The width of the content column.
  final double contentWidth;

  /// How a turn's items are ordered in the transcript.
  final TurnLayout turnLayout;

  /// Overrides which actions work. When omitted, send, stop and approval
  /// decisions follow the backend's send, cancel and approve capabilities.
  /// [AgentPaneActions.readOnly] disables all three; [AgentPaneActions.all]
  /// explicitly enables them even if the backend omits those capabilities.
  AgentPaneActions get paneActions =>
      _paneActionsOverride ??
      AgentPaneActions(
        send: backend.capabilities.has(KitCapability.send),
        stop: backend.capabilities.has(KitCapability.cancel),
        decide: backend.capabilities.has(KitCapability.approve),
      );

  final AgentPaneActions? _paneActionsOverride;

  @override
  State<AgentChatPane> createState() => _AgentChatPaneState();
}

class _AgentChatPaneState extends State<AgentChatPane> {
  static const _gap = 40.0;
  static const _sideWidth = 252.0;

  ChatFeed? _feed;
  StreamSubscription<ChatSnapshot>? _sub;
  ChatSnapshot? _snapshot;
  String? _loadError;
  String? _error;
  late ComposerMode _mode = _canSteer ? ComposerMode.steer : ComposerMode.queue;
  List<KitChoice> _models = const [];
  List<KitChoice> _profiles = const [];
  final TextEditingController _text = TextEditingController();
  final TranscriptController _transcript = TranscriptController();

  KitCapabilities get _caps => widget.backend.capabilities;
  bool get _canSteer => _caps.has(KitCapability.steer);
  AgentPaneActions get _paneActions => widget.paneActions;

  @override
  void initState() {
    super.initState();
    _open();
    _loadChoices();
  }

  @override
  void didUpdateWidget(AgentChatPane old) {
    super.didUpdateWidget(old);
    if (old.backend != widget.backend) {
      _close();
      _models = const [];
      _profiles = const [];
      _mode = _canSteer ? ComposerMode.steer : ComposerMode.queue;
      _open();
      _loadChoices();
    } else if (old.chatId != widget.chatId) {
      _close();
      _text.clear();
      _open();
    }
  }

  @override
  void dispose() {
    _close();
    _text.dispose();
    _transcript.dispose();
    super.dispose();
  }

  // ----------------------------------------------------------------- feed

  void _open() {
    final feed = ChatFeed(widget.backend, widget.chatId);
    _feed = feed;
    _snapshot = null;
    _loadError = null;
    _error = null;
    _sub = feed.snapshots.listen(
      (snap) {
        if (!mounted || _feed != feed) return;
        setState(() => _snapshot = snap);
        widget.onSnapshot?.call(snap);
      },
      onError: (Object error, StackTrace stack) {
        if (!mounted || _feed != feed) return;
        setState(() => _error = _describe(error));
      },
    );
    feed.start().then<void>(
      (snap) {
        if (!mounted || _feed != feed || _snapshot != null) return;
        setState(() => _snapshot = snap);
        widget.onSnapshot?.call(snap);
      },
      onError: (Object error) {
        if (!mounted || _feed != feed) return;
        setState(() => _loadError = _describe(error));
      },
    );
  }

  void _close() {
    final feed = _feed;
    _feed = null;
    _sub?.cancel();
    _sub = null;
    if (feed != null) unawaited(feed.close());
  }

  void _retry() {
    _close();
    setState(_open);
  }

  Future<void> _loadChoices() async {
    final backend = widget.backend;
    try {
      if (_caps.has(KitCapability.models)) {
        final models = await backend.listModels();
        if (mounted && widget.backend == backend) {
          setState(() => _models = models);
        }
      }
      if (_caps.has(KitCapability.profiles)) {
        final profiles = await backend.listProfiles();
        if (mounted && widget.backend == backend) {
          setState(() => _profiles = profiles);
        }
      }
    } catch (_) {
      // The picks stay empty; the chat itself works without them.
    }
  }

  static String _describe(Object error) =>
      error is KitError ? error.message : 'Something went wrong.';

  /// Runs a backend command. A failure becomes the dock's error line.
  /// Whether it worked.
  Future<bool> _run(
    Future<void> Function() command, {
    VoidCallback? onFail,
  }) async {
    try {
      await command();
      if (mounted && _error != null) setState(() => _error = null);
      return true;
    } catch (error) {
      onFail?.call();
      if (mounted) setState(() => _error = _describe(error));
      return false;
    }
  }

  // ------------------------------------------------------------- commands

  Future<bool> _submit(ComposerSubmission s) {
    if (!_paneActions.send) return Future.value(false);
    final backend = widget.backend;
    final id = widget.chatId;
    return _run(
      () async {
        switch (s.delivery) {
          case ComposerDelivery.send:
            await backend.send(id, s.text, refs: s.refs);
          case ComposerDelivery.steer:
            if (_canSteer) {
              await backend.steer(id, s.text, refs: s.refs);
            } else {
              await backend.followup(id, s.text, refs: s.refs);
            }
          case ComposerDelivery.followup:
            await backend.followup(id, s.text, refs: s.refs);
        }
      },
      onFail: () {
        // Give the text back instead of losing it.
        if (_text.text.isEmpty) _text.text = s.text;
      },
    );
  }

  TranscriptActions _actions() {
    final a = widget.transcriptActions;
    final backend = widget.backend;
    return TranscriptActions(
      markdown: a.markdown,
      onReviewDiff: a.onReviewDiff,
      onUndo: _caps.has(KitCapability.editUndo)
          ? (edit) async {
              final worked = await _run(
                () => backend.undoEdit(widget.chatId, edit.id),
              );
              if (!worked) throw StateError('Undo failed');
            }
          : null,
      onOpenFile: a.onOpenFile,
      onOpenOutput: a.onOpenOutput,
      onOpenChild: a.onOpenChild,
      onLinkTap: a.onLinkTap,
      onRefTap: a.onRefTap,
      onViewContext: widget.onOpenContext ?? a.onViewContext,
      onAnswerChildQuestion: _caps.has(KitCapability.answerChildQuestion)
          ? (childId, questionId, text) => _run(
              () => backend.answerChildQuestion(
                widget.chatId,
                childId,
                questionId,
                text,
              ),
            )
          : null,
      onResume: _caps.has(KitCapability.resume)
          ? () => _run(() => backend.resume(widget.chatId))
          : null,
      onRewind: _caps.has(KitCapability.rewind)
          ? (message) => _run(() => backend.rewind(widget.chatId, message.id))
          : null,
      now: widget.now ?? a.now,
    );
  }

  List<ChromeMenuItem> _menu() => [
    if (_caps.has(KitCapability.fork))
      ChromeMenuItem(
        'Fork chat',
        () => _run(() async {
          final chat = await widget.backend.fork(widget.chatId);
          widget.onOpenChat?.call(chat.id);
        }),
      ),
    if (_caps.has(KitCapability.archive))
      ChromeMenuItem(
        'Archive chat',
        () => _run(() async {
          await widget.backend.archive(widget.chatId);
          widget.onChatsChanged?.call();
        }),
        separatorBefore: true,
      ),
  ];

  // The header's pill says the status alone, as in the mockup; a host can add
  // a detail through [AgentChatPane.statusDetail].
  String? _detail(ChatSnapshot snap) => widget.statusDetail?.call(snap);

  // ---------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) =>
      ApprovalKeyPane(child: Builder(builder: _buildPane));

  Widget _buildPane(BuildContext context) {
    final snap = _snapshot;
    if (snap == null) return _placeholder(context);
    final running = snap.run?.isActive ?? false;
    final strip =
        widget.showCrewStrip &&
        (snap.children.isNotEmpty || snap.jobs.isNotEmpty);
    final side = widget.sideBuilder?.call(context, snap);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ChatHeader(
          chat: _summary(snap),
          branch: snap.workspace?.branch,
          worktree: snap.workspace?.worktree,
          usage: snap.usage,
          statusDetail: _detail(snap),
          workspaceShown: widget.workspaceShown,
          onToggleWorkspace: widget.onToggleWorkspace,
          menuItems: _menu(),
          hideEmptyMenu: true,
          onOpenContext: snap.context == null ? null : widget.onOpenContext,
        ),
        if (strip)
          CrewStrip(
            agents: snap.children,
            jobs: snap.jobs,
            now: widget.now,
            onOpenAgent: widget.onOpenAgent,
            onOpenJob: widget.onOpenJob,
          ),
        Expanded(
          child: side == null
              ? _main(context, snap, running, widget.contentWidth)
              : _grid(context, snap, running, side),
        ),
      ],
    );
  }

  ChatSummary _summary(ChatSnapshot snap) {
    final s = ChatSummary.of(snap);
    return snap.title.isEmpty
        ? ChatSummary(
            id: s.id,
            title: 'New chat',
            status: s.status,
            workspace: s.workspace,
            runningChildren: s.runningChildren,
          )
        : s;
  }

  Widget _placeholder(BuildContext context) {
    final t = context.bb;
    final failed = _loadError;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: failed == null
            ? Semantics(
                liveRegion: true,
                label: 'Loading the chat',
                child: Text('Loading…', style: ts(t.typeScale.ui, t.faint)),
              )
            : Semantics(
                liveRegion: true,
                container: true,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Couldn’t load this chat',
                      textAlign: TextAlign.center,
                      style: ts(t.typeScale.ui, t.ink, weight: 700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      failed,
                      textAlign: TextAlign.center,
                      style: ts(t.typeScale.uiSmall, t.muted),
                    ),
                    const SizedBox(height: 12),
                    KitButton(label: 'Retry', onTap: _retry),
                  ],
                ),
              ),
      ),
    );
  }

  /// The mockup's stage grid with a side column:
  /// `minmax(16, 1fr) minmax(0, 720) 252 .5fr`, 40 px apart.
  Widget _grid(
    BuildContext context,
    ChatSnapshot snap,
    bool running,
    Widget side,
  ) {
    return LayoutBuilder(
      builder: (context, box) {
        final w = box.maxWidth;
        final room = w - 3 * _gap - _sideWidth - 16;
        if (!box.hasBoundedWidth || room < 160) {
          return _main(context, snap, running, widget.contentWidth);
        }
        final content = math.min(widget.contentWidth, room);
        final free = w - 3 * _gap - _sideWidth - content;
        final left = math.max(16.0, free * 2 / 3);
        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // The main column carries 16 px of padding on both sides.
            SizedBox(width: left + _gap - 16),
            SizedBox(
              width: content + 32,
              child: _main(context, snap, running, content),
            ),
            const SizedBox(width: _gap - 16),
            SizedBox(
              width: _sideWidth,
              child: Padding(
                padding: const EdgeInsets.only(top: 28),
                child: SingleChildScrollView(child: side),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _main(
    BuildContext context,
    ChatSnapshot snap,
    bool running,
    double contentWidth,
  ) {
    final t = context.bb;
    // The run outcome is the fallback for snapshots without the item.
    final interrupted =
        !running &&
        snap.run?.outcome == RunOutcome.interrupted &&
        !snap.items.any((i) => i is InterruptedItem);
    final transcript = TranscriptList(
      key: ValueKey('transcript-${widget.chatId}'),
      items: snap.items,
      plan: snap.plan,
      inserts: _inserts(snap),
      actions: _actions(),
      controller: _transcript,
      layout: widget.turnLayout,
      contentWidth: contentWidth,
      trailing: interrupted
          ? InterruptedNotice(
              onResume: _caps.has(KitCapability.resume)
                  ? () => _run(() => widget.backend.resume(widget.chatId))
                  : null,
            )
          : null,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: snap.stale
              ? Opacity(opacity: .6, child: transcript)
              : transcript,
        ),
        Padding(
          padding: const EdgeInsets.only(top: 10, bottom: 14),
          child: Center(
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: contentWidth + 32),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _dock(context, t, snap, running),
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// Resolved questions, placed after the last item that was there when the
  /// request was made.
  List<TranscriptInsert> _inserts(ChatSnapshot snap) {
    final out = <TranscriptInsert>[];
    for (final q in snap.questions) {
      if (q.isPending) continue;
      String? after;
      for (final item in snap.items) {
        final at = item.at;
        if (at != null && !at.isAfter(q.requestedAt)) after = item.id;
      }
      out.add(
        TranscriptInsert(
          id: 'question-${q.id}',
          afterItemId: after,
          child: QuestionAnswerLines(question: q),
        ),
      );
    }
    return out;
  }

  Widget _dock(
    BuildContext context,
    BbTheme t,
    ChatSnapshot snap,
    bool running,
  ) {
    final backend = widget.backend;
    final id = widget.chatId;
    final approvals = snap.pendingApprovals.toList();
    final question = _caps.has(KitCapability.questions)
        ? snap.pendingQuestions.firstOrNull
        : null;
    bool composerEmpty() => _text.text.trim().isEmpty;
    final profiles = _caps.has(KitCapability.profiles)
        ? _withCurrent(_profiles, snap.profile)
        : const <KitChoice>[];
    final models = _caps.has(KitCapability.models)
        ? _withCurrent(_models, snap.model)
        : const <KitChoice>[];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < approvals.length; i++) ...[
          ApprovalBar(
            key: ValueKey('approval-${approvals[i].id}'),
            approval: approvals[i],
            now: widget.now,
            composerEmpty: composerEmpty,
            captureKeys: i == 0,
            onReview:
                widget.onReviewApproval == null || approvals[i].diff == null
                ? null
                : () => widget.onReviewApproval!(approvals[i]),
            enabled: _paneActions.decide,
            onDecide: (decision) {
              if (!_paneActions.decide) return;
              _run(() => backend.decideApproval(id, approvals[i].id, decision));
            },
          ),
          const SizedBox(height: 8),
        ],
        if (question != null) ...[
          QuestionPrompt(
            key: ValueKey('question-${question.id}'),
            question: question,
            now: widget.now,
            composerEmpty: composerEmpty,
            captureKeys: approvals.isEmpty,
            onAnswer: (answers) =>
                _run(() => backend.answerQuestion(id, question.id, answers)),
          ),
          const SizedBox(height: 8),
        ],
        for (final input in snap.queue) ...[
          QueuedRow(
            key: ValueKey('queued-${input.id}'),
            input: input,
            hideUnavailable: true,
            onSendNow: _caps.has(KitCapability.sendQueuedNow)
                ? (i) => _run(() => backend.sendQueuedNow(id, i.id))
                : null,
            onEdit: _caps.has(KitCapability.queueEdit)
                ? (i, text) => _run(() => backend.editQueued(id, i.id, text))
                : null,
            onRemove: _caps.has(KitCapability.queueEdit)
                ? (i) => _run(() => backend.removeQueued(id, i.id))
                : null,
          ),
          const SizedBox(height: 8),
        ],
        if (_error != null) ...[
          _ErrorLine(
            message: _error!,
            onDismiss: () => setState(() => _error = null),
          ),
          const SizedBox(height: 8),
        ],
        AgentComposer(
          onSubmit: _submit,
          running: running,
          canSend: _paneActions.send,
          placeholder: _paneActions.send
              ? 'Steer the agent…'
              : 'This chat is read-only.',
          onStop: _paneActions.stop
              ? () {
                  if (!_paneActions.stop) return;
                  _run(() => backend.cancel(id));
                }
              : null,
          models: models,
          modelId: snap.model,
          showModelPick: models.isNotEmpty,
          onModelChanged: (c) => _run(() => backend.setModel(id, c.id)),
          workspaces: profiles,
          workspaceId: snap.profile,
          onWorkspaceChanged: (c) => _run(() => backend.setProfile(id, c.id)),
          mentions: widget.mentions,
          mode: _mode,
          showModeToggle: _canSteer,
          onModeChanged: (m) => setState(() => _mode = m),
          controller: _text,
        ),
      ],
    );
  }

  /// [choices], plus the current one when the list does not hold it.
  static List<KitChoice> _withCurrent(List<KitChoice> choices, String? id) {
    if (id == null || choices.any((c) => c.id == id)) return choices;
    return [...choices, KitChoice(id: id, label: id)];
  }
}

/// The one inline line for a failed command, with a dismiss button.
class _ErrorLine extends StatelessWidget {
  const _ErrorLine({required this.message, required this.onDismiss});

  final String message;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final t = context.bb;
    return Semantics(
      container: true,
      liveRegion: true,
      label: message,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: t.radii.field,
          border: Border.all(color: t.colors.borderStrong),
        ),
        child: Padding(
          padding: const EdgeInsets.only(left: 10, right: 2),
          child: Row(
            children: [
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: ExcludeSemantics(
                    child: Text(
                      message,
                      style: ts(t.typeScale.uiSmall, t.dangerInk, weight: 600),
                    ),
                  ),
                ),
              ),
              KitIconButton(
                ComposerGlyphs.x,
                label: 'Dismiss',
                onTap: onDismiss,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

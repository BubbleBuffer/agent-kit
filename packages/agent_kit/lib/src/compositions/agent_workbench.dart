// AgentWorkbench: the whole agent app in one widget.
//
// The session rail (the chat list comes from the backend), the chat pane for
// the selected chat, the crew ledger or crew strip, and an optional workspace
// beside the chat. The layout follows the width the widget is given:
//
//  * the whole width picks the rail (a column, or a sliding screen when
//    compact) and whether the crew shows as a ledger beside the transcript
//    (expanded, no workspace) or as a strip under the header;
//  * the width beside the rail picks how the workspace sits: next to the chat
//    when expanded (the chat takes 44%, 444 to 584 px), a narrower column when
//    medium (40%, 240 to 420 px), a full-screen sheet over the chat when
//    compact.
//
// What the host supplies: per-model usage, the rail's detail text, the
// workspace's panes, and the actions the kit cannot know (opening a file).

import 'dart:math' as math;

import 'package:agent_kit_core/agent_kit_core.dart';
import 'package:bb_ui/bb_ui.dart';
import 'package:flutter/widgets.dart';

import '../chrome/chrome.dart';
import '../composer/composer.dart';
import '../composer/composer_parts.dart' show KitButton;
import '../context/context_pane.dart' show ContextPaneController;
import '../theme/theme.dart';
import '../transcript/transcript.dart';
import '../workspace/workspace.dart';
import 'agent_chat_pane.dart';
import 'agent_context_pane.dart';

/// The agent app: rail, chat, crew and workspace on one [backend].
class AgentWorkbench extends StatefulWidget {
  /// Creates the workbench.
  const AgentWorkbench({
    super.key,
    required this.backend,
    this.initialChatId,
    this.workspaceName = '',
    this.initials = '',
    this.now,
    this.modelUsage = const [],
    this.detailFor,
    this.railController,
    this.workspaceController,
    this.workspaceKinds = const [],
    this.workspacePaneBuilder,
    this.initialWorkspaceShown = false,
    this.onNewChat,
    this.onSearch,
    this.onSwitchWorkspace,
    this.onSettings,
    this.transcriptActions = const TranscriptActions(),
    this.mentions,
    this.onReviewApproval,
    this.onOpenAgent,
    this.onOpenJob,
  });

  /// Where the chats live.
  final AgentBackend backend;

  /// The chat to open first; the newest chat when null.
  final String? initialChatId;

  /// The project switcher's label in the rail.
  final String workspaceName;

  /// The avatar's letters.
  final String initials;

  /// Replaces the wall clock for ages (tests, the gallery).
  final DateTime? now;

  /// Tokens per model, for the ledger's "By model" bars. The kit cannot know
  /// them from a backend, so the host supplies them.
  final List<ModelUsage> modelUsage;

  /// The text after a rail row's status label ("edit approval").
  final String? Function(ChatSummary chat)? detailFor;

  /// Hides and shows the rail from outside; the workbench makes one if null.
  final RailController? railController;

  /// The workspace's layout. Without it, and without
  /// [workspacePaneBuilder], the workbench has no workspace.
  final WorkspaceController? workspaceController;

  /// The kinds the workspace's + menu lists.
  final List<WorkspaceKind> workspaceKinds;

  /// What each workspace pane shows.
  final WorkspacePaneBuilder? workspacePaneBuilder;

  /// Whether the workspace starts open.
  final bool initialWorkspaceShown;

  /// The rail's new-chat button. By default the workbench creates a chat
  /// through the backend and opens it.
  final VoidCallback? onNewChat;
  final VoidCallback? onSearch;
  final VoidCallback? onSwitchWorkspace;
  final VoidCallback? onSettings;

  /// What the transcript's rows open.
  final TranscriptActions transcriptActions;

  /// Where `@` mentions in the composer come from.
  final MentionSource? mentions;

  /// "Review diff" on an approval.
  final ValueChanged<Approval>? onReviewApproval;

  /// A crew chip was opened.
  final ValueChanged<ChildAgent>? onOpenAgent;
  final ValueChanged<BackgroundJob>? onOpenJob;

  @override
  State<AgentWorkbench> createState() => _AgentWorkbenchState();
}

class _AgentWorkbenchState extends State<AgentWorkbench> {
  final GlobalKey _sheetKey = GlobalKey(debugLabel: 'workbench sheet');
  final GlobalKey _workspaceKey = GlobalKey(debugLabel: 'workbench workspace');
  RailController? _ownRail;
  List<ChatSummary> _chats = const [];

  // The cursor for older chats, when the backend pages the list. Once an
  // older page is loaded, a refresh updates the first page in place instead
  // of dropping what was loaded.
  String? _nextCursor;
  bool _extended = false;
  bool _loadingMore = false;
  bool _loadMoreFailed = false;

  // Agents whose cancellation was asked for, and the last failure.
  final Set<String> _cancelling = {};
  String? _cancelError;
  String? _selected;
  bool _listed = false;
  String? _listError;
  late bool _workspaceShown = widget.initialWorkspaceShown;
  int _listing = 0;
  final ContextPaneController _context = ContextPaneController();
  ContextView? _contextView;

  RailController get _rail =>
      widget.railController ?? (_ownRail ??= RailController());

  bool get _hasWorkspace =>
      widget.workspaceController != null && widget.workspacePaneBuilder != null;

  @override
  void initState() {
    super.initState();
    _selected = widget.initialChatId;
    _refresh();
  }

  @override
  void didUpdateWidget(AgentWorkbench old) {
    super.didUpdateWidget(old);
    if (old.backend != widget.backend) {
      _selected = widget.initialChatId;
      _chats = const [];
      _nextCursor = null;
      _extended = false;
      _loadingMore = false;
      _loadMoreFailed = false;
      _cancelling.clear();
      _cancelError = null;
      _listed = false;
      _refresh();
    } else if (old.initialChatId != widget.initialChatId &&
        widget.initialChatId != null) {
      _selected = widget.initialChatId;
    }
  }

  @override
  void dispose() {
    _context.dispose();
    _ownRail?.dispose();
    super.dispose();
  }

  Future<void> _refresh() async {
    final ticket = ++_listing;
    final backend = widget.backend;
    try {
      final page = await backend.listChats();
      if (!mounted || ticket != _listing || backend != widget.backend) return;
      setState(() {
        if (_extended) {
          final first = {for (final c in page.chats) c.id};
          _chats = [
            ...page.chats,
            for (final c in _chats)
              if (!first.contains(c.id)) c,
          ];
        } else {
          _chats = page.chats;
          _nextCursor = page.nextCursor;
        }
        _listed = true;
        _listError = null;
        _selected ??= page.chats.isEmpty ? null : page.chats.first.id;
      });
    } catch (error) {
      if (!mounted || ticket != _listing) return;
      setState(() {
        _listed = true;
        _listError = error is KitError
            ? error.message
            : 'Something went wrong.';
      });
    }
  }

  Future<void> _loadMore() async {
    final cursor = _nextCursor;
    final backend = widget.backend;
    if (cursor == null || _loadingMore) return;
    setState(() {
      _loadingMore = true;
      _loadMoreFailed = false;
    });
    try {
      final page = await backend.listChats(cursor: cursor);
      if (!mounted || backend != widget.backend) return;
      setState(() {
        final known = {for (final c in _chats) c.id};
        _chats = [
          ..._chats,
          for (final c in page.chats)
            if (!known.contains(c.id)) c,
        ];
        _nextCursor = page.nextCursor;
        _extended = true;
        _loadingMore = false;
      });
    } catch (_) {
      if (!mounted || backend != widget.backend) return;
      setState(() {
        _loadingMore = false;
        _loadMoreFailed = true;
      });
    }
  }

  bool get _canCancelAgent =>
      widget.backend.capabilities.has(KitCapability.children);

  Future<void> _cancelAgent(String chatId, ChildAgent agent) async {
    final backend = widget.backend;
    setState(() {
      _cancelling.add(agent.id);
      _cancelError = null;
    });
    try {
      await backend.cancelChild(chatId, agent.id);
    } catch (error) {
      if (!mounted || backend != widget.backend) return;
      setState(() {
        _cancelling.remove(agent.id);
        _cancelError =
            'Could not cancel “${agent.task}”. '
            '${error is KitError ? error.message : 'Something went wrong.'}';
      });
    }
  }

  void _select(String id) {
    if (id == _selected) return;
    setState(() {
      _selected = id;
      _contextView = null;
    });
  }

  bool get _canContext =>
      widget.backend.capabilities.has(KitCapability.context);

  /// The header's context meter and the compaction marker's View: add the
  /// Context pane when the chat has none, show the workspace and bring the
  /// pane to the front on the Now tab.
  void _openContext() {
    final controller = widget.workspaceController;
    if (!_hasWorkspace || controller == null) return;
    final existing = controller.layout.tabs
        .where((t) => t.kind == WorkspaceKind.context.id)
        .firstOrNull;
    if (existing == null) {
      controller.addPane(WorkspaceKind.context.id);
    } else {
      controller.activate(existing.id);
    }
    setState(() => _workspaceShown = true);
    // The pane is built in the next frame when it was just added.
    WidgetsBinding.instance.addPostFrameCallback((_) => _context.showNow());
  }

  Widget _paneBuilder(BuildContext context, WorkspaceTab tab) {
    if (tab.kind != WorkspaceKind.context.id || !_canContext) {
      return widget.workspacePaneBuilder!(context, tab);
    }
    final chat = _selected;
    if (chat == null) return const SizedBox.shrink();
    return AgentContextPane(
      backend: widget.backend,
      chatId: chat,
      view: _contextView,
      controller: _context,
      now: widget.now,
    );
  }

  void _onSnapshot(ChatSnapshot snap) {
    if (snap.chatId == _selected && snap.context != _contextView) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && snap.chatId == _selected) {
          setState(() => _contextView = snap.context);
        }
      });
    }
    // Keep the rail's row in step with the open chat.
    final row = _chats.where((c) => c.id == snap.chatId).firstOrNull;
    final now = ChatSummary.of(snap);
    if (row == null ||
        row.status != now.status ||
        row.title != now.title ||
        row.runningChildren != now.runningChildren) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _refresh();
      });
    }
  }

  Future<void> _newChat() async {
    final custom = widget.onNewChat;
    if (custom != null) {
      custom();
      return;
    }
    try {
      final chat = await widget.backend.createChat();
      if (!mounted) return;
      setState(() => _selected = chat.id);
      _refresh();
    } catch (_) {
      // The rail stays as it was.
    }
  }

  void _toggleWorkspace() => setState(() => _workspaceShown = !_workspaceShown);

  // ---------------------------------------------------------------- build

  @override
  Widget build(BuildContext context) {
    final t = context.bb;
    final clock = widget.now ?? DateTime.now();
    return ColoredBox(
      color: t.canvas,
      child: RailLayout(
        controller: _rail,
        rail: SessionRail(
          workspaceName: widget.workspaceName,
          groups: groupSessions(_chats, clock),
          selectedId: _selected,
          detailFor: (chat) =>
              widget.detailFor?.call(chat) ?? railDetail(chat, clock),
          now: clock,
          initials: widget.initials,
          onSelect: (chat) => _select(chat.id),
          onNewChat: _newChat,
          onSearch: widget.onSearch,
          onSwitchWorkspace: widget.onSwitchWorkspace,
          onSettings: widget.onSettings,
          hasMore: _nextCursor != null,
          loadingMore: _loadingMore,
          loadMoreFailed: _loadMoreFailed,
          onLoadMore: _loadMore,
        ),
        child: Builder(
          builder: (context) {
            final whole =
                RailScope.maybeOf(context)?.sizeClass ?? SizeClass.expanded;
            return SizeClassBuilder(
              builder: (context, area) => LayoutBuilder(
                builder: (context, box) =>
                    _area(context, t, whole, area, box.maxWidth),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _area(
    BuildContext context,
    BbTheme t,
    SizeClass whole,
    SizeClass area,
    double width,
  ) {
    final shown = _hasWorkspace && _workspaceShown;
    final ledger = whole.isExpanded && !shown;
    final sheet = _sheet(context, t, whole, ledger);
    if (!_hasWorkspace) return sheet;
    final workspace = KeyedSubtree(
      key: _workspaceKey,
      child: AgentWorkspace(
        controller: widget.workspaceController!,
        kinds: [
          ...widget.workspaceKinds,
          if (_canContext &&
              !widget.workspaceKinds.any(
                (k) => k.id == WorkspaceKind.context.id,
              ))
            WorkspaceKind.context,
        ],
        paneBuilder: _paneBuilder,
        open: shown,
        onClose: _toggleWorkspace,
        sizeClass: area,
      ),
    );
    if (area.isCompact) {
      return Stack(
        fit: StackFit.expand,
        children: [
          sheet,
          Positioned.fill(child: workspace),
        ],
      );
    }
    if (!shown) return sheet;
    final padded = Padding(
      padding: const EdgeInsets.fromLTRB(0, 12, 12, 12),
      child: workspace,
    );
    if (area.isMedium) {
      final w = math.min(420.0, math.max(240.0, width * .4));
      return Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(child: sheet),
          SizedBox(width: w, child: padded),
        ],
      );
    }
    final w = math.min(584.0, math.max(444.0, width * .44));
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(width: w, child: sheet),
        Expanded(child: padded),
      ],
    );
  }

  Widget _sheet(BuildContext context, BbTheme t, SizeClass whole, bool ledger) {
    final selected = _selected;
    final Widget content;
    if (selected == null) {
      content = _empty(t);
    } else {
      content = AgentChatPane(
        backend: widget.backend,
        chatId: selected,
        now: widget.now,
        showCrewStrip: !ledger,
        sideBuilder: ledger ? _ledger : null,
        workspaceShown: _hasWorkspace && _workspaceShown,
        onToggleWorkspace: _hasWorkspace ? _toggleWorkspace : null,
        onSnapshot: _onSnapshot,
        onOpenChat: (id) {
          _select(id);
          _refresh();
        },
        onChatsChanged: _refresh,
        transcriptActions: widget.transcriptActions,
        mentions: widget.mentions,
        onReviewApproval: widget.onReviewApproval,
        onOpenAgent: widget.onOpenAgent,
        onOpenJob: widget.onOpenJob,
        onOpenContext: _hasWorkspace && _canContext ? _openContext : null,
      );
    }
    if (whole.isCompact) {
      return KeyedSubtree(
        key: _sheetKey,
        child: ColoredBox(color: t.surface, child: content),
      );
    }
    final radius = BorderRadius.vertical(top: Radius.circular(t.radii.sheet));
    return KeyedSubtree(
      key: _sheetKey,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: t.surface,
            borderRadius: radius,
            boxShadow: t.colors.stack,
          ),
          child: ClipRRect(borderRadius: radius, child: content),
        ),
      ),
    );
  }

  Widget? _ledger(BuildContext context, ChatSnapshot snap) {
    final clock = widget.now;
    final t = context.bb;
    // Nothing running and no usage to show: no side column at all.
    if (snap.children.isEmpty &&
        snap.jobs.isEmpty &&
        widget.modelUsage.isEmpty) {
      return null;
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        CrewLedger(
          agents: snap.children,
          jobs: snap.jobs,
          now: clock,
          onOpenAgent: widget.onOpenAgent,
          onOpenJob: widget.onOpenJob,
          onCancelAgent: _canCancelAgent
              ? (agent) => _cancelAgent(snap.chatId, agent)
              : null,
          cancelling: _cancelling,
        ),
        if (_cancelError != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 0),
            child: Semantics(
              liveRegion: true,
              child: Text(
                _cancelError!,
                key: const ValueKey('ledger-cancel-error'),
                style: ts(const TypeSpec(12, 16, 400), t.dangerInk),
              ),
            ),
          ),
        if (widget.modelUsage.isNotEmpty) ...[
          if (snap.children.isNotEmpty || snap.jobs.isNotEmpty)
            const SizedBox(height: 16),
          UsageByModel(models: widget.modelUsage, usage: snap.usage),
        ],
      ],
    );
  }

  Widget _empty(BbTheme t) {
    if (!_listed) {
      return Center(
        child: Text('Loading…', style: ts(t.typeScale.ui, t.faint)),
      );
    }
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _listError ?? 'No chats yet',
            style: ts(t.typeScale.ui, t.muted),
          ),
          const SizedBox(height: 12),
          if (_listError == null)
            KitButton(label: 'New chat', onTap: _newChat)
          else
            KitButton(label: 'Retry', onTap: _refresh),
        ],
      ),
    );
  }
}

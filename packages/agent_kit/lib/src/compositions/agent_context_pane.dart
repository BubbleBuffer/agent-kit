// AgentContextPane: the Context pane of one chat, fed by an AgentBackend.
//
// The host passes the serving view it already has (`ChatSnapshot.context`);
// the pane loads the structure behind it (`loadContext`) when the view
// changes, and gives the pane its two loaders (original messages by range,
// one summary's full text). Together with AgentChatPane and AgentWorkbench
// it is the only widget that calls a backend. A backend without the
// `context` capability gets a quiet line instead.

import 'dart:async';

import 'package:agent_kit_core/agent_kit_core.dart';
import 'package:bb_ui/bb_ui.dart';
import 'package:flutter/widgets.dart';

import '../context/context_pane.dart';
import '../theme/theme.dart';
import '../transcript/markdown.dart';

/// The Context pane for [chatId] on [backend], showing [view].
class AgentContextPane extends StatefulWidget {
  const AgentContextPane({
    super.key,
    required this.backend,
    required this.chatId,
    required this.view,
    this.controller,
    this.now,
    this.renderer = const LeanMarkdownRenderer(),
  });

  final AgentBackend backend;
  final String chatId;

  /// The current serving view; null shows "no context data".
  final ContextView? view;
  final ContextPaneController? controller;
  final DateTime? now;
  final MarkdownRenderer renderer;

  @override
  State<AgentContextPane> createState() => _AgentContextPaneState();
}

class _AgentContextPaneState extends State<AgentContextPane> {
  ContextDetails? _details;
  int _loading = 0;

  bool get _supported => widget.backend.capabilities.has(KitCapability.context);

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(AgentContextPane old) {
    super.didUpdateWidget(old);
    if (old.chatId != widget.chatId || old.backend != widget.backend) {
      _details = null;
      _load();
    } else if (old.view != widget.view) {
      _load();
    }
  }

  Future<void> _load() async {
    if (!_supported || widget.view == null) return;
    final ticket = ++_loading;
    final backend = widget.backend;
    final chat = widget.chatId;
    try {
      final d = await backend.loadContext(chat);
      if (!mounted || ticket != _loading) return;
      setState(() => _details = d);
    } catch (_) {
      // The pane keeps what it has; the view still shows.
    }
  }

  @override
  Widget build(BuildContext context) {
    final view = widget.view;
    if (!_supported || view == null) {
      final t = context.bb;
      return ColoredBox(
        color: t.surface,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              'This chat has no context data yet.',
              textAlign: TextAlign.center,
              style: ts(t.typeScale.ui, t.faint, weight: 400),
            ),
          ),
        ),
      );
    }
    final backend = widget.backend;
    final chat = widget.chatId;
    return ContextPane(
      view: view,
      details: _details,
      controller: widget.controller,
      renderer: widget.renderer,
      now: widget.now,
      loadHistory: (first, last) => backend.loadHistoryRange(chat, first, last),
      loadSummary: (id) => backend.loadSummary(chat, id),
    );
  }
}

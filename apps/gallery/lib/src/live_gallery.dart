import 'dart:async';
import 'dart:ui' show AppExitResponse;

import 'package:agent_kit/agent_kit.dart';
import 'package:agent_kit_bubblepaw/agent_kit_bubblepaw.dart';
import 'package:agent_kit_core/agent_kit_core.dart' show ChatSummary;
import 'package:bb_ui/bb_ui.dart' show AppColors;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/widgets.dart';

import 'gallery_app.dart';

/// Optional local-host mode. With no defines the scripted gallery is unchanged.
class GalleryLaunch extends StatelessWidget {
  const GalleryLaunch({
    super.key,
    this.binaryPath = const String.fromEnvironment('BP_BIN'),
    this.workspaceDirectory = const String.fromEnvironment('BP_WORKSPACE'),
    this.dataDirectory = const String.fromEnvironment('BP_DATA'),
  });

  final String binaryPath;
  final String workspaceDirectory;
  final String dataDirectory;

  @override
  Widget build(BuildContext context) {
    final supplied = [
      binaryPath,
      workspaceDirectory,
      dataDirectory,
    ].where((value) => value.trim().isNotEmpty).length;
    if (supplied == 0) return const GalleryApp();
    if (supplied != 3) {
      return const _LiveShell(
        child: _ConnectionStatus(
          title: 'Live gallery needs all three settings',
          message:
              'Supply BP_BIN, BP_WORKSPACE and BP_DATA together, '
              'or clear all three to open the scripted gallery.',
        ),
      );
    }
    if (kIsWeb) {
      return const _LiveShell(
        child: _ConnectionStatus(
          title: 'Live gallery needs a desktop app',
          message:
              'A browser cannot launch the local BubblePaw host. '
              'Run the desktop gallery with these settings, '
              'or clear them to open the scripted gallery.',
        ),
      );
    }
    return _LiveGallery(
      binaryPath: binaryPath,
      workspaceDirectory: workspaceDirectory,
      dataDirectory: dataDirectory,
    );
  }
}

class _LiveGallery extends StatefulWidget {
  const _LiveGallery({
    required this.binaryPath,
    required this.workspaceDirectory,
    required this.dataDirectory,
  });

  final String binaryPath;
  final String workspaceDirectory;
  final String dataDirectory;

  @override
  State<_LiveGallery> createState() => _LiveGalleryState();
}

class _LiveGalleryState extends State<_LiveGallery> {
  late final Future<BubblePawBackend?> _starting;
  late final AppLifecycleListener _lifecycle;
  BubblePawBackend? _backend;
  StreamSubscription<ChatSummary>? _createdChats;
  String? _initialChatId;
  Future<void>? _closing;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _starting = _start();
    _lifecycle = AppLifecycleListener(
      onExitRequested: () async {
        await _close();
        return AppExitResponse.exit;
      },
      onDetach: () => unawaited(_close()),
    );
  }

  Future<BubblePawBackend?> _start() async {
    try {
      final backend = await BubblePawBackend.start(
        binaryPath: widget.binaryPath,
        workspaceDirectory: widget.workspaceDirectory,
        dataDirectory: widget.dataDirectory,
      );
      if (mounted && _closing == null) {
        _createdChats = backend.createdChats.listen((chat) {
          if (mounted && _closing == null) {
            setState(() => _initialChatId = chat.id);
          }
        });
        setState(() => _backend = backend);
      }
      return backend;
    } catch (_) {
      // Startup errors can contain local paths or provider diagnostics.
      if (mounted && _closing == null) setState(() => _failed = true);
      return null;
    }
  }

  Future<void> _close() => _closing ??= _disposeBackend();

  Future<void> _disposeBackend() async {
    final backend = await _starting;
    try {
      await _createdChats?.cancel();
      await backend?.dispose();
    } catch (_) {
      // Closing the window must not expose local host diagnostics.
    }
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    unawaited(_close());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final backend = _backend;
    return _LiveShell(
      child: backend != null
          ? AgentWorkbench(
              // A new rewind result needs both selection and a fresh rail list.
              // didUpdateWidget selects an ID but does not reload the rail.
              key: ValueKey(_initialChatId),
              backend: backend,
              initialChatId: _initialChatId,
              workspaceName: 'BubblePaw',
            )
          : _ConnectionStatus(
              title: _failed
                  ? 'Could not start BubblePaw'
                  : 'Starting BubblePaw…',
              message: _failed
                  ? 'Check the binary, workspace and data settings, '
                        'then restart the gallery.'
                  : 'Connecting to the local host.',
            ),
    );
  }
}

class _LiveShell extends StatelessWidget {
  const _LiveShell({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => WidgetsApp(
    title: 'Agent kit · BubblePaw',
    color: AppColors.light.desk,
    debugShowCheckedModeBanner: false,
    pageRouteBuilder: <T>(settings, builder) => PageRouteBuilder<T>(
      settings: settings,
      pageBuilder: (context, animation, secondary) => builder(context),
    ),
    home: BbThemeScope(brightness: Brightness.light, child: child),
  );
}

class _ConnectionStatus extends StatelessWidget {
  const _ConnectionStatus({required this.title, required this.message});

  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    final theme = context.bb;
    return ColoredBox(
      color: theme.canvas,
      child: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: Semantics(
                liveRegion: true,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: DefaultTextStyle.of(context).style
                          .copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 12),
                    Text(message, style: TextStyle(color: theme.muted)),
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

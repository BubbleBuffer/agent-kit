// The gallery app: a toolbar over one scene at the chosen width, driven by the
// scripted fake backend.

import 'dart:async';

import 'package:agent_kit/agent_kit.dart';
import 'package:flutter/widgets.dart';

import 'gallery_controller.dart';
import 'scene_frame.dart';
import 'toolbar.dart';

class GalleryApp extends StatefulWidget {
  /// Runs on [controller], or on a new one (manual clock, played to the end).
  const GalleryApp({super.key, this.controller});

  final GalleryController? controller;

  @override
  State<GalleryApp> createState() => _GalleryAppState();
}

class _GalleryAppState extends State<GalleryApp> {
  late final GalleryController _controller =
      widget.controller ?? GalleryController();
  late final bool _owns = widget.controller == null;

  @override
  void initState() {
    super.initState();
    if (_owns) unawaited(_controller.start());
  }

  @override
  void dispose() {
    if (_owns) _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => WidgetsApp(
    title: 'Agent kit gallery',
    color: const Color(0xFFECE6DB),
    debugShowCheckedModeBanner: false,
    pageRouteBuilder: <T>(settings, builder) => PageRouteBuilder<T>(
      settings: settings,
      pageBuilder: (context, animation, secondary) => builder(context),
    ),
    home: _Shell(controller: _controller),
  );
}

class _Shell extends StatelessWidget {
  const _Shell({required this.controller});

  final GalleryController controller;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: controller,
    builder: (context, _) => BbThemeScope(
      brightness: controller.brightness,
      child: Column(
        children: [
          GalleryToolbar(controller: controller),
          Expanded(
            child: SceneFrame(
              scene: controller.scene,
              snapshot: controller.snapshot,
              width: controller.width,
              brightness: controller.brightness,
            ),
          ),
        ],
      ),
    ),
  );
}

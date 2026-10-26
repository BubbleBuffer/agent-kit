// RailLayout: the rail beside (or over) its content, hidden fully and
// animated with the sheet motion tokens (`.rail-hidden`, `.rail-open` in the
// mockup's app.css).
//
// Medium and expanded: the rail is a 240 px column that folds to 0 and slides
// out. Compact: the content fills the width and the rail is a sliding screen
// over it. Ctrl+B (Cmd+B) toggles it whenever focus is inside.

import 'package:bb_ui/bb_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../theme/theme.dart';
import 'chrome_button.dart';
import 'chrome_icons.dart';
import 'rail_model.dart';

/// Lays out [rail] (a `SessionRail`) and [child] by the width of its own
/// area, and shows or hides the rail as [controller] says.
///
/// It measures its area with a `SizeClassBuilder`, so [child] sees that
/// class unless it measures its own. [RailScope] carries the controller to
/// the rail's hide button and to `RailShowButton`.
class RailLayout extends StatelessWidget {
  const RailLayout({
    super.key,
    required this.controller,
    required this.rail,
    required this.child,
  });

  final RailController controller;
  final Widget rail;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return SizeClassBuilder(
      builder: (context, sizeClass) => ListenableBuilder(
        listenable: controller,
        builder: (context, _) {
          final theme = context.bb;
          final visible = controller.isVisible(sizeClass);
          final duration = Motion.of(context).sheet;
          final Widget body = sizeClass.isCompact
              ? _Sliding(
                  visible: visible,
                  duration: duration,
                  rail: rail,
                  child: child,
                )
              : _Column(
                  visible: visible,
                  duration: duration,
                  line: theme.railLine,
                  rail: rail,
                  child: child,
                );
          return RailScope(
            controller: controller,
            sizeClass: sizeClass,
            visible: visible,
            child: CallbackShortcuts(
              bindings: {
                const SingleActivator(
                  LogicalKeyboardKey.keyB,
                  control: true,
                ): () =>
                    controller.toggle(sizeClass),
                const SingleActivator(
                  LogicalKeyboardKey.keyB,
                  meta: true,
                ): () =>
                    controller.toggle(sizeClass),
              },
              child: body,
            ),
          );
        },
      ),
    );
  }
}

class _Column extends StatelessWidget {
  const _Column({
    required this.visible,
    required this.duration,
    required this.line,
    required this.rail,
    required this.child,
  });

  final bool visible;
  final Duration duration;
  final Color line;
  final Widget rail;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TweenAnimationBuilder<double>(
          tween: Tween<double>(end: visible ? 1.0 : 0.0),
          duration: duration,
          curve: Motion.ease,
          builder: (context, v, _) {
            if (v == 0) return const SizedBox.shrink();
            return ClipRect(
              child: Align(
                alignment: Alignment.centerRight,
                widthFactor: v,
                child: SizedBox(
                  width: Layout.sidebarWidth,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(child: rail),
                      SizedBox(width: 1, child: ColoredBox(color: line)),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
        Expanded(child: child),
      ],
    );
  }
}

class _Sliding extends StatelessWidget {
  const _Sliding({
    required this.visible,
    required this.duration,
    required this.rail,
    required this.child,
  });

  final bool visible;
  final Duration duration;
  final Widget rail;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(child: child),
        Positioned.fill(
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(end: visible ? 1.0 : 0.0),
            duration: duration,
            curve: Motion.ease,
            builder: (context, v, _) {
              if (v == 0) return const SizedBox.shrink();
              return FractionalTranslation(
                translation: Offset(v - 1, 0),
                child: rail,
              );
            },
          ),
        ),
      ],
    );
  }
}

/// The header's button that brings the rail back: the menu button in
/// compact (the sliding screen), `panel-left-open` when the column is
/// hidden, and nothing while the rail shows or outside a [RailLayout].
/// [gap] is the space after it, only when it shows.
class RailShowButton extends StatelessWidget {
  const RailShowButton({super.key, this.gap = 8, this.size = 32});

  final double gap;
  final double size;

  @override
  Widget build(BuildContext context) {
    final scope = RailScope.maybeOf(context);
    if (scope == null) return const SizedBox.shrink();
    final Widget button;
    if (scope.sizeClass.isCompact) {
      button = ChromeIconButton(
        glyphMenu,
        key: const ValueKey('rail-show'),
        label: 'Sessions',
        size: size,
        glyphSize: 20,
        onTap: () => scope.controller.show(scope.sizeClass),
      );
    } else if (!scope.visible) {
      button = ChromeIconButton(
        glyphPanelLeftOpen,
        key: const ValueKey('rail-show'),
        label: 'Show sidebar',
        shortcut: 'Ctrl+B',
        size: size,
        onTap: () => scope.controller.show(scope.sizeClass),
      );
    } else {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: EdgeInsets.only(right: gap),
      child: button,
    );
  }
}

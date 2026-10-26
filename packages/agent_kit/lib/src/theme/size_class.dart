// Size classes: layout by the width of the container, never the window.

import 'package:flutter/widgets.dart';

import 'bb_theme.dart';

/// The three layouts of a kit area (`--size-medium` and `--size-expanded` in
/// the mockup's theme.css): compact below `sizeMedium`, medium to below
/// `sizeExpanded`, expanded from there up.
enum SizeClass {
  compact,
  medium,
  expanded;

  /// The class of a container [width] with the given thresholds.
  static SizeClass forWidth(
    double width, {
    double medium = 600,
    double expanded = 1000,
  }) => width < medium
      ? SizeClass.compact
      : width < expanded
      ? SizeClass.medium
      : SizeClass.expanded;

  bool get isCompact => this == compact;
  bool get isMedium => this == medium;
  bool get isExpanded => this == expanded;

  /// Whether this class is [other] or wider.
  bool atLeast(SizeClass other) => index >= other.index;

  /// The class of the nearest [SizeClassBuilder] above [context].
  static SizeClass of(BuildContext context) {
    final scope = maybeOf(context);
    assert(scope != null, 'No SizeClassBuilder above this context.');
    return scope!;
  }

  /// Like [of], or null when there is none.
  static SizeClass? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<SizeClassScope>()?.sizeClass;
}

/// Measures its own width with a [LayoutBuilder] and gives [builder] the
/// [SizeClass] from the theme's thresholds. Descendants can read it with
/// [SizeClass.of]. An unbounded width counts as expanded.
class SizeClassBuilder extends StatelessWidget {
  const SizeClassBuilder({super.key, required this.builder});

  final Widget Function(BuildContext context, SizeClass sizeClass) builder;

  @override
  Widget build(BuildContext context) {
    final theme = BbTheme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final sizeClass = constraints.hasBoundedWidth
            ? SizeClass.forWidth(
                constraints.maxWidth,
                medium: theme.sizeMedium,
                expanded: theme.sizeExpanded,
              )
            : SizeClass.expanded;
        return SizeClassScope(
          sizeClass: sizeClass,
          child: Builder(builder: (context) => builder(context, sizeClass)),
        );
      },
    );
  }
}

/// Carries a [SizeClass] to descendants.
class SizeClassScope extends InheritedWidget {
  const SizeClassScope({
    super.key,
    required this.sizeClass,
    required super.child,
  });

  final SizeClass sizeClass;

  @override
  bool updateShouldNotify(SizeClassScope old) => old.sizeClass != sizeClass;
}

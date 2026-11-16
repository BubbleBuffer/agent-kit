// Size classes: layout by the width of the container, never the window.
//
// The classes and their scope are bb-ui's (`SizeClass`, `SizeClassScope` in
// bb_tokens, compact below `SizeClass.mediumWidth`, medium below
// `SizeClass.expandedWidth`); this adds the kit's builder and lookups.

import 'package:bb_ui/tokens.dart';
import 'package:flutter/widgets.dart';

export 'package:bb_ui/tokens.dart' show SizeClass, SizeClassScope;

/// The kit's questions about a [SizeClass].
extension KitSizeClass on SizeClass {
  bool get isMedium => this == SizeClass.medium;
  bool get isExpanded => this == SizeClass.expanded;
}

/// The class of the nearest [SizeClassScope] above [context] (a
/// [SizeClassBuilder] puts one), or [SizeClass.expanded] when there is none.
///
/// Unlike `context.sizeClass` this never falls back to the window: a kit
/// area without a builder lays out as the widest class.
SizeClass sizeClassOf(BuildContext context) =>
    context.dependOnInheritedWidgetOfExactType<SizeClassScope>()?.sizeClass ??
    SizeClass.expanded;

/// Measures its own width with a [LayoutBuilder] and gives [builder] the
/// [SizeClass] of that width. Descendants read it with [sizeClassOf] or
/// `context.sizeClass`. An unbounded width counts as expanded.
class SizeClassBuilder extends StatelessWidget {
  const SizeClassBuilder({super.key, required this.builder});

  final Widget Function(BuildContext context, SizeClass sizeClass) builder;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final sizeClass = constraints.hasBoundedWidth
            ? SizeClass.forWidth(constraints.maxWidth)
            : SizeClass.expanded;
        return SizeClassScope(
          sizeClass: sizeClass,
          child: Builder(builder: (context) => builder(context, sizeClass)),
        );
      },
    );
  }
}

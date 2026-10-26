// The rail's data and its hidden state.

import 'package:agent_kit_core/agent_kit_core.dart' show ChatSummary;
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../theme/theme.dart';

/// A labelled run of rows in the rail ("Today", "Earlier").
@immutable
class SessionGroup {
  const SessionGroup(this.label, this.chats);

  final String label;
  final List<ChatSummary> chats;
}

/// Whether the rail is shown. Above compact the rail is a column that
/// [hidden] folds away; in compact it is a sliding screen that [open] shows.
/// The two are kept apart, as in the mockup, so resizing keeps each choice.
class RailController extends ChangeNotifier {
  RailController({bool hidden = false, bool open = false})
    : _hidden = hidden,
      _open = open;

  bool _hidden;
  bool _open;

  /// Medium and expanded: the column is folded away.
  bool get hidden => _hidden;
  set hidden(bool value) {
    if (value == _hidden) return;
    _hidden = value;
    notifyListeners();
  }

  /// Compact: the sliding screen is shown.
  bool get open => _open;
  set open(bool value) {
    if (value == _open) return;
    _open = value;
    notifyListeners();
  }

  /// Whether the rail shows at [sizeClass].
  bool isVisible(SizeClass sizeClass) => sizeClass.isCompact ? _open : !_hidden;

  void show(SizeClass sizeClass) {
    if (sizeClass.isCompact) {
      open = true;
    } else {
      hidden = false;
    }
  }

  void hide(SizeClass sizeClass) {
    if (sizeClass.isCompact) {
      open = false;
    } else {
      hidden = true;
    }
  }

  void toggle(SizeClass sizeClass) {
    if (isVisible(sizeClass)) {
      hide(sizeClass);
    } else {
      show(sizeClass);
    }
  }
}

/// What a `RailLayout` tells the widgets inside it: the controller, the size
/// class of the whole layout and whether the rail is shown. The rail's hide
/// button and the header's `RailShowButton` read it.
class RailScope extends InheritedWidget {
  const RailScope({
    super.key,
    required this.controller,
    required this.sizeClass,
    required this.visible,
    required super.child,
  });

  final RailController controller;
  final SizeClass sizeClass;
  final bool visible;

  /// The scope above [context], or null.
  static RailScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<RailScope>();

  @override
  bool updateShouldNotify(RailScope old) =>
      old.controller != controller ||
      old.sizeClass != sizeClass ||
      old.visible != visible;
}

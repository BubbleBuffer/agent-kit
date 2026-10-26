// The workspace controller: holds a [WorkspaceLayout], applies its pure
// operations and notifies. Hosts keep one, listen to it to persist the
// layout (`toJson`) and give it back to [AgentWorkspace].

import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'workspace_model.dart';

class WorkspaceController extends ChangeNotifier {
  WorkspaceController([WorkspaceLayout layout = const WorkspaceLayout.empty()])
    : _layout = layout;

  /// Reads a controller from [WorkspaceLayout.toJson] output.
  factory WorkspaceController.fromJson(Map<String, Object?> json) =>
      WorkspaceController(WorkspaceLayout.fromJson(json));

  WorkspaceLayout _layout;

  WorkspaceLayout get layout => _layout;

  set layout(WorkspaceLayout value) {
    if (value == _layout) return;
    _layout = value;
    notifyListeners();
  }

  Map<String, Object?> toJson() => _layout.toJson();

  /// The layout as text, for a settings file.
  String encode() => jsonEncode(toJson());

  /// Replaces the layout with one written by [encode].
  void decode(String text) {
    layout = WorkspaceLayout.fromJson(
      (jsonDecode(text) as Map).cast<String, Object?>(),
    );
  }

  void addPane(String kind, {String? title, String? besideLeaf}) => layout =
      _layout.addPane(kind: kind, title: title, besideLeaf: besideLeaf);

  void addTab(String leafId, String kind, {String? title}) =>
      layout = _layout.addTab(leafId: leafId, kind: kind, title: title);

  void split(String leafId, DockSide side, String kind, {String? title}) =>
      layout = _layout.split(
        leafId: leafId,
        side: side,
        kind: kind,
        title: title,
      );

  void closeTab(String tabId) => layout = _layout.closeTab(tabId);

  void closeLeaf(String leafId) => layout = _layout.closeLeaf(leafId);

  void activate(String tabId) => layout = _layout.activate(tabId);

  void dock(String tabId, DockTarget target) =>
      layout = _layout.dock(tabId, target);

  void resize(String splitId, int index, double share) =>
      layout = _layout.resize(splitId, index, share);

  void evenSplit(String splitId, int index) =>
      layout = _layout.evenSplit(splitId, index);

  void collapse(String nodeId) => layout = _layout.collapse(nodeId);

  void restore(String nodeId) => layout = _layout.restore(nodeId);

  void toggleCollapse(String nodeId) =>
      layout = _layout.toggleCollapse(nodeId);

  void maximise(String leafId) => layout = _layout.maximise(leafId);

  void unmaximise() => layout = _layout.unmaximise();

  void toggleMaximise(String leafId) =>
      layout = _layout.toggleMaximise(leafId);
}

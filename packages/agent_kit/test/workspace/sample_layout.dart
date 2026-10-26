// Shared fixtures of the workspace tests: the default tree of the mockup
// (browser on the left; terminal over the file preview on the right).

import 'package:agent_kit/agent_kit.dart';
import 'package:flutter/widgets.dart';

const kinds = [
  WorkspaceKind(id: 'browser', label: 'Browser', icon: IconData(0xe0f3)),
  WorkspaceKind(id: 'terminal', label: 'Terminal', icon: IconData(0xe1b6)),
  WorkspaceKind(id: 'file', label: 'File', icon: IconData(0xe0d9)),
  WorkspaceKind(id: 'activity', label: 'Activity', icon: IconData(0xe038)),
];

WorkspaceLayout sampleLayout() => WorkspaceLayout(
  root: WorkspaceSplit(
    id: 'root',
    axis: SplitAxis.row,
    children: [
      WorkspaceLeaf(
        id: 'b',
        tabs: const [WorkspaceTab(id: 'browser', kind: 'browser')],
      ),
      WorkspaceSplit(
        id: 'right',
        axis: SplitAxis.column,
        weights: const [1.15, 0.85],
        children: [
          WorkspaceLeaf(
            id: 't',
            tabs: const [WorkspaceTab(id: 'terminal', kind: 'terminal')],
          ),
          WorkspaceLeaf(
            id: 'f',
            tabs: const [WorkspaceTab(id: 'file', kind: 'file')],
          ),
        ],
      ),
    ],
  ),
  front: 'browser',
);

/// The ids of the tabs of every leaf, in tree order, one string per leaf.
List<String> shape(WorkspaceLayout l) => [
  for (final leaf in l.leaves) leaf.tabs.map((t) => t.id).join('+'),
];

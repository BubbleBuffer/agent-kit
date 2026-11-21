// The agent kit's own values: dimensions and steps particular to its
// widgets that bb-ui's shared scales (bb_tokens) do not have. Named here so
// widgets never write a number (the bb_lints rules accept raw values in a
// `*_tokens.dart` library). Everything else comes from bb_tokens' Space,
// ControlSize, IconSize, Stroke, Alpha, Radii and Motion.
//
// Kit-wide layout sizes from the mockup's theme.css stay in bb_tokens'
// `KitLayout`; read them through `BbTheme.layout`.

import 'dart:ui' show Offset, Size;

/// Opacity steps of the kit beyond bb-ui's `Alpha`.
abstract final class KitAlpha {
  /// Fully opaque: the resting end of a fade or dim.
  static const double opaque = 1;

  /// The rail's selected row over the dark rail.
  static const double railSelected = .10;

  /// The ink wash over a secondary button on hover, and the danger ink's
  /// over a danger button.
  static const double hover = .05, dangerHover = .08;

  /// The workspace's dock preview over the pane it would split.
  static const double dockPreview = .72;
}

/// Sizes particular to the kit's widgets.
abstract final class KitSizes {
  /// The composer's @-mention menu, when the composer is wider than compact.
  static const double mentionMenu = 324;

  /// The workspace's + menu.
  static const double paneMenu = 176;

  /// The workspace's size when its parent does not bound it.
  static const unboundedWorkspace = Size(1000, 600);

  /// A header on a compact screen: the chat header and the workspace sheet's
  /// tab bar.
  static const double compactHeader = 52;

  /// A key hint's outlined cap (`.kc`), at least this wide and tall.
  static const double keyCap = 18;

  /// The session's icon tile beside the chat title.
  static const double sessionTile = 22;

  /// The largest share of the chat header's title area its status pill
  /// takes, so a narrow header never overflows.
  static const double headerPillShare = .6;

  /// The context meter's bar in the chat header.
  static const double headerMeter = 40;

  /// The column a row's leading icon sits in (the crew ledger's rows).
  static const double leadSlot = 22;

  /// The longest title and status of a crew strip chip.
  static const double crewChipTitle = 180, crewChipMark = 140;

  /// Below this width a queued row's Send now button drops its label.
  static const double queuedRowLabels = 320;

  /// The widest a reference chip above the composer gets.
  static const double refChip = 280;

  /// The tallest the composer's @-mention list gets before it scrolls.
  static const double mentionList = 168;

  /// The approval bar keeps its request at least this wide beside the
  /// actions (`.ap-what{flex:1 1 280px}`); narrower, the actions wrap under.
  static const double approvalRequestMin = 280;

  /// The chat pane's wide grid: the gap around the transcript column, the
  /// side column's width, and the narrowest transcript the grid keeps (below
  /// it the side column drops).
  static const double chatGridGap = 40,
      chatSide = 252,
      chatGridMinContent = 160;

  /// The share of the grid's spare width that goes left of the transcript.
  static const double chatGridLeftShare = 2 / 3;

  /// The workbench's workspace beside a medium chat: a share of the width
  /// between a minimum and a maximum.
  static const workspaceMedium = (min: 240.0, max: 420.0, share: .4);

  /// The workbench's chat beside an expanded workspace.
  static const chatExpanded = (min: 444.0, max: 584.0, share: .44);

  /// The columns of a compacted message row: its number and its role.
  static const double historySeqColumn = 30, historyRoleColumn = 44;

  /// The verb column of a compacted episode's action row, and the widest its
  /// target chip gets (compact, and wider).
  static const double historyVerbColumn = 56;
  static const double historyChipCompact = 220, historyChip = 520;

  /// The context meter's bar (and its legend swatches), and how far the
  /// compaction cap's mark reaches past the bar above and below.
  static const double meterBar = 10, meterCapOvershoot = 3;

  /// The label column of a summary's facts in the Context pane.
  static const double factLabel = 76;

  /// A share row in the Context pane: its label, bar and figure.
  static const double shareLabel = 64, shareBar = 6, shareValue = 54;

  /// The widest a quiet note in the Context pane runs (`.cx-note`).
  static const double noteMaxWidth = 520;

  /// An activity row's verb column (compact, and wider), and the row's
  /// minimum height with a pointer.
  static const double activityVerbCompact = 40, activityVerb = 44;
  static const double activityRow = 20;

  /// An edit row narrower than this drops its +/− counts beside the name.
  static const double editRowCounts = 160;

  /// A diff's line-number gutter and its +/− column.
  static const double diffGutter = 44, diffSign = 16;

  /// A user message's bubble: a share of the transcript's width, up to a
  /// maximum.
  static const userBubble = (max: 560.0, share: .85);

  /// A markdown list's marker column.
  static const double listMarker = 16;

  /// The dot inside an interrupted status ring.
  static const double interruptedDot = 2.5;

  /// The outline's contents: a centred panel, or a bottom sheet taking this
  /// share of a compact screen.
  static const contents = (width: 440.0, height: 560.0, sheetShare: .7);
}

/// The Context pane's compaction timeline: a time column, then a rail with a
/// dot per event and a line down to the next.
abstract final class KitTimeline {
  /// The time column and the rail beside it.
  static const double timeColumn = 44, rail = 14;

  /// Where the line down to the next event starts, and the centre of an
  /// event's dot, from the top of its row.
  static const double lineTop = 20, dotCenter = 12;

  /// An applied compaction's dot; the others are `Sizes.dot`.
  static const double dotApplied = 10;

  /// The widest the before and after bars run, for an applied compaction and
  /// for the others.
  static const double barsApplied = 420, barsPending = 260;
}

/// Corners of the kit's marks beyond bb-ui's `Radii`.
abstract final class KitRadii {
  /// The running status mark: a square with softened corners, so it reads
  /// apart from the round done and idle dots.
  static const double runningMark = 2;
}

/// The small lift under a selected segment of a segmented toggle.
abstract final class KitShadow {
  static const liftOffset = Offset(0, 1);
  static const double liftBlur = 2;
}

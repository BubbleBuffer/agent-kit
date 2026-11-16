// The gallery's own layout values: the frames its specimens sit in and the
// sizes of its fake host panes. Shared design values come from bb_tokens;
// only what is particular to these specimen pages lives here.

/// The window widths the specimens show a component at.
abstract final class StageWidths {
  static const double desktop = 1000, medium = 700, phone = 390;
}

/// Frames that hold a specimen at a readable size.
abstract final class Specimen {
  /// The rail column's height, and the sliding rail's phone frame.
  static const double railHeight = 560;

  /// The crew ledger and usage cards, at the chat pane's side width.
  static const double sideCard = 252;

  /// The hidden-rail specimen.
  static const double hiddenRailWidth = 760, hiddenRailHeight = 120;

  /// The Context pane frames: wide, narrow and history widths, and the
  /// tall and short heights.
  static const double contextWide = 760,
      contextNarrow = 420,
      contextHistory = 680,
      contextTall = 760,
      contextShort = 640;

  /// The transcript list's frame.
  static const double transcriptHeight = 380;

  /// The workspace stages' heights.
  static const double workspaceLive = 460,
      workspaceCollapsed = 360,
      workspaceMaximised = 300,
      workspaceMedium = 340,
      workspaceCompact = 480,
      workspaceEmpty = 160;

  /// The status specimens: the name column, and a dot mark without and with
  /// a detail.
  static const double statusName = 96, statusMark = 170, statusDetail = 190;

  /// The live gallery's message column.
  static const double liveMessage = 480;

  /// The toolbar's width readout and width slider.
  static const double widthReadout = 64, widthSlider = 200;

  /// The width slider's track: its inset at each end and its thickness.
  static const double sliderInset = 8, sliderTrack = 4;
}

/// The fake host panes in the workspace specimens.
abstract final class FakePane {
  /// A fake load bar's thickness.
  static const double bar = 6;

  /// The fake diff's line-number gutter and sign column.
  static const double diffGutter = 44, diffSign = 16;
}

// The Lucide glyphs the chrome widgets draw, behind one small widget. bb_ui's
// Ico enum lacks most of them (panel-left-close, git-branch, ...), so they
// are named here; not exported from the barrel.

import 'package:bb_ui/bb_ui.dart';
import 'package:flutter/widgets.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../shared/kit_icon.dart';

const LucideGlyph glyphPanelLeftClose = (
  LucideIcons.panelLeftClose300,
  LucideIcons.panelLeftClose,
  LucideIcons.panelLeftClose500,
);
const LucideGlyph glyphPanelLeftOpen = (
  LucideIcons.panelLeftOpen300,
  LucideIcons.panelLeftOpen,
  LucideIcons.panelLeftOpen500,
);
const LucideGlyph glyphSquarePen = (
  LucideIcons.squarePen300,
  LucideIcons.squarePen,
  LucideIcons.squarePen500,
);
const LucideGlyph glyphSearch = (
  LucideIcons.search300,
  LucideIcons.search,
  LucideIcons.search500,
);
const LucideGlyph glyphSettings = (
  LucideIcons.settings300,
  LucideIcons.settings,
  LucideIcons.settings500,
);
const LucideGlyph glyphFolderPen = (
  LucideIcons.folderPen300,
  LucideIcons.folderPen,
  LucideIcons.folderPen500,
);
const LucideGlyph glyphChevronDown = (
  LucideIcons.chevronDown300,
  LucideIcons.chevronDown,
  LucideIcons.chevronDown500,
);
const LucideGlyph glyphGitBranch = (
  LucideIcons.gitBranch300,
  LucideIcons.gitBranch,
  LucideIcons.gitBranch500,
);
const LucideGlyph glyphLayoutPanelLeft = (
  LucideIcons.layoutPanelLeft300,
  LucideIcons.layoutPanelLeft,
  LucideIcons.layoutPanelLeft500,
);
const LucideGlyph glyphEllipsis = (
  LucideIcons.ellipsis300,
  LucideIcons.ellipsis,
  LucideIcons.ellipsis500,
);
const LucideGlyph glyphMessageSquare = (
  LucideIcons.messageSquare300,
  LucideIcons.messageSquare,
  LucideIcons.messageSquare500,
);
const LucideGlyph glyphMenu = (
  LucideIcons.menu300,
  LucideIcons.menu,
  LucideIcons.menu500,
);
const LucideGlyph glyphBot = (
  LucideIcons.bot300,
  LucideIcons.bot,
  LucideIcons.bot500,
);
const LucideGlyph glyphTerminal = (
  LucideIcons.terminal300,
  LucideIcons.terminal,
  LucideIcons.terminal500,
);

/// A Lucide [glyph] at [size], drawn at the kit's 1.5 px stroke.
class ChromeIcon extends StatelessWidget {
  const ChromeIcon(
    this.glyph, {
    super.key,
    required this.color,
    this.size = 16,
  });

  final LucideGlyph glyph;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) =>
      kitIcon(glyph, size: size, color: color);
}

const LucideGlyph glyphX = (LucideIcons.x300, LucideIcons.x, LucideIcons.x500);

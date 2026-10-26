# theme

`BbTheme` (the one `ThemeExtension` with the semantic roles), `BbThemeScope`
(installs it, plus `bb_ui`'s `AppTheme`) and `SizeClass` with
`SizeClassBuilder` (layout by container width). Widgets read roles from
`BbTheme.of(context)`, never raw colours or `MediaQuery.size`.

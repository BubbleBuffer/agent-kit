/// The text for a shortcut the kit binds to Ctrl and Cmd alike: "Ctrl+B" or
/// "Ctrl K" as written, "⌘B" or "⌘K" on macOS and iOS.
library;

import 'package:flutter/foundation.dart';

/// [ctrlHint] ("Ctrl+B", "Ctrl K") as the platform shows it.
String commandKeyHint(String ctrlHint) {
  final apple =
      defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.iOS;
  if (!apple || !ctrlHint.startsWith('Ctrl')) return ctrlHint;
  return '⌘${ctrlHint.substring(5)}';
}

/// Test helpers for code that renders the kit: loads the bundled fonts so
/// golden screenshots draw real text and real icons. Import from tests only
/// (uses dart:io).
library;

import 'dart:io';
import 'dart:isolate';

import 'package:flutter/services.dart';

const _families = <String, List<String>>{
  'Atkinson Hyperlegible Next': [
    'AtkinsonHyperlegibleNext[wght].ttf',
    'AtkinsonHyperlegibleNext-Italic[wght].ttf',
  ],
  'Fragment Mono': ['FragmentMono-Regular.ttf', 'FragmentMono-Italic.ttf'],
  'Bricolage Grotesque': ['BricolageGrotesque[opsz,wdth,wght].ttf'],
};

/// Loads Atkinson Hyperlegible Next, Fragment Mono and Bricolage Grotesque
/// from [directory] (relative to the test's working directory, the package
/// root), and the Lucide icon fonts of `lucide_icons_flutter`. The font files
/// live in the gallery's `assets/fonts`.
Future<void> loadKitFonts(String directory) async {
  for (final entry in _families.entries) {
    final loader = FontLoader(entry.key);
    for (final name in entry.value) {
      final bytes = File('$directory/$name').readAsBytesSync();
      loader.addFont(Future.value(ByteData.sublistView(bytes)));
    }
    await loader.load();
  }
  await _loadPackageFonts(
    'lucide_icons_flutter',
    'package:lucide_icons_flutter/lucide_icons.dart',
  );
}

/// `flutter test` does not load the fonts of dependencies, so icons would
/// draw as boxes. Reads the families and files from the package's pubspec and
/// registers them under `packages/<package>/<family>`, the name icons use.
Future<void> _loadPackageFonts(String package, String library) async {
  final uri = await Isolate.resolvePackageUri(Uri.parse(library));
  if (uri == null) return;
  final root = File.fromUri(uri).parent.parent.path;
  final loaders = <String, FontLoader>{};
  String? family;
  final familyLine = RegExp(r'^\s*-\s*family:\s*(\S+)');
  final assetLine = RegExp(r'^\s*-?\s*asset:\s*(\S+)');
  for (final line in File('$root/pubspec.yaml').readAsLinesSync()) {
    final f = familyLine.firstMatch(line);
    if (f != null) {
      family = f.group(1)!.replaceAll(RegExp('[\'"]'), '');
      continue;
    }
    final a = assetLine.firstMatch(line);
    if (a != null && family != null) {
      final name = 'packages/$package/$family';
      final path = a.group(1)!.replaceAll(RegExp('[\'"]'), '');
      loaders
          .putIfAbsent(name, () => FontLoader(name))
          .addFont(
            Future.value(
              ByteData.sublistView(File('$root/$path').readAsBytesSync()),
            ),
          );
    }
  }
  for (final loader in loaders.values) {
    await loader.load();
  }
}

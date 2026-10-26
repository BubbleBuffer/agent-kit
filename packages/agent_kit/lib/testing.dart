/// Test helpers for code that renders the kit: loads the bundled fonts so
/// golden screenshots draw real text and real icons. Import from tests only
/// (uses dart:io).
library;

import 'dart:convert';
import 'dart:io';

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
  await _loadPackageFonts('lucide_icons_flutter');
}

/// `flutter test` does not load the fonts of dependencies, so icons would
/// draw as boxes. Reads the families and files from the package's pubspec and
/// registers them under `packages/<package>/<family>`, the name icons use.
Future<void> _loadPackageFonts(String package) async {
  final root = _packageRoot(package);
  if (root == null) return;
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

/// The directory of [package], from the nearest `.dart_tool/package_config.json`
/// above the working directory (the workspace root's, for a workspace member).
String? _packageRoot(String package) {
  var dir = Directory.current.absolute;
  while (true) {
    final config = File('${dir.path}/.dart_tool/package_config.json');
    if (config.existsSync()) {
      final json = jsonDecode(config.readAsStringSync()) as Map<String, Object?>;
      for (final entry in json['packages']! as List<Object?>) {
        final p = entry! as Map<String, Object?>;
        if (p['name'] == package) {
          var root = config.uri.resolve(p['rootUri']! as String);
          if (!root.path.endsWith('/')) root = root.replace(path: '${root.path}/');
          return File.fromUri(root.resolve('pubspec.yaml')).parent.path;
        }
      }
      return null;
    }
    final parent = dir.parent;
    if (parent.path == dir.path) return null;
    dir = parent;
  }
}

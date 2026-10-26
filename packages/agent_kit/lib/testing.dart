/// Test helpers for code that renders the kit: loads the bundled fonts so
/// golden screenshots draw real text. Import from tests only (uses dart:io).
library;

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
/// root). The font files live in the gallery's `assets/fonts`.
Future<void> loadKitFonts(String directory) async {
  for (final entry in _families.entries) {
    final loader = FontLoader(entry.key);
    for (final name in entry.value) {
      final bytes = File('$directory/$name').readAsBytesSync();
      loader.addFont(Future.value(ByteData.sublistView(bytes)));
    }
    await loader.load();
  }
}

// Writes lib/src/colors.g.dart from tokens/agent-kit.json.
//
// The JSON is vendored from the agent-kit profile of the BubbleBuffer design
// repository; its `vendored` header names the repository, commit and command
// (see README.md). Plain Dart, no packages. Run it from this package:
//
//   dart tool/generate_colors.dart
//
// CI runs it and fails when the result differs from the committed file.

import 'dart:convert';
import 'dart:io';

/// Roles whose value is a CSS shadow list instead of a colour.
const _shadowRoles = {'shadow', 'shadowHover', 'shadowStack'};

final _hex = RegExp(r'^#([0-9A-Fa-f]{6})([0-9A-Fa-f]{2})?$');

void main() {
  final root = File.fromUri(Platform.script).parent.parent;
  final source = File('${root.path}/tokens/agent-kit.json');
  final target = File('${root.path}/lib/src/colors.g.dart');

  final json = jsonDecode(source.readAsStringSync()) as Map<String, Object?>;
  final vendored = json['vendored'] as Map<String, Object?>?;
  final light = _roles(json, 'light');
  final dark = _roles(json, 'dark');
  final names = light.keys.toList();
  if (names.join(',') != dark.keys.join(',')) {
    _fail('light and dark declare different roles.');
  }

  final from = vendored == null
      ? 'tokens/agent-kit.json'
      : '${vendored['repo']}@${vendored['commit']}';
  final out = StringBuffer()
    ..writeln('// GENERATED CODE, DO NOT EDIT.')
    ..writeln('//')
    ..writeln(
      '// Source: tokens/agent-kit.json, profile ${json['profile']} of $from.',
    )
    ..writeln(
      '// Regenerate: dart tool/generate_colors.dart (from packages/bb_tokens).',
    )
    ..writeln()
    ..writeln("import 'package:flutter/widgets.dart';")
    ..writeln()
    ..writeln(
      '/// The resolved light or dark palette of the agent-kit profile.',
    )
    ..writeln('///')
    ..writeln('/// Role names are the profile\'s. Shadow roles are lists of')
    ..writeln('/// [BoxShadow]; every other role is a [Color], translucent')
    ..writeln('/// where the profile says so.')
    ..writeln('@immutable')
    ..writeln('class ProfileColors {')
    ..writeln('  const ProfileColors({');
  for (final name in names) {
    out.writeln('    required this.$name,');
  }
  out.writeln('  });');
  out.writeln();
  for (final name in names) {
    out.writeln(
      _shadowRoles.contains(name)
          ? '  final List<BoxShadow> $name;'
          : '  final Color $name;',
    );
  }
  out.writeln();
  for (final entry in {'light': light, 'dark': dark}.entries) {
    out.writeln('  static const ${entry.key} = ProfileColors(');
    for (final name in names) {
      final value = entry.value[name]!;
      out.writeln(
        '    $name: ${_shadowRoles.contains(name) ? _shadows(name, value) : _color(name, value)},',
      );
    }
    out.writeln('  );');
    if (entry.key == 'light') out.writeln();
  }
  out.writeln('}');

  target.writeAsStringSync(out.toString());
  final format = Process.runSync(Platform.resolvedExecutable, [
    'format',
    target.path,
  ]);
  if (format.exitCode != 0) _fail('dart format failed:\n${format.stderr}');
  stdout.writeln('Wrote ${target.path} (${names.length} roles).');
}

Map<String, String> _roles(Map<String, Object?> json, String theme) {
  final block = json[theme];
  if (block is! Map<String, Object?>) _fail('"$theme" is missing.');
  return block.map((key, value) => MapEntry(key, value as String));
}

/// `#RRGGBB` or `#RRGGBBAA` as a Dart [Color] literal.
String _color(String role, String value) {
  final match = _hex.firstMatch(value);
  if (match == null) _fail('$role: "$value" is not a hex colour.');
  final alpha = (match.group(2) ?? 'FF').toUpperCase();
  return 'Color(0x$alpha${match.group(1)!.toUpperCase()})';
}

/// A CSS shadow list ("0 4px 12px #282A2F1A, 0 0 0 1px #282A2F0F") as a const
/// list of [BoxShadow].
String _shadows(String role, String value) {
  final parts = value.split(', ').map((shadow) {
    final words = shadow.trim().split(' ');
    final numbers = words
        .sublist(0, words.length - 1)
        .map((word) => num.parse(word.replaceAll('px', '')))
        .toList();
    if (numbers.length < 3 || numbers.length > 4) {
      _fail('$role: "$shadow" needs x, y, blur and an optional spread.');
    }
    final args = <String>['color: ${_color(role, words.last)}'];
    if (numbers[0] != 0 || numbers[1] != 0) {
      args.add('offset: Offset(${numbers[0]}, ${numbers[1]})');
    }
    if (numbers[2] != 0) args.add('blurRadius: ${numbers[2]}');
    if (numbers.length == 4 && numbers[3] != 0) {
      args.add('spreadRadius: ${numbers[3]}');
    }
    return 'BoxShadow(${args.join(', ')})';
  });
  return '[${parts.join(', ')}]';
}

Never _fail(String message) {
  stderr.writeln('generate_colors: $message');
  exit(1);
}

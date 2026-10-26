// Loads the bundled fonts for every test in this package, so widget tests and
// goldens draw real text. The font files live in the gallery's assets.

import 'dart:async';

import 'package:agent_kit/testing.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  await loadKitFonts('../../apps/gallery/assets/fonts');
  await testMain();
}

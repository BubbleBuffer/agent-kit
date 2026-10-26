// Loads the bundled fonts for every test in the gallery, so goldens draw real
// text.

import 'dart:async';

import 'package:agent_kit/testing.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  TestWidgetsFlutterBinding.ensureInitialized();
  await loadKitFonts('assets/fonts');
  await testMain();
}

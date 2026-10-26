// The token set keeps Scratch's values and the theme lookup works.

import 'package:bb_tokens/bb_tokens.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('light and dark palettes differ and say which they are', () {
    expect(AppColors.light.dark, isFalse);
    expect(AppColors.darkTheme.dark, isTrue);
    expect(AppColors.light.bgPrimary, isNot(AppColors.darkTheme.bgPrimary));
  });

  test('the form factor follows the window width', () {
    expect(FormFactor.forWidth(FormFactor.breakpoint - 1), FormFactor.mobile);
    expect(FormFactor.forWidth(FormFactor.breakpoint), FormFactor.desktop);
  });

  test('bundled font families keep Scratch names', () {
    expect(sansFamily, 'Atkinson Hyperlegible Next');
    expect(monoFamily, 'Fragment Mono');
    expect(displayFamily, 'Bricolage Grotesque');
  });

  testWidgets('context reads the nearest AppTheme', (tester) async {
    late TypeScale type;
    late AppColors colors;
    await tester.pumpWidget(
      AppTheme(
        colors: AppColors.darkTheme,
        formFactor: FormFactor.mobile,
        child: Builder(
          builder: (context) {
            type = context.type;
            colors = context.colors;
            return const SizedBox();
          },
        ),
      ),
    );
    expect(colors, same(AppColors.darkTheme));
    expect(type, same(TypeScale.mobile));
  });
}

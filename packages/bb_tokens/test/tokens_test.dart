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

  test('the generated palette backs the Scratch names', () {
    expect(AppColors.light.palette, same(ProfileColors.light));
    expect(AppColors.darkTheme.palette, same(ProfileColors.dark));
    expect(AppColors.light.bgPrimary, ProfileColors.light.surface);
    expect(AppColors.light.bgTertiary, ProfileColors.light.desk);
    expect(AppColors.darkTheme.okBg, ProfileColors.dark.constructive);
    expect(AppColors.light.seam, same(ProfileColors.light.shadow));
    // Translucent values stay translucent.
    expect(AppColors.darkTheme.okBg.a, lessThan(1));
    expect(ProfileColors.dark.statusNeedsYouLine.a, lessThan(1));
    expect(ProfileColors.light.paper, kTransparent);
  });

  test('space colours come from the palette', () {
    expect(spaceColor('moss', Brightness.light), const Color(0xFF697A6B));
    expect(spaceColor('moss', Brightness.dark), const Color(0xFF5F7062));
    expect(spaceColor('duvet', Brightness.dark), const Color(0xFF999DA6));
    expect(spaceColor('nope', Brightness.dark), isNull);
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

  test('kit tokens match the Scratch-skin theme.css', () {
    const layout = KitLayout.standard;
    expect(layout.sizeMedium, 600);
    expect(layout.sizeExpanded, 1000);
    expect(layout.fitComposer, 460);
    expect(layout.paneMinWidth, 200);
    expect(layout.paneMinHeight, 120);
    expect(layout.edgeTab, 28);
    expect(KitMotion.standard.breathe, const Duration(milliseconds: 2400));
    expect(KitInks.of(AppColors.light).danger, const Color(0xFFAD4B4B));
    expect(KitInks.of(AppColors.darkTheme).attention, const Color(0xFFF0D29C));
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

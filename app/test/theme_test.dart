// 主题回归测试。
//
// 这些断言守着一个**只在 debug 下才暴露、且 release 下会静默失效**的坑：
//
//   Flutter 的 `ThemeData.textTheme` 只带颜色、不带几何 —— 它的 fontSize 全是 null。
//   字号由 `Typography.englishLike / dense / tall` 提供，在 MaterialApp 里经
//   `ThemeData.localize()` 按语言脚本合并进来。
//
//   因此 `textTheme.apply(fontSizeFactor: 1.18)` 会命中
//   `painting/text_style.dart` 的断言 → debug 启动直接红屏；
//   而 release 下断言被裁掉，缩放**悄悄不生效**（字号压根没变大）。
//
// 曾经就是这么写的：ui-smoke 走的是 `flutter build web`（release），
// 一路绿灯；换成 `flutter run -d chrome`（debug）立刻红屏。
import 'package:cane_guardian/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// 复现 MaterialApp 内部做的事：按语言脚本把几何主题合并进 textTheme。
ThemeData _localize(ThemeData theme, ScriptCategory category) {
  return ThemeData.localize(theme, theme.typography.geometryThemeFor(category));
}

void main() {
  group('AppTheme 可构建性', () {
    test('light / dark 都能构建且不抛断言', () {
      expect(() => AppTheme.light(), returnsNormally);
      expect(() => AppTheme.dark(), returnsNormally);
    });
  });

  group('全局字号放大（几何主题，而非 textTheme）', () {
    test('原始 textTheme 确实不含 fontSize（这是 Flutter 的设计，不是 bug）', () {
      final raw = AppTheme.light().textTheme;
      expect(
        raw.bodyMedium?.fontSize,
        isNull,
        reason: '若这里不再是 null，说明 Flutter 改了行为，textScale 的实现方式需要重新评估',
      );
    });

    test('中文字形（dense）放大后 bodyMedium = 14 × 1.18', () {
      final localized = _localize(AppTheme.light(), ScriptCategory.dense);
      expect(
        localized.textTheme.bodyMedium?.fontSize,
        closeTo(14 * AppTheme.textScale, 0.01),
      );
    });

    test('拉丁字形（englishLike）同样被放大', () {
      final localized = _localize(AppTheme.light(), ScriptCategory.englishLike);
      expect(
        localized.textTheme.bodyMedium?.fontSize,
        closeTo(14 * AppTheme.textScale, 0.01),
      );
    });

    test('15 个样式在合并后全部拿到非空 fontSize', () {
      final t = _localize(AppTheme.light(), ScriptCategory.dense).textTheme;
      final styles = <String, TextStyle?>{
        'displayLarge': t.displayLarge,
        'displayMedium': t.displayMedium,
        'displaySmall': t.displaySmall,
        'headlineLarge': t.headlineLarge,
        'headlineMedium': t.headlineMedium,
        'headlineSmall': t.headlineSmall,
        'titleLarge': t.titleLarge,
        'titleMedium': t.titleMedium,
        'titleSmall': t.titleSmall,
        'bodyLarge': t.bodyLarge,
        'bodyMedium': t.bodyMedium,
        'bodySmall': t.bodySmall,
        'labelLarge': t.labelLarge,
        'labelMedium': t.labelMedium,
        'labelSmall': t.labelSmall,
      };
      final missing = styles.entries
          .where((e) => e.value?.fontSize == null)
          .map((e) => e.key)
          .toList();
      expect(missing, isEmpty, reason: '这些样式没拿到字号：$missing');
    });

    test('放大是等比放大的：每个样式都等于基准 × textScale', () {
      final plain = _localize(
        ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: AppTheme.seed,
            brightness: Brightness.light,
          ),
        ),
        ScriptCategory.dense,
      );
      final scaled = _localize(AppTheme.light(), ScriptCategory.dense);

      for (final pair in <List<TextStyle?>>[
        [plain.textTheme.bodyMedium, scaled.textTheme.bodyMedium],
        [plain.textTheme.titleLarge, scaled.textTheme.titleLarge],
        [plain.textTheme.labelSmall, scaled.textTheme.labelSmall],
      ]) {
        final baseSize = pair[0]!.fontSize!;
        expect(pair[1]!.fontSize, closeTo(baseSize * AppTheme.textScale, 0.01));
      }
    });
  });

  group('颜色与触控尺寸等其余主题项', () {
    test('textTheme 被上了色（主题的本职工作）', () {
      final scheme = ColorScheme.fromSeed(
        seedColor: AppTheme.seed,
        brightness: Brightness.light,
      );
      expect(AppTheme.light().textTheme.bodyMedium?.color, scheme.onSurface);
    });

    test('最小触控区域 ≥ Material 建议的 48dp', () {
      expect(AppTheme.minTouchSize, greaterThanOrEqualTo(48));
    });
  });
}

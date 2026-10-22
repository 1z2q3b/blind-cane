import 'package:flutter/foundation.dart' show defaultTargetPlatform;
import 'package:flutter/material.dart';

/// 全局主题。
///
/// 设计前提：**主要使用者是 40~70 岁的家属**，不是年轻重度用户。
/// 因此这里做的不是"好看"，而是"看得清、点得准"：
/// - 全站字号整体放大 18%（Material 基准 14 → 约 16.5），正文与按钮文字都明显更大；
/// - 最小点击区域 52dp，高于 Material 建议的 48dp；
/// - 主色选中低饱和的青蓝，避免大面积高饱和大红大绿造成视觉疲劳，
///   把"红"留给真正的紧急告警。
class AppTheme {
  const AppTheme._();

  /// 主色：稳定的青蓝，传达"可靠、不打扰"。
  static const Color seed = Color(0xFF0E7490);

  /// 紧急告警红。与主色拉开足够距离，保证在全屏告警页有压迫感。
  static const Color critical = Color(0xFFD32F2F);

  /// 警示橙。
  static const Color warning = Color(0xFFE08A00);

  /// 正常/在线绿。
  static const Color healthy = Color(0xFF2E7D32);

  static const double minTouchSize = 52;

  /// 全站文字放大倍数。
  ///
  /// ⚠️ 为什么放大的是 [Typography] 而不是 `ThemeData.textTheme`：
  ///
  /// Flutter 里 `ThemeData.textTheme` **只带颜色、不带几何**——它的 `fontSize`
  /// 全是 `null`。真正的字号由 `Typography` 的 `englishLike / dense / tall`
  /// 三套「几何主题」按语言脚本提供，在 `MaterialApp` 里经由
  /// `ThemeData.localize()` 合并进 textTheme（中文走 `dense`）。
  ///
  /// 所以对 textTheme 调 `apply(fontSizeFactor: ...)` 必然命中
  /// `painting/text_style.dart` 的断言
  /// `assert(fontSize != null || fontSizeFactor == 1.0)`：
  /// debug 下启动即红屏，release 下断言被裁掉、缩放**静默失效**（字号根本没变大）。
  ///
  /// 正确做法是把倍数施加到那三套几何主题上，这样 `localize()` 合并进来的
  /// 就是放大后的字号。
  static const double textScale = 1.18;

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.light,
    );
    return _base(scheme);
  }

  static ThemeData dark() {
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.dark,
    );
    return _base(scheme);
  }

  static ThemeData _base(ColorScheme scheme) {
    // 与 ThemeData 内部默认值保持一致（M3 用 material2021）
    final typography = Typography.material2021(
      platform: defaultTargetPlatform,
      colorScheme: scheme,
    );
    // 只缩放「几何」，三套都要覆盖：中文属 dense，英文属 englishLike，
    // 波斯语/印地语/泰语属 tall。漏掉任何一个，对应语言就享受不到放大。
    final scaledTypography = typography.copyWith(
      englishLike: typography.englishLike.apply(fontSizeFactor: textScale),
      dense: typography.dense.apply(fontSizeFactor: textScale),
      tall: typography.tall.apply(fontSizeFactor: textScale),
    );

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      typography: scaledTypography,
      // 默认字体族指向随包分发的思源黑体。
      // 不设置的后果：CanvasKit 渲染汉字时会去 fonts.gstatic.com 现拉字体，
      // 网络一抖动中文就全变豆腐块（页面看着像"没有内容"）。
      fontFamily: 'NotoSansSC',
    );

    return base.copyWith(
      scaffoldBackgroundColor: scheme.surface,
      // 这里**只上颜色**。字号缩放必须留给上面的 typography，
      // 在这里动 fontSize 会重新踩回那个断言（详见 textScale 的注释）。
      textTheme: base.textTheme.apply(
        bodyColor: scheme.onSurface,
        displayColor: scheme.onSurface,
      ),
      appBarTheme: AppBarTheme(
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 1,
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        titleTextStyle: base.textTheme.titleLarge?.copyWith(
          fontSize: 21,
          fontWeight: FontWeight.w600,
          color: scheme.onSurface,
        ),
      ),
      // ⚠️ 这里**不能**用 Size.fromHeight(minTouchSize)：
      // Size.fromHeight 的宽度是 double.infinity，按钮一旦成为 Row /
      // Wrap 里的非弹性子节点，就会被布局成无限宽——把同排的 Expanded
      // 挤成 0 宽（文字一字一行），按钮自己也画不出来（无限大的渲染盒
      // 什么都画不出）。这就是「添加家人」页位置卡片竖排、手动定位按钮
      // 消失的根因。宽度留给 0，需要全宽的 CTA 在调用处包
      // SizedBox(width: double.infinity)。
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(0, minTouchSize),
          textStyle: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          // 同 filledButtonTheme：宽度不能给 ∞（Size.fromHeight 的坑）
          minimumSize: const Size(0, minTouchSize),
          textStyle: const TextStyle(fontSize: 17, fontWeight: FontWeight.w500),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(minTouchSize, minTouchSize),
          textStyle: const TextStyle(fontSize: 16),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: scheme.primary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: critical, width: 1.5),
        ),
        labelStyle: const TextStyle(fontSize: 16),
        hintStyle: TextStyle(fontSize: 16, color: scheme.onSurfaceVariant),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        margin: EdgeInsets.zero,
        color: scheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      listTileTheme: const ListTileThemeData(
        minVerticalPadding: 14,
        titleTextStyle: TextStyle(fontSize: 17, fontWeight: FontWeight.w500),
        subtitleTextStyle: TextStyle(fontSize: 15),
      ),
      chipTheme: base.chipTheme.copyWith(
        labelStyle: const TextStyle(fontSize: 15),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 68,
        elevation: 2,
        labelTextStyle: WidgetStateProperty.all(
          const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
        ),
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        contentTextStyle: TextStyle(fontSize: 16),
      ),
      dividerTheme: const DividerThemeData(thickness: 0.6, space: 1),
    );
  }

  /// 告警级别配色，列表与全屏页共用。
  static Color severityColor(int severity, ColorScheme scheme) {
    return switch (severity) {
      1 => critical,
      2 => warning,
      _ => scheme.primary,
    };
  }
}

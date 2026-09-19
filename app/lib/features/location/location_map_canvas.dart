import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../state/location_state.dart';

/// 位置地图画布。
///
/// 为什么是自绘而不是接高德地图：提示词里高德 Web Key 是可选配置项，
/// 没有 Key 时必须能给家属一个「至少能看出老人在哪、走了多远」的视图。
/// 安卓端接高德 SDK 的版本在二期，一期用等距圆柱投影把经纬度画到网格上，
/// 位置精度与真实地图完全一致（只是没有底图元素）。
///
/// 入参刻意用裸的 lng/lat/accuracyM 而不是 LatestLocation 或 AlertRecord：
/// 调用方既有实时位置也有告警坐标，画布只关心这三个数，
/// 定义成具体类型会逼着调用方去构造一个语义上并不存在的对象。
class LocationMapCanvas extends StatelessWidget {
  const LocationMapCanvas({
    super.key,
    required this.lng,
    required this.lat,
    this.accuracyM,
    this.trail = const [],
    this.metersPerPixel = 0.6,
    this.showGrid = true,
    this.showCoordinates = true,
  });

  final double? lng;
  final double? lat;
  final double? accuracyM;
  final List<TrailPoint> trail;

  /// 每像素代表多少米。数值越小越「放大」。
  final double metersPerPixel;
  final bool showGrid;

  /// 是否在标记下方打印坐标。缩略图里通常不需要。
  final bool showCoordinates;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return CustomPaint(
      painter: _LocationPainter(
        lng: lng,
        lat: lat,
        accuracyM: accuracyM,
        trail: trail,
        metersPerPixel: metersPerPixel,
        showGrid: showGrid,
        showCoordinates: showCoordinates,
        gridColor: theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
        trailColor: theme.colorScheme.primary,
        markerColor: theme.colorScheme.error,
        accuracyColor: theme.colorScheme.primary.withValues(alpha: 0.18),
        labelStyle: TextStyle(
          fontSize: 11,
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      child: const SizedBox.expand(),
    );
  }
}

class _LocationPainter extends CustomPainter {
  _LocationPainter({
    required this.lng,
    required this.lat,
    required this.accuracyM,
    required this.trail,
    required this.metersPerPixel,
    required this.showGrid,
    required this.showCoordinates,
    required this.gridColor,
    required this.trailColor,
    required this.markerColor,
    required this.accuracyColor,
    required this.labelStyle,
  });

  final double? lng;
  final double? lat;
  final double? accuracyM;
  final List<TrailPoint> trail;
  final double metersPerPixel;
  final bool showGrid;
  final bool showCoordinates;
  final Color gridColor;
  final Color trailColor;
  final Color markerColor;
  final Color accuracyColor;
  final TextStyle labelStyle;

  static const double _metersPerDegreeLat = 111320;

  @override
  void paint(Canvas canvas, Size size) {
    final centerLng = lng;
    final centerLat = lat;
    if (centerLng == null || centerLat == null) {
      return;
    }
    if (showGrid) {
      _paintGrid(canvas, size);
    }
    _paintScaleBar(canvas, size);
    _paintTrail(canvas, size, centerLng, centerLat);
    _paintAccuracy(canvas, size);
    _paintMarker(canvas, size, centerLng, centerLat);
  }

  /// 以中心点为屏幕中心，把经纬度换算成画布坐标。
  ///
  /// 用等距圆柱投影：小范围内与真实距离的误差可以忽略，
  /// 但必须按 cos(纬度) 修正经度方向，否则在郑州（北纬 34°）
  /// 画面会被横向拉伸约 20%。
  Offset _project(double pointLng, double pointLat, Size size,
      double centerLng, double centerLat) {
    final metersPerDegreeLng =
        _metersPerDegreeLat * math.cos(centerLat * math.pi / 180);
    final dx = (pointLng - centerLng) * metersPerDegreeLng / metersPerPixel;
    final dy = -(pointLat - centerLat) * _metersPerDegreeLat / metersPerPixel;
    return Offset(size.width / 2 + dx, size.height / 2 + dy);
  }

  void _paintGrid(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    const step = 44.0;
    for (double x = 0; x <= size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y <= size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  void _paintTrail(
      Canvas canvas, Size size, double centerLng, double centerLat) {
    if (trail.length < 2) {
      return;
    }
    final path = Path();
    for (var i = 0; i < trail.length; i++) {
      final point =
          _project(trail[i].lng, trail[i].lat, size, centerLng, centerLat);
      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = trailColor.withValues(alpha: 0.55)
        ..strokeWidth = 3
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
    // 轨迹起点标记：家属最关心「从哪里出发」
    final start =
        _project(trail.first.lng, trail.first.lat, size, centerLng, centerLat);
    canvas.drawCircle(start, 5, Paint()..color = trailColor.withValues(alpha: 0.9));
  }

  void _paintAccuracy(Canvas canvas, Size size) {
    final accuracy = accuracyM ?? 0;
    if (accuracy <= 0) {
      return;
    }
    final radius = accuracy / metersPerPixel;
    // 精度圈超过半个屏幕时画出来只会是一整片色块，没有信息量
    if (radius > size.shortestSide) {
      return;
    }
    canvas.drawCircle(
      Offset(size.width / 2, size.height / 2),
      radius,
      Paint()..color = accuracyColor,
    );
  }

  void _paintMarker(
      Canvas canvas, Size size, double centerLng, double centerLat) {
    final center = Offset(size.width / 2, size.height / 2);

    // 外圈光晕：让标记在网格背景上更醒目
    canvas.drawCircle(center, 18, Paint()..color = markerColor.withValues(alpha: 0.18));
    canvas.drawCircle(center, 9, Paint()..color = markerColor);
    canvas.drawCircle(center, 3.5, Paint()..color = Colors.white);

    if (!showCoordinates) {
      return;
    }
    final label = TextPainter(
      text: TextSpan(
        text: '${centerLat.toStringAsFixed(5)}, ${centerLng.toStringAsFixed(5)}',
        style: labelStyle,
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    label.paint(canvas, Offset(center.dx - label.width / 2, center.dy + 22));
  }

  /// 左下角比例尺。没有底图时，这条线是家属判断「距离多远」的唯一依据。
  void _paintScaleBar(Canvas canvas, Size size) {
    const targetPx = 90.0;
    final meters = targetPx * metersPerPixel;
    final niceMeters = _niceRound(meters);
    final barPx = niceMeters / metersPerPixel;

    const left = 14.0;
    final bottom = size.height - 16;
    final paint = Paint()
      ..color = labelStyle.color ?? Colors.grey
      ..strokeWidth = 2;

    canvas.drawLine(Offset(left, bottom), Offset(left + barPx, bottom), paint);
    canvas.drawLine(Offset(left, bottom - 5), Offset(left, bottom + 5), paint);
    canvas.drawLine(
        Offset(left + barPx, bottom - 5), Offset(left + barPx, bottom + 5), paint);

    final text = TextPainter(
      text: TextSpan(
        text: niceMeters >= 1000
            ? '${(niceMeters / 1000).toStringAsFixed(1)} km'
            : '${niceMeters.toStringAsFixed(0)} m',
        style: labelStyle,
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    text.paint(canvas, Offset(left, bottom - 22));
  }

  /// 把任意米数取整成 1/2/5 × 10^n，比例尺上的数字才不会出现 137m 这种读数。
  double _niceRound(double value) {
    if (value <= 0) {
      return 1;
    }
    final exponent = (math.log(value) / math.ln10).floor();
    final magnitude = math.pow(10, exponent).toDouble();
    final normalized = value / magnitude;
    final nice = normalized < 1.5
        ? 1.0
        : normalized < 3.5
            ? 2.0
            : normalized < 7.5
                ? 5.0
                : 10.0;
    return nice * magnitude;
  }

  @override
  bool shouldRepaint(covariant _LocationPainter oldDelegate) {
    return oldDelegate.lng != lng ||
        oldDelegate.lat != lat ||
        oldDelegate.accuracyM != accuracyM ||
        oldDelegate.trail != trail ||
        oldDelegate.metersPerPixel != metersPerPixel ||
        oldDelegate.showGrid != showGrid;
  }
}

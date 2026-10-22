import 'package:flutter/material.dart';

import '../../features/location/location_map_canvas.dart';
import '../../state/location_state.dart';

/// Web 端的地图实现：自绘网格画布。
///
/// <p>为什么 Web 不接高德：高德 Web 能力走的是 **JS API**（需要 Web 端 Key +
/// 安全密钥 + 域名白名单），和移动端 SDK 是两套完全不同的接入方式。
/// 用 `HtmlElementView` 嵌 iframe 也能做，但会带来平台视图层级、手势冲突、
/// 与 Flutter 主题不一致等一堆问题，收益不足以支撑。
///
/// <p>自绘画布的价值在于：**坐标投影是真的**。它把经纬度按等距圆柱投影画到网格上，
/// 位置、精度圈、轨迹走向与真实地图完全一致，只是没有底图元素。
/// 演示时家属依然能看出"老人在往东走 300 米"。
class SmartMapView extends StatelessWidget {
  const SmartMapView({
    super.key,
    required this.lng,
    required this.lat,
    this.accuracyM,
    this.trail = const [],
    this.metersPerPixel = 0.6,
    this.showCoordinates = true,
    this.zoom = 17,
  });

  final double? lng;
  final double? lat;
  final double? accuracyM;
  final List<TrailPoint> trail;
  final double metersPerPixel;
  final bool showCoordinates;

  /// 缩放级别。仅原生地图使用，Web 画布用 [metersPerPixel] 表达缩放，
  /// 这里保留参数是为了让两个实现签名一致。
  final double zoom;

  @override
  Widget build(BuildContext context) {
    return LocationMapCanvas(
      lng: lng,
      lat: lat,
      accuracyM: accuracyM,
      trail: trail,
      metersPerPixel: metersPerPixel,
      showCoordinates: showCoordinates,
    );
  }
}

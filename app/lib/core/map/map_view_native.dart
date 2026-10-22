import 'dart:math' as math;

import 'package:amap_flutter_base/amap_flutter_base.dart';
import 'package:amap_flutter_map/amap_flutter_map.dart';
import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../features/location/location_map_canvas.dart';
import '../../state/location_state.dart';
import '../config/app_config.dart';

/// Android / iOS 的地图实现：高德原生地图。
///
/// <p><b>没有 Key 时的行为很关键</b>：直接渲染 AMapWidget 会得到一片灰底
/// 甚至原生侧崩溃，演示时非常难堪。所以这里先判 [AppConfig.hasAmapKey]，
/// 没配就自动退回自绘画布——坐标、轨迹、精度圈逻辑完全一致，
/// 只是没有底图。这样「有没有 Key」只影响观感，不影响功能可用性。
///
/// <p>关于隐私合规（高德 SDK 3.0 起强制要求）：`AMapPrivacyStatement` 的三个
/// 布尔值必须为 true，否则地图不会加载。生产环境必须改成「用户真实同意后才置 true」，
/// 当前项目没有隐私弹窗流程，演示阶段先声明已同意。
class SmartMapView extends StatefulWidget {
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

  /// Web 画布用；原生地图用 [zoom]。
  final double metersPerPixel;
  final bool showCoordinates;
  final double zoom;

  @override
  State<SmartMapView> createState() => _SmartMapViewState();
}

class _SmartMapViewState extends State<SmartMapView> {
  AMapController? _controller;

  @override
  void didUpdateWidget(covariant SmartMapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final lng = widget.lng;
    final lat = widget.lat;
    // 位置变了就把镜头跟过去。不跟的话地图会停在第一次渲染的位置，
    // 而家属的预期是"地图始终锁着老人"。
    if (lng != null && lat != null && (oldWidget.lng != lng || oldWidget.lat != lat)) {
      _controller?.moveCamera(CameraUpdate.newLatLng(LatLng(lat, lng)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final lng = widget.lng;
    final lat = widget.lat;

    // 没有坐标 或 没有配 Key → 降级画布
    if (lng == null || lat == null || !AppConfig.hasAmapKey) {
      return LocationMapCanvas(
        lng: lng,
        lat: lat,
        accuracyM: widget.accuracyM,
        trail: widget.trail,
        metersPerPixel: widget.metersPerPixel,
        showCoordinates: widget.showCoordinates,
      );
    }

    final center = LatLng(lat, lng);

    return AMapWidget(
      apiKey: AMapApiKey(
        androidKey: AppConfig.amapAndroidKey.isEmpty ? null : AppConfig.amapAndroidKey,
        iosKey: AppConfig.amapIosKey.isEmpty ? null : AppConfig.amapIosKey,
      ),
      privacyStatement: const AMapPrivacyStatement(
        hasContains: true,
        hasShow: true,
        hasAgree: true,
      ),
      initialCameraPosition: CameraPosition(target: center, zoom: widget.zoom),
      // 关闭倾斜/旋转手势：家属端是"看位置"，误触把地图转歪了会看不清方向
      rotateGesturesEnabled: false,
      tiltGesturesEnabled: false,
      compassEnabled: true,
      scaleEnabled: true,
      markers: {
        Marker(
          position: center,
          // 锚点设在底部中心，让图钉尖端对准真实坐标
          anchor: const Offset(0.5, 1),
          infoWindowEnable: false,
        ),
      },
      polylines: widget.trail.length < 2
          ? const {}
          : {
              Polyline(
                points: [
                  for (final point in widget.trail) LatLng(point.lat, point.lng),
                ],
                width: 6,
                color: AppTheme.seed,
              ),
            },
      // 高德 Flutter 插件没有 circle 覆盖物，精度圈用 32 边形近似
      polygons: _accuracyPolygon(center, widget.accuracyM),
      onMapCreated: (controller) => _controller = controller,
    );
  }

  Set<Polygon> _accuracyPolygon(LatLng center, double? accuracyM) {
    if (accuracyM == null || accuracyM <= 0) {
      return const {};
    }
    const segments = 32;
    // 纬度方向 1 度 ≈ 110540 米；经度方向随纬度收缩
    final dLat = accuracyM / 110540.0;
    final dLng = accuracyM /
        (111320.0 * math.cos(center.latitude * math.pi / 180.0));
    final points = <LatLng>[
      for (var i = 0; i < segments; i++)
        LatLng(
          center.latitude + dLat * math.sin(2 * math.pi * i / segments),
          center.longitude + dLng * math.cos(2 * math.pi * i / segments),
        ),
    ];
    return {
      Polygon(
        points: points,
        strokeWidth: 2,
        strokeColor: AppTheme.seed,
        fillColor: AppTheme.seed.withValues(alpha: 0.12),
      ),
    };
  }
}

/// 地图视图的统一入口。
///
/// <p>为什么需要这层间接：
/// 高德官方的 `amap_flutter_map` 只支持 Android/iOS（它是对原生 SDK 的封装），
/// 而本项目同时要在 **Flutter Web** 上跑演示。如果在页面里直接 import 高德包，
/// Web 构建会编译失败或运行时报错。
///
/// <p>用条件导入按平台分流：
/// <ul>
///   <li>Web（`dart.library.io` 不可用）→ [map_view_web.dart]，走自绘网格画布；</li>
///   <li>Android/iOS（`dart.library.io` 可用）→ [map_view_native.dart]，走高德原生地图。</li>
/// </ul>
///
/// <p>两个实现对外暴露**完全相同的 API**（`SmartMapView` 的构造参数与语义），
/// 所以业务页面只依赖这个文件，不需要写任何 `if (kIsWeb)` 分支。
library;

export 'map_view_web.dart' if (dart.library.io) 'map_view_native.dart';

/// 应用级配置。
///
/// 后端地址通过编译期变量注入，不写死在代码里：
/// ```
/// flutter run --dart-define=API_BASE_URL=http://192.168.1.10:8001
/// ```
/// 默认值是本机回环地址，方便开发时直接跑起来。
///
/// 为什么后端端口是 8001 而不是 8080：本机 8080 常被其它服务占用，
/// 故后端固定监听 8001，默认值与之保持一致。
///
/// 为什么不用 `.env` 文件：Flutter 没有运行时读取明文配置的标准做法，
/// 而 `--dart-define` 是编译期常量，既可以按环境打包，也不会把地址
/// 泄漏进可被反编译的字符串常量池里的「可变」位置。
class AppConfig {
  const AppConfig._();

  /// 后端 REST 根地址。
  static const String apiBaseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://127.0.0.1:8001',
  );

  /// STOMP 端点地址。默认由 [apiBaseUrl] 推导（http→ws、https→wss）。
  static String get wsUrl {
    const override = String.fromEnvironment('WS_URL');
    if (override.isNotEmpty) {
      return override;
    }
    if (apiBaseUrl.startsWith('https://')) {
      return '${apiBaseUrl.replaceFirst('https://', 'wss://')}/ws';
    }
    return '${apiBaseUrl.replaceFirst('http://', 'ws://')}/ws';
  }

  /// 统一的 REST 前缀。
  static const String apiPrefix = '/api/v1';

  /// 构建标识：用来区分「浏览器里跑的到底是哪一次构建」。
  ///
  /// 加这个字段的缘由很具体：Flutter Web 的 Service Worker 会把整包缓存住，
  /// 代码改了、服务也重启了，用户刷新页面拿到的可能还是旧的 main.dart.js，
  /// 于是「我明明改好了，用户却说没生效」反复出现，排查成本极高。
  /// 把构建号显式印在登录页和「我的」页，用户扫一眼就能对比
  /// 手上跑的构建和交付时说好的构建是不是同一个。
  ///
  /// 构建时注入（推荐写进构建脚本，别手敲）：
  /// ```
  /// flutter build web --dart-define=BUILD_STAMP=20261021-2000
  /// flutter run -d chrome --dart-define=BUILD_STAMP=20261021-2000
  /// ```
  /// 不注入时显示 `dev`，意思是「本地直接跑的未打包构建」。
  static const String buildStamp =
      String.fromEnvironment('BUILD_STAMP', defaultValue: 'dev');

  /// 网络超时。
  static const Duration connectTimeout = Duration(seconds: 10);
  static const Duration receiveTimeout = Duration(seconds: 15);

  /// 短信验证码倒计时（与后端 60 秒发送间隔保持一致）。
  static const int smsCountdownSeconds = 60;

  /// 演示模式：为 true 时设置页会出现「设备模拟器」入口。
  ///
  /// 与后端 `blindcane.simulator.enabled` 是同一个开关的两端：
  /// 后端关掉模拟器后，Mock 接口会返回 404，入口留着也点不通，
  /// 所以这里再控一次只是为了避免家属误触。
  static const bool demoMode = bool.fromEnvironment('DEMO_MODE', defaultValue: true);

  /// 紧急联系电话，全屏告警页的「一键拨号」用它兜底。
  ///
  /// 只有在被监护人档案没填「随身电话」时才会打到这个号码；
  /// 填了的话优先拨本人（见 AlertDetailPage / FullScreenAlertPage）。
  static const String emergencyNumber = '120';

  /// 高德地图 Key（**仅 Android/iOS 需要**，Web 端不用、也不支持）。
  ///
  /// 申请入口：https://lbs.amap.com/ → 应用管理 → 创建应用 → 添加 Key，
  /// 平台选「Android」或「iOS」。Android 的 Key 必须与打包签名 SHA1 + 包名绑定。
  ///
  /// 通过编译期参数传入，不要把真实 Key 提交进仓库：
  /// ```
  /// flutter run --dart-define=AMAP_ANDROID_KEY=你的key
  /// flutter build apk --dart-define=AMAP_ANDROID_KEY=你的key
  /// ```
  ///
  /// 为空时移动端**不会崩**：SmartMapView 会自动退回自绘网格画布，
  /// 坐标与轨迹逻辑完全一致，只是没有底图。
  static const String amapAndroidKey =
      String.fromEnvironment('AMAP_ANDROID_KEY', defaultValue: '');

  static const String amapIosKey =
      String.fromEnvironment('AMAP_IOS_KEY', defaultValue: '');

  /// 是否已配置高德 Key。移动端据此决定用真地图还是降级画布。
  static bool get hasAmapKey => amapAndroidKey.isNotEmpty || amapIosKey.isNotEmpty;
}

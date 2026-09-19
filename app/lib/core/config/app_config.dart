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
  static const String emergencyNumber = '120';
}

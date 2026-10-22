// 自定义 Flutter Web 启动引导。
//
// 为什么要有这个文件（值得留档，因为踩过坑）：
// Flutter 默认会在启动时注册 Service Worker，把整包（main.dart.js 等）缓存下来。
// 本项目的使用场景是「本地开发、反复改代码、改完立刻验证」，
// 一旦 SW 缓存了旧包，就会出现：代码改了、服务重启了、浏览器也刷新了，
// 界面上却还是旧行为——因为 SW 从缓存里直接返回了旧 main.dart.js。
// 这类"改了不生效"极难排查，已经浪费过大量时间。
//
// 这里做两件事，把这类问题一次性根除：
//   1. 启动前注销所有已注册的 Service Worker（清理历史遗留缓存）；
//   2. 不传 serviceWorkerSettings，loader 就不会注册新的 SW。
// 代价是没有离线访问能力——本项目是联机演示/开发，不需要离线。
//
// 注意：两个 {{ }} 占位符必须保留，构建时会被 Flutter 工具替换成
// 真正的 loader 脚本与构建配置，不要改成别的写法。

{{flutter_js}}
{{flutter_build_config}}

// 1) 清理历史遗留的 Service Worker 注册（旧包缓存住的元凶）。
//    已经在跑的 SW 会拦截请求并从缓存返回旧文件，必须先注销掉。
if ('serviceWorker' in navigator) {
  navigator.serviceWorker.getRegistrations().then(function (registrations) {
    registrations.forEach(function (registration) {
      registration.unregister().then(function (unregistered) {
        if (unregistered) {
          console.log('[bootstrap] 已注销遗留 Service Worker，后续刷新将始终拉取最新构建');
        }
      });
    });
  });
}

// 2) 正常加载应用。刻意不传 serviceWorkerSettings——loader 收到 falsy
//    时直接跳过注册（见 flutter.js: loadServiceWorker 的首行判断）。
_flutter.loader.load();

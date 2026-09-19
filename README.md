# 智能导盲杖 · 家属监护端（阶段一 MVP）

家属端（**明眼人**用的那端）的定位是「接收端 + 监护窗口」：看得见老人的实时位置和设备状态，
第一时间收到 SOS / 跌倒 / 离线 / 低电量告警并能立刻行动。

盲人本人只操作导盲杖本体，**不碰这个 App**，所以这里不需要蓝牙、TTS/ASR、后台保活。
导盲杖通过 4G Cat.1 / eSIM 直连云端上报，家属端只负责消费云端数据。

```
┌──────────┐   HTTP    ┌─────────────────┐   STOMP/WS   ┌──────────────────┐
│ 导盲杖    │ ────────▶ │  backend        │ ───────────▶ │ app（家属端）     │
│ (模拟器)  │  上报     │  Spring Boot    │  三主题推送   │ Flutter Web/移动  │
└──────────┘           │  MySQL + Redis  │              └──────────────────┘
                       └─────────────────┘
```

---

## 一、目录结构

```
cane/
├── backend/                        Spring Boot 3.3.4 + Java 17
│   ├── build.sh                    本机 mvn 脚本损坏时的 Maven 启动器
│   ├── docker-compose.yml          MySQL8 + Redis7（备选方案，默认用本机实例）
│   ├── local-secrets.yml           本地密钥（不进版本库）
│   ├── src/main/java/com/blindcane/guardian/
│   │   ├── common/                 统一响应 / 错误码 / 异常处理 / 加密工具
│   │   ├── framework/              security(JWT) · websocket(STOMP) · config
│   │   └── modules/                auth · user · ward · device · location · alert · push · simulator
│   ├── src/main/resources/
│   │   ├── application.yml         主配置（含 Mock 降级开关、模拟器参数）
│   │   ├── application-dev.yml     本地数据源（开发默认 profile）
│   │   └── db/migration/V1__init.sql   Flyway 初始化（9 张表 + 空间索引）
│   └── tools/                      验证与运维脚本
│       ├── verify-s3.sh            位置 + 告警 + WebSocket 十项端到端验证
│       ├── verify-s4.sh            设备模拟器验证
│       ├── demo-reset.js           演示前复位数据（清限流 / 复位设备 / 处置遗留告警）
│       ├── stomp-watch.js          STOMP 订阅观察工具（联调排障主力）
│       ├── json-get.js             从 JSON 里取字段（bash 里替代 jq）
│       └── geo-delta.js            两点间距离计算
├── app/                            Flutter 3.48 家属端
│   ├── lib/
│   │   ├── core/                   config · network(Dio+拦截器) · ws(STOMP) · storage · router · theme
│   │   ├── models/                 与后端 VO 一一对应的数据模型
│   │   ├── state/                  Riverpod 状态层（含 ws_bridge 推送桥）
│   │   └── features/               auth · home · ward · location · alert · settings · shared
│   ├── test/
│   │   ├── models_test.dart        模型层单元测试
│   │   └── link/backend_link_test.dart  直连后端的契约回归（默认跳过）
│   └── tools/
│       ├── ui-smoke.js             无头 Chrome 真实渲染冒烟（含 SOS 全屏验收）
│       ├── verify-s5.sh            跑上面那个 Dart 契约回归
│       ├── ws-diagnose.js          WebSocket 链路诊断（状态 + 语义树 dump）
│       └── ws-browser-probe.js     浏览器内手写 STOMP 探针（分离服务端/客户端故障）
└── demo.sh                         一键演示剧本
```

---

## 二、环境要求

| 组件 | 版本 | 说明 |
|---|---|---|
| JDK | 17+ | 实测 Java 21 可跑，源码级别锁 17 |
| Maven | 3.8+ | **本机 `mvn` 脚本已损坏**，一律走 `backend/build.sh` |
| MySQL | 8.0 | 必须 8.0+：用到 `POINT NOT NULL SRID 4326` + 空间索引 |
| Redis | 7.x | 最新位置热数据 + 令牌黑名单 + 各类去抖标记 |
| Flutter | 3.x | 实测 3.48（master），`D:\Flutter\flutter` |

> ⚠️ **本机 MySQL 的 SRID 4326 轴序是「纬度在前」**，写 `POINT(lat lng)` 而不是 `POINT(lng lat)`，
> 否则报 `ERROR 3617`。这一条踩过一次，改了半小时。

---

## 三、启动步骤

### 1. 基础设施

默认用本机实例（MySQL `3306` + Redis `6379`）：

```bash
# 确认两个服务在跑
mysql -uroot -p -e "SELECT VERSION();"
/d/redis/redis-cli ping          # 期望 PONG
```

也可以改用 Docker（端口会映射到 `3307/6380`，记得同步改 `application-dev.yml`）：

```bash
cd backend && docker compose up -d
```

### 2. 后端

```bash
cd backend
bash build.sh spring-boot:run
```

- 表结构由 Flyway 自动建立（9 张表）
- 启动后接口根路径 `http://127.0.0.1:8001`
- 接口文档 `http://127.0.0.1:8001/swagger-ui.html`

> **端口说明：后端固定用 `8001`。** 本机 `8080` 常被其它服务占用（本项目就撞过一次），
> 故在 `application.yml` 里把 `server.port` 定为 8001，前端 `AppConfig` 的默认值、
> 各验证脚本与 `demo.sh` 已全部对齐。需要临时换端口时**用启动参数覆盖**，不要改配置文件：
>
> ```bash
> bash build.sh spring-boot:run -Dspring-boot.run.arguments=--server.port=8002
> # 前端/脚本同步：API_BASE_URL=http://127.0.0.1:8002（脚本支持 PORT=8002 bash xxx.sh）
> ```

> `mvn` 报 `ClassNotFoundException: plexus-classworlds.launcher` 时不要折腾环境变量，
> `build.sh` 就是为这个场景写的：它用 `java -classpath boot/plexus-classworlds-*.jar` 直启 Maven。

### 3. 家属端

> **Flutter SDK 位置：`D:\Flutter\flutter`**（实测 `3.48.0-1.0.pre-805` · channel master · Dart 3.14.0）。
> 它的 `bin` 目录**已经在用户 PATH 里**（`D:\Flutter\flutter\bin`），新开的终端可直接用 `flutter`。
> 若在**旧终端**里敲 `flutter` 提示找不到，那是终端没重开、环境变量还是启动时的快照，
> 关掉重开即可；临时救急也行：
>
> ```bash
> export PATH="/d/Flutter/flutter/bin:$PATH"
> ```

> ⚠️ **别裸用 `dart` 命令。** 系统 PATH 里还有一套独立 Dart SDK
> `D:\dark\Dart\dart-sdk\bin`（**3.13.4 stable**）。Windows 解析 PATH 的顺序是
> **系统 PATH 优先于用户 PATH**，所以裸敲 `dart` 命中的是 3.13.4，而不是 Flutter 自带的 3.14.0。
> 版本对不上会报「Flutter SDK is not available」或 pubspec 的 SDK 约束不满足。
> **本项目一律走 `flutter pub get` / `flutter analyze` / `flutter test`**，
> 万不得已要直接调 dart，写全路径 `D:\Flutter\flutter\bin\dart.bat`。

> 历史遗留：用户 PATH 里还留着一条失效的 `D:\Dart SDK\flutter\bin`
> （`D:\Dart SDK` 整个目录都不存在）。它不影响解析（Windows 会跳过不存在的目录），
> 但建议在 `系统属性 → 环境变量 → 用户变量 Path` 里删掉。
> 改 PATH 时**不要用 `setx PATH "%PATH%;..."`**，它会把 PATH 截断到 1024 字符，可能弄坏环境变量。

> 另外：Git Bash 下如果配了代理，`127.0.0.1` 的请求会被绕出去，先 `unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY`。

```bash
cd "D:/blind cane/cane/app"
unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY

# ① 浏览器跑（开发调试最方便，热重载可用；按 q 退出）
flutter run -d chrome --dart-define=API_BASE_URL=http://127.0.0.1:8001

# ② 真机 / 模拟器：换成局域网 IP，并放行 Windows 防火墙的 8001
flutter run --dart-define=API_BASE_URL=http://192.168.x.x:8001

# ③ 只验证能否编译
flutter build web --dart-define=API_BASE_URL=http://127.0.0.1:8001

# ④ 演示用：跑构建产物 + 静态服务器（不依赖 flutter 进程，最稳）
flutter build web --dart-define=API_BASE_URL=http://127.0.0.1:8001 --dart-define=DEMO_MODE=true
cd build/web && python -m http.server 9100 --bind 127.0.0.1
# 然后浏览器打开 http://127.0.0.1:9100
```

依赖变动后先 `flutter pub get`（`flutter run` 会自动做，但单独跑 `analyze` 前建议手动执行一次）。

`--dart-define` 说明：`API_BASE_URL` 默认就是 `http://127.0.0.1:8001`，本机开发可以不传；
`DEMO_MODE` 默认 `true`，只影响设置页要不要显示「设备模拟器」入口。

### 4. 演示账号

| 项 | 值 |
|---|---|
| 手机号 | `13800138000`（V1 迁移的种子数据，ward 1 的主监护人） |
| 验证码 | `123456`（Mock 短信通道，固定值，页面上会自动填入） |
| 演示设备 | `BC-2024-DEMO01`（启动时自动注册，电量 85%） |
| 起始坐标 | 郑州市 · 华北水利水电大学附近（`113.7845, 34.8133`） |

---

## 四、演示剧本

```bash
# 一条命令跑完：复位 -> 位置 -> 低电量 -> SOS -> 跌倒升级 -> 取消
bash demo.sh
```

也可以手动分步（`TOKEN` 从登录接口取）：

```bash
BASE=http://127.0.0.1:8001
SN=BC-2024-DEMO01

# 复位演示数据（演示前建议每次都跑）
node backend/tools/demo-reset.js

# 位置上报（同时驱动 Redis 热数据 + MySQL 批量落库 + WebSocket 广播）
curl -X POST "$BASE/api/v1/mock/devices/$SN/location?lng=113.7861&lat=34.7431&accuracy=8.5"

# 电量告警（低于 20% 产生 LOW_BATTERY，按 10% 阶梯去重）
curl -X POST "$BASE/api/v1/mock/devices/$SN/battery?level=15"

# SOS：App 应在 3 秒内弹出整屏红色强提醒（实测 ~220ms）
curl -X POST "$BASE/api/v1/mock/devices/$SN/sos"

# 跌倒：先按警示级创建并进入 30 秒待确认窗口，超时未确认自动升级为紧急
curl -X POST "$BASE/api/v1/mock/devices/$SN/fall"
curl -X POST "$BASE/api/v1/mock/devices/$SN/fall/{alertId}/cancel"   # 误报则取消

# 设备离线（离线超过 5 分钟产生 DEVICE_OFFLINE，同一离线周期只发一次）
curl -X POST "$BASE/api/v1/mock/devices/$SN/toggle-online?ageMinutes=6"
```

---

## 五、验证脚本

| 脚本 | 验什么 | 前置 |
|---|---|---|
| `bash backend/tools/verify-s3.sh` | Redis 热数据新鲜度、MySQL 批量落库、STOMP 三主题推送、越权订阅 103001、告警状态机 | 后端运行 |
| `bash backend/tools/verify-s4.sh` | 位置随机游走位移量、电量衰减触发低电量、SOS 等级、跌倒 30 秒升级、取消幂等 | 后端运行 |
| `node app/tools/ui-smoke.js` | 无头 Chrome 真实渲染：登录页 → 首页真实数据 → CORS → WS 已连接 → **SOS 全屏 3 秒内** → 误报关闭 → 低电量不打扰 → 位置实时变化 | 后端运行 + `app/build/web` 已构建 + 静态服务器在 `9100` |
| `bash app/tools/verify-s5.sh [--slow]` | Dart 侧直连后端的契约回归（13 项，含越权拦截与令牌轮换） | 后端运行；**需一次带授权的 `flutter test`** |

排障用：

| 脚本 | 用途 |
|---|---|
| `node app/tools/ws-diagnose.js` | App 自报的 WS 状态 + 语义树 dump + 控制台日志，判断「没连上」还是「连上了收不到」 |
| `node app/tools/ws-browser-probe.js` | 浏览器里手写 STOMP 帧，把「服务端问题」和「客户端库用法问题」分开 |
| `node backend/tools/stomp-watch.js --token=X --ward=1 --duration=30` | 独立订阅三主题，看服务端到底推了什么 |

---

## 六、关键设计取舍（速查）

| 主题 | 取舍 | 理由 |
|---|---|---|
| 认证 | jjwt **0.12.x** 新 API | 彻底避开 0.9.1 的 `javax.xml.bind` 缺失与弃用 API |
| 登出 | Redis 黑名单，TTL = 令牌剩余有效期 | 黑名单不会无限膨胀 |
| 位置 | Redis 热数据 + MySQL 异步批量落库（200 条 / 5 秒） | 实时读走 Redis 保证亚秒延迟；逐条 INSERT 会被 10 秒一次的 上报放大写入 |
| 告警 | **先落库拿到 id，再分发** | 推送可能失败，落库先行保证告警永不丢失；App 侧 20 秒轮询兜底补齐 |
| 去抖 | 离线按「离线周期」、低电量按 10% 阶梯各只发一次 | 避免设备在阈值附近抖动造成告警轰炸 |
| 实时通道 | STOMP + SimpleBroker（内存） | MVP 单实例；多实例时换 `enableStompBrokerRelay` 即可，业务代码不动 |
| 订阅鉴权 | CONNECT 校验 JWT，**SUBSCRIBE 再校验 wardId 是否属于该用户** | 只靠前端隐藏入口不是安全边界，任何人都能手工构造 SUBSCRIBE 偷听他人位置 |
| 全屏提醒 | 只有 `severity=1 且未处理` 才弹 | 低电量、离线这类告警打断家属做任何事都是骚扰 |
| 心跳 | 显式提供 `TaskScheduler` | SimpleBroker 没有 TaskScheduler 时会**静默忽略** heartbeat 配置 |
| 地图 | 无高德 Key 时渲染自绘网格图 | 坐标、精度圈、更新时间逻辑完全不变，不阻塞演示 |
| 令牌存储 | SharedPreferences（非 secure_storage） | 要能在 Chrome 上跑通端到端；**上架前必须换 Keychain / Keystore** |

---

## 七、Mock 降级开关

集中在 `application.yml` 的 `blindcane` 配置块，一键切换生产形态：

| 能力 | 开关 | 关闭后的行为 |
|---|---|---|
| 短信 | `tencent.sms.enabled` | 验证码固定 `123456`，接口直接回传 |
| 推送 | `jpush.enabled` | 只走 STOMP + 日志 |
| 地图 | `amap.web.key` 为空 | 自绘占位网格图 |
| 设备模拟器 | `simulator.enabled` | 定时任务与 `/api/v1/mock/**` 全部不注册 |

---

## 八、已知限制

- **无真实硬件**：所有设备数据由内置模拟器产出，评委演示时需说明（Mock 开关可一键切生产 profile）。
- **位置历史轨迹回放**未做（二期）；当前只有最新位置 + App 内存内的本次会话轨迹。
- **电子围栏命中判断**未做（二期的表结构已预留）。
- **多家属邀请协作**未做；`ward_guardian` 表已含邀请字段占位。
- **当前运行的演示后端实例**带电量加速衰减参数（约每 10 秒 -1%，即 `--blindcane.simulator.battery-decay-cron="0/10 * * * * *"`），
  这是 S4 验证时留下的，重启后端即恢复 `application.yml` 里的 `0 0 * * * *`（每小时 -1%）。
  演示前跑一次 `node backend/tools/demo-reset.js` 会把电量拉回 85%。
- **`app/tools/verify-s5.sh`（Dart 侧契约回归，13 项）已写好但尚未完整跑通**，
  需要一次带授权的 `flutter test` 执行；等价的后端契约已由 `ui-smoke.js` 21 项与
  `verify-s3.sh` / `verify-s4.sh` 覆盖。

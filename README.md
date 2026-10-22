# 智能导盲杖 · 家属监护端（阶段一 MVP）

> 家属端 App（Flutter）+ 后端（Spring Boot）的完整实现。
> **手机是手杖与云端之间的网关**：手杖只走蓝牙，不直接连云；手机解析手杖的
> BLE 遥测、节流后转发给云端，并把云端的命令写回手杖。

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
│   │       └── device/             ★ BLE 接入：DeviceBleController · telemetry/command service
│   ├── src/main/resources/
│   │   ├── application.yml         主配置（含 Mock 降级开关、模拟器参数、BLE 阈值与节流窗口）
│   │   ├── application-dev.yml     本地数据源（开发默认 profile）
│   │   └── db/migration/
│   │       ├── V1__init.sql        Flyway 初始化（9 张表 + 空间索引）
│   │       └── V2__ble_integration.sql  ★ 设备表补 8 个 BLE 字段 + ble_address 索引
│   └── tools/                      验证与运维脚本
│       ├── verify-s3.sh            位置 + 告警 + WebSocket 十项端到端验证
│       ├── verify-s4.sh            设备模拟器验证
│       ├── verify-ble.sh           ★ BLE 全链路验证（11 步 41 项断言，`--watch` 验广播）
│       ├── demo-reset.js           演示前复位数据（清限流 / 复位设备 / 处置遗留告警）
│       ├── stomp-watch.js          STOMP 订阅观察工具（联调排障主力，含 /command 主题）
│       ├── json-get.js             从 JSON 里取字段（bash 里替代 jq）
│       └── geo-delta.js            两点间距离计算
├── app/                            Flutter 3.48 家属端
│   ├── lib/
│   │   ├── core/
│   │   │   ├── ble/                ★ 协议层(纯 Dart) + 真机/Mock 两种链路实现
│   │   │   ├── config/ network/ ws/ storage/ router/ theme
│   │   ├── models/                 与后端 VO 一一对应的数据模型
│   │   ├── state/                  Riverpod 状态层（ws_bridge 推送桥 · cane_state 手杖会话）
│   │   └── features/               auth · home · ward · location · alert · **cane** · settings · shared
│   ├── test/
│   │   ├── ble_protocol_test.dart  ★ 报文解析 + BLE 语义（含畸形输入与距离优先）
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
| Android | 6.0+（API 23+） | ★ 真机连手杖需要 BLE；Android 12+ 申请 `BLUETOOTH_SCAN/CONNECT`，12 以下才需要定位权限 |

> ⚠️ **本机 MySQL 的 SRID 4326 轴序是「纬度在前」**，写 `POINT(lat lng)` 而不是 `POINT(lng lat)`，
> 否则报 `ERROR 3617`。这一条踩过一次，改了半小时。

---

## 三、手杖 BLE 接入（先读这一节）

### 3.1 数据流

```
   导盲杖（ESP32-S3 · BLE 从机）        手机 App（BLE 主机 + 云端网关）           云端
   ┌──────────────────────┐            ┌──────────────────────────┐        ┌──────────────┐
   │ NUS 服务 6E400001     │  Notify    │ 解析 `<状态>,<距离cm>`    │  HTTP  │ /telemetry   │
   │  TX 6E400003 ────────┼───────────▶│ 本机节流                 ├───────▶│ 1 秒窗口节流  │
   │  RX 6E400002 ◀───────┼────────────│ 写 RX 特征               │        │ 距离优先裁决  │
   └──────────────────────┘   Write    │                          │        └──────┬───────┘
                                       │                          │   STOMP       │
                                       │  ◀───────────────────────┼───────────────┘
                                       │  /topic/ward/{id}/command │
                                       └──────────────────────────┘
```

**后端没有蓝牙**。它只提供四个接口（`DeviceBleController`）：

| 接口 | 作用 |
|---|---|
| `POST /api/v1/devices/{id}/telemetry` | 障碍遥测上行，返回 `accepted` 表示是否被采纳 |
| `POST /api/v1/devices/{id}/ble-link` | 蓝牙链路连/断事件，**必须显式上报** |
| `POST /api/v1/devices/{id}/command` | 下发命令（不改变状态，只广播） |
| `POST /api/v1/devices/{id}/command/ack` | 执行回执，**状态的唯一提交点** |

### 3.2 三条不可动摇的规则

1. **`bleConnected` 与 `online` 是两件事。**
   云端在线只说明手机在传数据；蓝牙断了但手机还在，设备依然 `online`。
   界面必须分别显示，否则「云上说在线、其实没连上手杖」这种情况会被掩盖。

2. **距离优先于状态词。**
   报文 `<状态>,<距离cm>` 里两者都能定档，但**距离是物理量，状态词只是固件对它的解释**。
   固件阈值写错、串口串帧、将来改档位而忘了同步另一端，都会让两者打架 ——
   两端（App 与后端）必须裁同一个，否则同一帧会「手机显示有障碍、云端入库危险」。
   只有报文省略距离时才退回采信状态词。

3. **命令回执是唯一的提交点。**
   `POST /command` 只是广播，**不改任何状态**；只有持有 BLE 链路的那台手机把字节真正
   写进 RX 特征后回调 `/command/ack?success=true`，云端才提交 `mute_mode`。
   没连上手杖的一方**不能回执** —— 抢答会把真正执行的那台手机的结果覆盖掉。

### 3.3 两级节流

手杖 500ms 一帧（2 帧/秒），直传会让一台手杖产生 2 次 HTTP + 2 次 UPDATE/秒。

| 层 | 策略 |
|---|---|
| App 侧 | 状态变化立即转发 + 距离跳变 ≥20cm + 30 秒心跳（保设备在线判定） |
| 服务端 | 1 秒窗口；**状态变化不受窗口限制**（危险必须零延迟可见）；设备不在线时立即放行 |

被服务端丢掉的帧返回 `accepted=false`，App 只计数、不当错误 —— 稳态下丢一半是正常现象。

### 3.4 协议常量（《硬件配置说明》）

| 项 | 值 |
|---|---|
| 广播名 | `StarPath` |
| 服务 | `6E400001-B5A3-F393-E0A9-E50E24DCCA9E`（Nordic UART Service） |
| TX（手杖→手机，Notify） | `6E400003-…` |
| RX（手机→手杖，Write） | `6E400002-…` |
| 上行报文 | `<状态>,<距离cm>`，UTF-8，500ms 一帧；状态 `CLEAR` / `NEAR` / `DANGER` |
| 下行命令 | `M` = 切换工作/静音模式 |
| 阈值 | ≥100cm 畅通 · 20~100cm 有障碍 · <20cm 危险（**两端必须一致**） |

---

## 四、启动步骤

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

- 表结构由 Flyway 自动建立（V1 建 9 张表，**V2 补 BLE 字段**）
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
> **`flutter test` 也会踩这个坑**：测试进程与 `flutter_tester` 之间走回环 WebSocket，
> 被代理一挡就报 `Invalid WebSocket upgrade request`，5 个测试文件全数「加载失败」。
> 换依赖时再加 `PUB_HOSTED_URL=https://pub.flutter-io.cn`。

```bash
cd "D:/blind cane/cane/app"
unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY
export no_proxy="127.0.0.1,localhost,::1" NO_PROXY="127.0.0.1,localhost,::1"

# ① 浏览器跑（开发调试最方便，热重载可用；按 q 退出）
#    注意：Web 端「真机」模式受浏览器限制，默认会自动落到「模拟」来源
flutter run -d chrome --dart-define=API_BASE_URL=http://127.0.0.1:8001

# ② 真机 / 模拟器：换成局域网 IP，并放行 Windows 防火墙的 8001
#    Android 真机连手杖需要：蓝牙已开 + 授予「附近的设备」权限（12 以下为定位权限）
flutter run --dart-define=API_BASE_URL=http://192.168.x.x:8001

# ③ 只验证能否编译
flutter build web --dart-define=API_BASE_URL=http://127.0.0.1:8001

# ④ 演示用：跑构建产物 + 静态服务器（不依赖 flutter 进程，最稳）
flutter build web --dart-define=API_BASE_URL=http://127.0.0.1:8001 --dart-define=DEMO_MODE=true
cd build/web && python -m http.server 9100 --bind 127.0.0.1
# 然后浏览器打开 http://127.0.0.1:9100
```

> `flutter pub get` 若报 `Proxy failed to establish tunnel (502)`，那是走公网 pub.dev 超时，
> 加国内镜像即可：
>
> ```bash
> export PUB_HOSTED_URL=https://pub.flutter-io.cn
> export FLUTTER_STORAGE_BASE_URL=https://storage.flutter-io.cn
> ```

依赖变动后先 `flutter pub get`（`flutter run` 会自动做，但单独跑 `analyze` 前建议手动执行一次）。

`--dart-define` 说明：`API_BASE_URL` 默认就是 `http://127.0.0.1:8001`，本机开发可以不传；
`DEMO_MODE` 默认 `true`，只影响设置页要不要显示「设备模拟器」入口。

### 4. 演示账号

| 项 | 值 |
|---|---|
| 手机号 | `13800138000`（ward 1 的主监护人，启动时由 DemoAccountBootstrap 确保存在） |
| 密码 | `123456`（演示账号默认密码，仅 simulator.enabled=true 时自动补齐） |
| 验证码 | 后端随机生成（6 位）：Mock 模式下 `/auth/sms/send` 响应回显 `mockCode`，页面自动填入；也可看后端日志【Mock 短信】一行 |
| 演示设备 | `BC-2024-DEMO01`（启动时自动注册，电量 85%） |
| 演示设备蓝牙地址 | `D0:CF:13:8A:00:01`（`blindcane.simulator.demo-ble-address`，见 §6.2） |
| 起始坐标 | 郑州市 · 华北水利水电大学附近（`113.7845, 34.8133`） |

---

## 五、演示剧本

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

### 手杖（BLE）这一段怎么演

没有真实手杖时，用 Mock 接口扮演「那台连着蓝牙的手机」——
**它们跑的是真实 Service，没有旁路**，所以演示出来的行为和真机一致：

```bash
# 1) 连接手杖（等价于 App 完成服务发现并订阅 TX 通知）
curl -X POST "$BASE/api/v1/mock/ble/devices/$SN/connect?rssi=-58"

# 2) 推一帧危险遥测（只传距离，状态由后端按阈值推导）
curl -X POST "$BASE/api/v1/mock/ble/devices/$SN/telemetry?distanceCm=12"
#   → accepted=true, obstacleStatus=DANGER，App 的「前方障碍」卡立刻变红

# 3) 连发 6 帧看节流：只有第 1 帧被采纳，其余 accepted=false
curl -X POST "$BASE/api/v1/mock/ble/devices/$SN/stream?distanceCm=80&count=6&intervalMs=200"

# 4) 求静音（家属点按钮）→ 手杖执行 → 回执
#    注意：/command 只是广播，不改状态；/command/ack 才是唯一提交点
curl -X POST "$BASE/api/v1/devices/1/command" -H "Authorization: Bearer $TOKEN" \
  -H 'Content-Type: application/json' -d '{"command":"M"}'
curl -X POST "$BASE/api/v1/mock/ble/devices/$SN/command/ack?command=M&success=true"
#   success=false 时 mute_mode 不变 —— 用来证明「回执才是提交点」

# 5) 断开：障碍读数仍在，但 bleConnected=false，App 会把它标成「最后读数」
curl -X POST "$BASE/api/v1/mock/ble/devices/$SN/disconnect"
```

App 侧的入口：**首页 →「手杖连接与实时避障」**（或「我的 → 手杖蓝牙链路」）。
页面上有「真机 / 模拟」来源开关，现场必须能一眼看出当前在跟真机还是本机模拟通信。

---

## 六、验证脚本

| 脚本 | 验什么 | 前置 |
|---|---|---|
| `bash backend/tools/verify-s3.sh` | Redis 热数据新鲜度、MySQL 批量落库、STOMP 三主题推送、越权订阅 103001、告警状态机 | 后端运行 |
| `bash backend/tools/verify-s4.sh` | 位置随机游走位移量、电量衰减触发低电量、SOS 等级、跌倒 30 秒升级、取消幂等 | 后端运行 |
| `PORT=8001 bash backend/tools/verify-ble.sh [--watch]` | ★ BLE 全链路 11 步 41 项：地址登记 → 扫描 → ble-link → 遥测 → 距离优先 → 节流窗口 → 命令/回执 → 断连降级；`--watch` 额外用 STOMP 观察端确认命令确实广播到 `/topic/ward/{id}/command` | 后端运行 |
| `node app/tools/ui-smoke.js` | 无头 Chrome 真实渲染：登录页 → 首页真实数据 → CORS → WS 已连接 → **SOS 全屏 3 秒内** → 误报关闭 → 低电量不打扰 → 位置实时变化 | 后端运行 + `app/build/web` 已构建 + 静态服务器在 `9100` |
| `bash app/tools/verify-s5.sh [--slow]` | Dart 侧直连后端的契约回归（13 项，含越权拦截与令牌轮换） | 后端运行；**需一次带授权的 `flutter test`** |
| `cd app && flutter test` | 单元测试 53 项，其中 `ble_protocol_test.dart` 覆盖报文解析（含 `\0` 补位、脏距离、越界值）与 BLE 语义（**断链时旧读数不算实时值**） | 无（纯 Dart） |

排障用：

| 脚本 | 用途 |
|---|---|
| `node app/tools/ws-diagnose.js` | App 自报的 WS 状态 + 语义树 dump + 控制台日志，判断「没连上」还是「连上了收不到」 |
| `node app/tools/ws-browser-probe.js` | 浏览器里手写 STOMP 帧，把「服务端问题」和「客户端库用法问题」分开 |
| `node backend/tools/stomp-watch.js --token=X --ward=1 --duration=30` | 独立订阅四主题（location / alert / device / command），看服务端到底推了什么 |

### 6.1 verify-ble.sh 的两次踩坑（已修）

- **节流断言不能靠 bash 连发两次 curl**：每次 curl 都要新起进程，间隔可能已超过 1 秒窗口，
  测出来的「没被节流」是脚本自身开销造成的**假阴性**。改为打 `/stream`（一个 HTTP 请求里
  连续调用真实 `reportTelemetry`），帧间隔就是服务端处理耗时，断言才稳定。
- **命令广播的断言不能用主题名做匹配**：日志里「→ 订阅 /topic/…/command」这一行同样含主题名，
  只 grep 主题名会在「订阅成功但一条都没推」时判通过（**假阳性**）。必须排除订阅行。
  （也不要用 emoji 做 pattern —— Git Bash 下多字节匹配不可靠。）

### 6.2 真机联调

1. 手机与电脑连同一 WiFi，后端用局域网 IP 启动（`--server.port=8001`，防火墙放行）。
2. 手杖上电，串口应能看到广播名 `StarPath`；手机 App 进「手杖连接」页，来源选**真机**，点扫描。
3. 连上后页面上「链路状态」应变成「已连接 · 实时接收中」，并开始滚帧数。
4. 若「链路已建立但收不到任何遥测帧」，说明**服务发现成功但 TX 通知没在推** ——
   查手杖固件是否真的启动了 500ms 定时上报（这是最常见的一种「连着但没数据」）。

---

## 七、关键设计取舍（速查）

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
| ★ BLE 链路 | 手机当**网关**，后端不碰蓝牙 | 手杖是无网络能力的 MCU；让手机做协议转换，后端只收结构化 JSON，逻辑与通道解耦 |
| ★ 蓝牙地址归属 | 连接成功后把地址回写云端档案 | iOS 的地址是**每台手机随机生成**的 UUID，换机后不重新登记就永远自动重连不上 |
| ★ 断链语义 | `obstacleStatus` 保留，但 `hasLiveObstacle=false` | 断链后那个「危险 12cm」只是**最后读数**，继续当实时值渲染会一直吓着家属 |
| ★ 地址为空 | 用 `UpdateWrapper` 显式 `.set(null)` | MyBatis-Plus 的 `updateById` **会跳过 null 字段**，断开时想把 `ble_rssi` 清空根本写不进去，库里留个 `-57` 就会显示「蓝牙已断开，信号 -57dBm」 |
| ★ 信号档位 | RSSI → 1~4 档，原始 dBm 另存 `ble_rssi` | 旧 UI 与历史数据都用 1~4 档，换口径会让历史记录的信号含义漂移 |

---

## 八、Mock 降级开关

集中在 `application.yml` 的 `blindcane` 配置块，一键切换生产形态：

| 能力 | 开关 | 关闭后的行为 |
|---|---|---|
| 短信 | `tencent.sms.enabled` | 验证码由后端随机生成、打印日志，接口直接回传 `mockCode` |
| 推送 | `jpush.enabled` | 只走 STOMP + 日志 |
| 地图 | `amap.web.key` 为空 | 自绘占位网格图 |
| 设备模拟器 | `simulator.enabled` | 定时任务与 `/api/v1/mock/**`（含 `/mock/ble/**`）全部不注册 |

BLE 相关的可调参数（同样在 `blindcane` 块）：

| 配置 | 默认 | 含义 |
|---|---|---|
| `device.telemetry-min-interval-ms` | `1000` | 遥测节流窗口；状态变化不受它限制 |
| `device.obstacle-near-cm` | `100` | ≥100cm 判畅通 |
| `device.obstacle-danger-cm` | `20` | <20cm 判危险 |
| `simulator.demo-ble-address` | `D0:CF:13:8A:00:01` | 无硬件时演示用的「虚拟蓝牙地址」，与 App 的 `MockCaneConnection.mockAddress` 一致 |

> 改阈值必须**同时**改 `app/lib/core/ble/ble_protocol.dart` 的 `nearCm` / `dangerCm` ——
> 两端判定不同的话，手机上显示的档位会与云端入库的档位打架。这一条有单测钉住（`协议常量` 组）。

---

## 九、已知限制

- **手杖原型硬件已具备 BLE 能力，但功能不完整**，演示时需说明：
  - **无电量检测**：上行报文里没有电量字段（协议已预留第三个字段），App 电量徽章来自旧的位置上报通道；
  - **触摸按键未接线**：串口读到的按键状态恒为 `0`，所以「切换静音」只能从家属端下发，手杖本体还不能自己切；
  - 因此 `mock/ble/**` 模拟器仍然保留 —— 手杖在实验室、在充电、在别人手上时，演示与联调照样要跑。
- **iOS 的 BLE 地址是随机 UUID**：换手机后必须重新扫描登记，自动重连会失效（已由「连接成功后回写地址」缓解，但不能根治）。
- **Web 端跑不了真机模式**：浏览器要求 HTTPS + 用户手势才能申请蓝牙，所以 `defaultCaneSource()` 在 Web/桌面端默认落到「模拟」。
- **位置历史轨迹回放**未做（二期）；当前只有最新位置 + App 内存内的本次会话轨迹。
- **电子围栏命中判断**未做（二期的表结构已预留）。
- **多家属邀请协作**未做；`ward_guardian` 表已含邀请字段占位。BLE 链路是**一对一**的，
  同一台手杖同时只能被一台手机持有 —— 另一台登录后能看到云端 `bleConnected=true`，
  但界面会明说「链路由其他家属端持有」，且不允许它回执命令。
- **`app/tools/verify-s5.sh`（Dart 侧契约回归，13 项）已写好但尚未完整跑通**，
  需要一次带授权的 `flutter test` 执行；等价的后端契约已由 `ui-smoke.js` 21 项与
  `verify-s3.sh` / `verify-s4.sh` 覆盖。

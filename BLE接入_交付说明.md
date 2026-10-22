# BLE 接入 · 重建与验证交付说明

**日期**：2026-09-19
**目标**：按《硬件配置说明》把丢失的 BLE 接入层重建出来，让真机 ESP32-S3 手杖能连上本监护端软件。
**结论**：已完成并通过端到端验证。后端 41 项断言连续 3 次全通过，App 静态分析零问题、53 项单测通过、release 构建通过。

---

## 一、保真度：不是「照着重写」，是真的还原了

`D:\blind cane\recovery\git-survived\` 里有 4 个侥幸逃过 `.git` 损坏的**原始源码**。逐个 diff：

| 原始文件 | 与重建版对比 |
|---|---|
| `ErrorCode.java` | 内容逐字节相同（仅行尾 CRLF/LF 差异） |
| `DeviceBleController.java` | **完全一致** |
| `DeviceTelemetryServiceImpl.java` | **完全一致** |
| `ble_protocol_test.dart` | 以其为权威版本恢复，另追加 6 组用例 |

`DeviceTelemetryServiceImpl` 能逐字对上是最关键的一条 —— 它承载「距离优先」与「节流窗口」两条核心规则。

---

## 二、重建时发现并修正的一处**真实缺陷**

原 `ble_protocol.dart` 的 `CaneTelemetry.tryParse` 是 **状态词优先、距离兜底**；
而后端 `DeviceTelemetryServiceImpl` 是 **距离优先**：

```java
// 后端：byDistance != null ? byDistance : byHardware
```

两端规则不对称，对同一帧会给出**不同档位** —— 报文 `NEAR,19` 会让手机显示「有障碍」、
云端入库「危险」。现场演示一对照就穿帮，而且是最难查的那类问题。

**已统一为距离优先**（只有报文省略距离时才退回状态词），并在单测里加「距离优先于状态词」组钉住。
两端阈值也加了断言：改 `application.yml` 的 `obstacle-*-cm` 必须同步改 App 的 `BleProtocol.nearCm/dangerCm`。

> 教训：**这类「两端同一条规则」的不对称，靠读单侧代码永远发现不了，必须两端对照。**

---

## 三、本次交付清单

### 后端（新增 16 / 修改 13）

| 类别 | 文件 |
|---|---|
| 迁移与配置 | `V2__ble_integration.sql`（设备表补 8 个 BLE 字段 + `ble_address` 索引）、`application.yml`（阈值 / 节流窗口 / 演示蓝牙地址） |
| 新增 | `entity/ObstacleStatus` `entity/CaneCommand` · `dto/` 9 个（含 `TelemetryAck`、`DeviceCommandMessage`、`BleLinkRequest`…） · `service/DeviceTelemetryService` `service/DeviceCommandService` + 两个 Impl · `controller/DeviceBleController`（4 接口） · `simulator/controller/MockBleController`（扮演手机网关） |
| 修改 | `Device` / `DeviceVO` / `DeviceStatusMessage` / `DeviceBindRequest` / `DeviceService(Impl)` / `DeviceController` / `DeviceOfflineDetectTask` / `ErrorCode` / `BlindcaneProperties` / `WsMessageSender` / `DeviceSimulatorBootstrap` / `MockMaintenanceController` |

### App（新增 6 / 修改 5 / 接线 3）

| 类别 | 文件 |
|---|---|
| 新增 | `core/ble/ble_protocol.dart`（纯 Dart，可单测） · `cane_connection.dart`（抽象） · `real_cane_connection.dart`（flutter_blue_plus 2.3.12） · `mock_cane_connection.dart` · `state/cane_state.dart`（网关核心 + 本机节流） · `features/cane/cane_page.dart` |
| 修改 | `models/device_info.dart` · `data/guardian_repository.dart` · `core/ws/ws_client.dart`（加命令主题） · `state/ward_state.dart` · `pubspec.yaml`（加 `flutter_blue_plus`） |
| 接线 | `core/router/app_router.dart`（`/cane` 路由） · `features/home/main_shell.dart`（会话挂在共同祖先上） · `features/home/home_page.dart` + `features/settings/settings_page.dart`（入口与蓝牙链路状态） · `android/app/src/main/AndroidManifest.xml`（BLE 权限） |

### 脚本与文档

| 文件 | 变更 |
|---|---|
| `backend/tools/verify-ble.sh` | **新建**，11 步 / 41 项断言，`--watch` 额外验 STOMP 广播 |
| `backend/tools/stomp-watch.js` | 订阅三主题 → **四主题**（补 `/topic/ward/{id}/command`） |
| `demo.sh` | 新增「5. 手杖避障（BLE）」演示段，后续步骤重新编号 |
| `README.md` | 新增「三、手杖 BLE 接入」整节；目录结构 / 环境要求 / 演示剧本 / 验证脚本 / 关键取舍 / 已知限制全部补齐 BLE |
| `app/test/ble_protocol_test.dart` | 恢复原始 11 组用例 + 追加 6 组 |

---

## 四、怎么验（三步）

```bash
# ① 后端（8001 留给 IDEA；助手验证临时用 8002，用完停掉）
cd backend && bash build.sh -DskipTests package
java -jar target/guardian-backend-1.0.0.jar --server.port=8002

# ② BLE 全链路 41 项断言（--watch 会额外起 STOMP 观察端，确认命令真的广播了）
cd .. && PORT=8002 bash backend/tools/verify-ble.sh --watch

# ③ App
cd app
export no_proxy="127.0.0.1,localhost,::1" NO_PROXY="127.0.0.1,localhost,::1"
unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY
flutter pub get && flutter analyze && flutter test
```

**实测结果**

| 项 | 结果 |
|---|---|
| `verify-ble.sh --watch` ×3 连续 | **41 / 41 全通过，0 失败** |
| `flutter analyze` | No issues found |
| `flutter test` | **53 passed**（1 skipped：需 `BACKEND_E2E=true` 的直连回归） |
| `flutter build web` | √ Built build\web |

---

## 五、接真机（硬件的正确用法）

1. 手杖上电，广播名 `StarPath`；确认固件真在按 500ms 推 `<状态>,<距离cm>`（串口先看一遍）。
2. 手机装 App，后端地址填**电脑的局域网 IP**（不是 127.0.0.1），放行防火墙 8001。
3. **确保云端已有「已绑定到被监护人的设备记录」** —— 否则遥测只在手机本地显示、不上报。
4. 进 **首页 →「手杖连接与实时避障」**，数据来源选**真机** → 扫描 → 连接。
5. 看到「已连接 · 实时接收中」且帧数在滚 = 通了。

排障对照：

| 现象 | 原因 |
|---|---|
| 扫不到任何设备 | Android 12+ 未授予「附近的设备」；12 以下需定位权限 |
| 能连上但一帧数据都没有 | 服务发现成功 ≠ TX 在推。查固件是否真的启动了定时上报 |
| 页面显示「链路由其他家属端持有」 | 蓝牙链路是**一对一**的，同一台手杖同时只能被一台手机持有 |
| 点静音没反应 | 本机没有 BLE 链路，命令无人执行（界面会提示）；或 WebSocket 断了 |

---

## 六、已知限制（如实说明）

- **原型硬件功能不完整**：**无电量检测**（上行报文没有电量字段）、**触摸按键未接线**（串口 `T` 恒为 `0`，所以静音只能从家属端下发）。
- **iOS 的 BLE 地址是每台手机随机生成的 UUID**：换机后必须重新扫描登记，自动重连会失效（已用「连接成功后回写地址」缓解，不能根治）。
- **Web 端跑不了真机模式**：浏览器要求 HTTPS + 用户手势才能申请蓝牙，所以默认落到「模拟」来源。
- **多家属场景下蓝牙链路不能共享**：另一台手机能看到云端 `bleConnected=true`，但界面会明说「链路由其他家属端持有」，且不允许它回执命令 —— 否则会把真正执行的那台的结果覆盖掉。

---

## 七、还没做的

- `app/tools/verify-s5.sh`（Dart 侧直连后端的契约回归 13 项）仍未完整跑通，需要一次带授权的 `flutter test`。
- 手杖固件的**电量检测**与**触摸按键**要等硬件补齐后才有对应代码路径（协议里已预留第三个字段）。

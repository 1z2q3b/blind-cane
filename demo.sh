#!/usr/bin/env bash
# =============================================================
# 智能导盲杖 · 家属监护端 —— 一键演示剧本
#
# 跑完这一条命令就能看到完整闭环：
#   复位数据 → 位置上报（双写 + 广播）→ 低电量告警 → SOS 紧急告警
#   → 跌倒待确认 → 取消误报 → 设备离线
#
# 全程用独立的 STOMP 客户端把服务端推的每一条消息打出来，
# 相当于把「App 会收到什么」摊在终端上。演示时另开一个窗口跑家属端即可。
#
# 用法：
#   bash demo.sh                # 完整剧本（约 70 秒）
#   bash demo.sh --no-wait      # 不等待，只把事件打出去
#
# 前置：后端已在 127.0.0.1:8001 运行（端口可用环境变量 PORT 覆盖）
# =============================================================
set -u

PORT="${PORT:-8001}"
BASE="${BASE:-http://127.0.0.1:$PORT}"
SN="${SN:-BC-2024-DEMO01}"
WARD="${WARD:-1}"
PHONE="${PHONE:-13800138000}"
SMS_CODE="${SMS_CODE:-123456}"
NO_WAIT=false
for arg in "$@"; do
  [ "$arg" = "--no-wait" ] && NO_WAIT=true
done

ROOT="$(cd "$(dirname "$0")" && pwd)"
# Git Bash 的 /d/... 路径 node 不认，统一转成 Windows 风格给 node 用
WINROOT="$(cygpath -m "$ROOT" 2>/dev/null || echo "$ROOT")"
BACKEND_TOOLS="$ROOT/backend/tools"
WIN_TOOLS="$WINROOT/backend/tools"
TMP="$ROOT/backend/target/demo"
mkdir -p "$TMP"

# 找 node：优先 PATH，其次 WorkBuddy 隔离运行时
if command -v node > /dev/null 2>&1; then
  NODE="node"
elif [ -x "C:/Users/Lenovo/.workbuddy/binaries/node/versions/22.22.2-2/node.exe" ]; then
  NODE="C:/Users/Lenovo/.workbuddy/binaries/node/versions/22.22.2-2/node.exe"
else
  echo "找不到 node，请先把 node 加进 PATH"; exit 1
fi
export NODE_PATH="${NODE_PATH:-C:/Users/Lenovo/.workbuddy/binaries/node/workspace/node_modules}"

# 代理会让 127.0.0.1 的请求绕出去
unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY

step() { echo; echo "──────── $1 ────────"; }
pause() { [ "$NO_WAIT" = true ] || sleep "${1:-3}"; }

step "0. 检查后端"
PROBE=$(curl -s --noproxy '*' --max-time 6 -X POST "$BASE/api/v1/mock/sms/reset?phone=0" 2>/dev/null || true)
case "$PROBE" in
  *'"code":0'*)
    echo "  [OK] 后端在线，且设备模拟器已启用"
    ;;
  *)
    echo "  [FAIL] 后端未在 $BASE 正常响应，或 blindcane.simulator.enabled=false"
    echo "         实际响应: $(echo "$PROBE" | head -c 200)"
    exit 1
    ;;
esac

step "1. 复位演示数据"
"$NODE" "$WIN_TOOLS/demo-reset.js" || exit 1

step "2. 登录拿令牌（Mock 短信固定 123456）"
# 先清限流：上一步 demo-reset 已经登录过一次，验证码被消费掉，
# 而短信 60 秒发送间隔会让这里的 send 直接返回 101005（不真的发码），
# 于是 login 拿到的是那条已消费的旧码，报 101002「验证码已过期」。
curl -s --noproxy '*' -X POST "$BASE/api/v1/mock/sms/reset?phone=$PHONE" \
  -o /dev/null
SEND_RESP=$(curl -s --noproxy '*' -X POST "$BASE/api/v1/auth/sms/send" \
  -H "Content-Type: application/json" -d "{\"phone\":\"$PHONE\"}")
case "$SEND_RESP" in
  *'"code":0'*) : ;;
  *) echo "  [WARN] 发送验证码未成功：$(echo "$SEND_RESP" | head -c 160)" ;;
esac
curl -s --noproxy '*' -X POST "$BASE/api/v1/auth/login" \
  -H "Content-Type: application/json" \
  -d "{\"phone\":\"$PHONE\",\"smsCode\":\"$SMS_CODE\"}" > "$TMP/login.json"
TOKEN=$("$NODE" "$WIN_TOOLS/json-get.js" data.accessToken < "$TMP/login.json")
if [ -z "$TOKEN" ]; then
  echo "  [FAIL] 登录失败：$(head -c 200 "$TMP/login.json")"; exit 1
fi
echo "  [OK] 已登录，令牌长度 ${#TOKEN}（不打印内容）"

step "3. 启动独立 STOMP 观察端（订阅 ward $WARD 的三个主题）"
DURATION=$([ "$NO_WAIT" = true ] && echo 20 || echo 58)
"$NODE" "$WIN_TOOLS/stomp-watch.js" \
  --token="$TOKEN" --ward="$WARD" --duration="$DURATION" > "$TMP/ws.log" 2>&1 &
WS_PID=$!
sleep 4
if grep -q "CONNECTED" "$TMP/ws.log"; then
  echo "  [OK] STOMP 已连接并订阅 location / alert / device"
else
  echo "  [WARN] STOMP 未连上，后续只看 REST 结果：$(head -3 "$TMP/ws.log")"
fi

step "4. 位置上报：模拟老人步行（同时驱动 Redis 热数据 + MySQL 批量落库 + 实时广播）"
for i in 1 2 3; do
  LNG=$("$NODE" -e "process.stdout.write((113.7845+$i*0.00012).toFixed(6))")
  LAT=$("$NODE" -e "process.stdout.write((34.8133+$i*0.00008).toFixed(6))")
  echo "  → 上报 ($LNG, $LAT)"
  curl -s --noproxy '*' -X POST \
    "$BASE/api/v1/mock/devices/$SN/location?lng=$LNG&lat=$LAT&accuracy=8.5&speed=1.2" \
    -o /dev/null
  pause 3
done
echo "  说明：10 秒一次的逐条 INSERT 会放大写库压力，所以实时读走 Redis、历史走批量落库"

step "5. 电量告警：把演示设备压到 15%"
curl -s --noproxy '*' -X POST "$BASE/api/v1/mock/devices/$SN/battery?level=15" \
  -H "Authorization: Bearer $TOKEN" > "$TMP/battery.json"
echo "  [OK] 已设置 15%，低于 20% 阈值应产生 LOW_BATTERY"
echo "  说明：低电量是「警示级」，只进列表和角标，**不弹全屏** —— 避免打扰家属"
pause 4

step "6. SOS：验收硬指标 —— App 应在 3 秒内弹出整屏红色强提醒"
curl -s --noproxy '*' -X POST "$BASE/api/v1/mock/devices/$SN/sos" \
  -H "Authorization: Bearer $TOKEN" > "$TMP/sos.json"
SOS_ID=$("$NODE" "$WIN_TOOLS/json-get.js" data.id < "$TMP/sos.json")
echo "  [OK] 已产生 SOS 告警 id=$SOS_ID（severity=1 紧急）"
echo "  此时家属端如果开着，屏幕上会立刻变成红色全屏页 + 一键拨打 120"
pause 6

step "7. 跌倒：先按警示级创建，进入 30 秒待确认窗口"
curl -s --noproxy '*' -X POST "$BASE/api/v1/mock/devices/$SN/fall" \
  -H "Authorization: Bearer $TOKEN" > "$TMP/fall.json"
FALL_ID=$("$NODE" "$WIN_TOOLS/json-get.js" data.id < "$TMP/fall.json")
echo "  [OK] 已产生跌倒告警 id=$FALL_ID（severity=2 警示，pendingConfirm=1）"
echo "  说明：30 秒内没人确认就自动升级为紧急 —— 既避免误报轰炸，又不漏掉真跌倒"
pause 5

step "8. 误报：取消这条跌倒"
curl -s --noproxy '*' -X POST \
  "$BASE/api/v1/mock/devices/$SN/fall/$FALL_ID/cancel?note=%E5%AE%B6%E5%B1%9E%E7%A1%AE%E8%AE%A4%E6%98%AF%E8%AF%AF%E6%8A%A5" \
  -H "Authorization: Bearer $TOKEN" > "$TMP/cancel.json"
echo "  [OK] 已取消，状态置为「误报」，且不会再被自动升级（重复取消会被幂等拒绝）"
pause 3

step "9. 设备离线：把最后上报时间推前 6 分钟（阈值 5 分钟）"
curl -s --noproxy '*' -X POST \
  "$BASE/api/v1/mock/devices/$SN/toggle-online?ageMinutes=6" \
  -H "Authorization: Bearer $TOKEN" > /dev/null
echo "  [OK] 已切离线，离线扫描任务（60 秒一次）会补一条 DEVICE_OFFLINE"
echo "  说明：同一离线周期只告警一次，去抖标记在设备恢复上报后重置"
pause 4

step "10. 处置告警：把 SOS 标记为已处理"
curl -s --noproxy '*' -X PUT "$BASE/api/v1/alerts/$SOS_ID/handle" \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $TOKEN" \
  -d '{"result":"RESOLVED","note":"demo.sh 演示处置"}' > /dev/null
echo "  [OK] SOS 已置为已处理，App 侧角标随之减少"

if [ "$NO_WAIT" = false ]; then
  step "11. 等待观察端收集完推送"
  wait "$WS_PID" 2>/dev/null || true
  echo "  ---- 服务端实际推送的消息 ----"
  sed 's/^/  /' "$TMP/ws.log"
fi

step "12. 收尾：复位演示数据"
"$NODE" "$WIN_TOOLS/demo-reset.js" | sed 's/^/  /'

echo
echo "════════ 演示结束 ════════"
echo "家属端启动方式："
echo "  cd app && flutter run -d chrome --dart-define=API_BASE_URL=$BASE"
echo "演示账号：$PHONE / 验证码 $SMS_CODE"

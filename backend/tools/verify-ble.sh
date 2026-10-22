#!/usr/bin/env bash
# =============================================================
# 智能导盲杖 · BLE 接入端到端验证（11 步）
#
# 验证的是「接入蓝牙之后新增的那条链路」是否真的按设计工作：
#
#   ①  绑定/登记蓝牙地址 → ② 扫描能看到它
#   ③  链路连接（ble-link）→ ④ 遥测上行（距离优先）
#   ⑤  服务端节流（状态变化放行 / 重复帧丢弃 / 窗口过后放行）
#   ⑥  命令下行 + 回执（回执才是状态的唯一提交点）
#   ⑦  回执失败不提交 / 不支持的命令被拒
#   ⑧  断连 → 障碍读数变成「最后读数」而不是当前状态
#
# 全程用真实的 Service 层：本脚本打的接口与 App 打的完全一样
# （Mock 接口只是代替手机去发起调用，没有任何旁路逻辑）。
#
# 用法：
#   bash backend/tools/verify-ble.sh              # 默认打 127.0.0.1:8001
#   PORT=8002 bash backend/tools/verify-ble.sh    # 临时实例
#   bash backend/tools/verify-ble.sh --watch      # 额外起 STOMP 观察端，验证命令确实被广播
#
# 前置：后端已启动，且 blindcane.simulator.enabled=true（演示 profile 默认开启）
# =============================================================
set -u

PORT="${PORT:-8001}"
BASE="${BASE:-http://127.0.0.1:$PORT}"
SN="${SN:-BC-2024-DEMO01}"
WARD="${WARD:-1}"
PHONE="${PHONE:-13800138000}"
# 验证码不再固定：由后端随机生成，Mock 模式下从 /auth/sms/send 响应里取（见步骤 1）
# 与服务端 blindcane.device.telemetry-min-interval-ms 对应，节流断言要按它算等待时间
WINDOW_MS="${WINDOW_MS:-1000}"
WATCH=false
for arg in "$@"; do
  [ "$arg" = "--watch" ] && WATCH=true
done

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BACKEND="$ROOT/backend"
WIN_BACKEND="$(cygpath -m "$BACKEND" 2>/dev/null || echo "$BACKEND")"
WIN_TOOLS="$WIN_BACKEND/tools"
TMP="$BACKEND/target/verify-ble"
mkdir -p "$TMP"

# 找 node：优先 PATH，其次 WorkBuddy 隔离运行时
if command -v node > /dev/null 2>&1; then
  NODE="node"
elif [ -x "C:/Users/Lenovo/.workbuddy/binaries/node/versions/22.22.2-6/node.exe" ]; then
  NODE="C:/Users/Lenovo/.workbuddy/binaries/node/versions/22.22.2-6/node.exe"
else
  echo "找不到 node，请先把 node 加进 PATH"; exit 1
fi
export NODE_PATH="${NODE_PATH:-C:/Users/Lenovo/.workbuddy/binaries/node/workspace/node_modules}"

# 代理会让 127.0.0.1 的请求绕出去，必须清掉
unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY

PASS=0
FAIL=0
step()  { echo; echo "──────── $1 ────────"; }
ok()    { PASS=$((PASS + 1)); echo "  [PASS] $1"; }
bad()   { FAIL=$((FAIL + 1)); echo "  [FAIL] $1"; }
check() { # check <描述> <实际> <期望>
  if [ "$2" = "$3" ]; then ok "$1（$2）"; else bad "$1：期望 [$3]，实际 [$2]"; fi
}
ne() { # ne <描述> <实际> <不应等于>
  if [ "$2" != "$3" ]; then ok "$1（$2）"; else bad "$1：不应等于 [$3]"; fi
}

req() { # req <METHOD> <PATH> [BODY] [TOKEN]
  local method="$1" path="$2" body="${3:-}" token="${4:-}"
  local -a args=(-s --noproxy '*' --max-time 20 -X "$method" "$BASE$path")
  [ -n "$body" ] && args+=(-H 'Content-Type: application/json' -d "$body")
  [ -n "$token" ] && args+=(-H "Authorization: Bearer $token")
  curl "${args[@]}"
}
field() { printf '%s' "$1" | "$NODE" "$WIN_TOOLS/json-get.js" "$2"; }
# 等节流窗口。用 node 而不是 sleep：Git Bash 的 sleep 只有整数秒精度
sleep_ms() { "$NODE" -e "setTimeout(()=>process.exit(0),$1)"; }

step "0. 前置：后端在线且模拟器已启用"
PROBE=$(req POST "/api/v1/mock/sms/reset?phone=0")
case "$PROBE" in
  *'"code":0'*) ok "后端在线 @ $BASE" ;;
  *) bad "后端未在 $BASE 正常响应（或 simulator.enabled=false）：$(echo "$PROBE" | head -c 160)"; echo; echo "中止。"; exit 1 ;;
esac

step "1. 复位演示数据并登录"
req POST "/api/v1/mock/devices/$SN/reset" > "$TMP/reset.json"
check "演示设备复位" "$(field "$(cat "$TMP/reset.json")" code)" "0"

req POST "/api/v1/mock/sms/reset?phone=$PHONE" > /dev/null
SEND_RESP=$(req POST "/api/v1/auth/sms/send" "{\"phone\":\"$PHONE\"}")
SMS_CODE=$(field "$SEND_RESP" data.mockCode)
if [ -z "$SMS_CODE" ]; then
  bad "发送验证码失败：$(printf '%s' "$SEND_RESP" | head -c 200)"; echo; echo "中止。"; exit 1
fi
req POST "/api/v1/auth/login" "{\"phone\":\"$PHONE\",\"smsCode\":\"$SMS_CODE\"}" > "$TMP/login.json"
TOKEN=$(field "$(cat "$TMP/login.json")" data.accessToken)
if [ -z "$TOKEN" ]; then
  bad "登录失败：$(head -c 200 "$TMP/login.json")"; echo; echo "中止。"; exit 1
fi
ok "已登录（令牌长度 ${#TOKEN}，不打印内容）"

req GET "/api/v1/wards/$WARD" "" "$TOKEN" > "$TMP/ward.json"
DEVICE_ID=$(field "$(cat "$TMP/ward.json")" data.device.id)
if [ -z "$DEVICE_ID" ]; then
  bad "ward $WARD 未绑定设备，无法继续"; echo; echo "中止。"; exit 1
fi
ok "照护对象 ward=$WARD 已绑定设备 deviceId=$DEVICE_ID"

# 命令下行要验证「确实广播了」，所以观察端必须赶在下发之前连上
if [ "$WATCH" = true ]; then
  step "1b. 启动 STOMP 观察端（订阅含 /command 的四个主题）"
  # duration 给足即可：脚本做完断言后会主动把它终止，
  # 不依赖「监听时长恰好等于脚本耗时」这种脆弱的对齐
  "$NODE" "$WIN_TOOLS/stomp-watch.js" \
    --token="$TOKEN" --ward="$WARD" --duration=300 > "$TMP/ws.log" 2>&1 &
  WS_PID=$!
  sleep 5
  if grep -q "CONNECTED" "$TMP/ws.log"; then
    ok "STOMP 已连接"
  else
    bad "STOMP 未连上：$(head -3 "$TMP/ws.log")"
  fi
fi

step "2. 登记手杖蓝牙地址（等价于 App 连接成功后回写地址，供下次自动重连）"
req POST "/api/v1/devices/$DEVICE_ID/ble-address" \
  "{\"bleAddress\":\"D0:CF:13:8A:00:01\"}" "$TOKEN" > "$TMP/addr.json"
check "登记蓝牙地址" "$(field "$(cat "$TMP/addr.json")" code)" "0"
check "云端已保存地址" "$(field "$(cat "$TMP/addr.json")" data.bleAddress)" "D0:CF:13:8A:00:01"

step "3. 模拟扫描：应能扫到已登记的那台手杖"
req GET "/api/v1/mock/ble/scan" > "$TMP/scan.json"
check "扫描到广播地址" "$(field "$(cat "$TMP/scan.json")" data.0.bleAddress)" "D0:CF:13:8A:00:01"
check "扫描结果带 deviceId（说明是已登记设备，不是幽灵广播）" \
  "$(field "$(cat "$TMP/scan.json")" data.0.deviceId)" "$DEVICE_ID"

step "4. 链路连接：ble-link 上报"
req POST "/api/v1/mock/ble/devices/$SN/connect?rssi=-58" > "$TMP/connect.json"
check "bleConnected" "$(field "$(cat "$TMP/connect.json")" data.bleConnected)" "true"
check "bleRssi 落库" "$(field "$(cat "$TMP/connect.json")" data.bleRssi)" "-58"
# RSSI -58 属于「同房间强信号」档
check "RSSI 换算成信号档位 4" "$(field "$(cat "$TMP/connect.json")" data.signalLevel)" "4"

step "5. 遥测上行 · 畅通（只传距离，状态由后端按阈值推导）"
req POST "/api/v1/mock/ble/devices/$SN/telemetry?distanceCm=235" > "$TMP/t1.json"
check "该帧被采纳" "$(field "$(cat "$TMP/t1.json")" data.accepted)" "true"
check "推导档位 CLEAR" "$(field "$(cat "$TMP/t1.json")" data.obstacleStatus)" "CLEAR"
check "距离原样落库" "$(field "$(cat "$TMP/t1.json")" data.distanceCm)" "235"

step "6. 状态变化不受节流限制：立刻上报危险帧，必须零延迟可见"
req POST "/api/v1/mock/ble/devices/$SN/telemetry?distanceCm=12" > "$TMP/t2.json"
check "危险帧紧跟上一帧仍被采纳" "$(field "$(cat "$TMP/t2.json")" data.accepted)" "true"
check "推导档位 DANGER" "$(field "$(cat "$TMP/t2.json")" data.obstacleStatus)" "DANGER"

step "7. 服务端节流：同一状态连发 3 帧，只应放行第 1 帧"
# 为什么用 /stream 而不是在 bash 里连发两次 curl：
# 每次 curl 都要新起进程，间隔可能已超过 1 秒窗口，测出来的「没被节流」
# 是脚本自身的开销造成的假阴性。/stream 在一个 HTTP 请求里连续调用
# 真实的 reportTelemetry，帧间隔就是服务端的处理耗时（毫秒级），断言才稳定
req POST "/api/v1/mock/ble/devices/$SN/stream?distanceCm=77&count=3&intervalMs=0" > "$TMP/stream.json"
# 77cm 对应 NEAR，与上一帧的 DANGER 不同 → 第 1 帧因「状态变化」放行
check "第 1 帧：状态变化 → 放行" "$(field "$(cat "$TMP/stream.json")" data.0.accepted)" "true"
check "第 1 帧档位 NEAR" "$(field "$(cat "$TMP/stream.json")" data.0.obstacleStatus)" "NEAR"
check "第 2 帧：状态未变且在窗口内 → 丢弃" "$(field "$(cat "$TMP/stream.json")" data.1.accepted)" "false"
check "第 3 帧：同上 → 丢弃" "$(field "$(cat "$TMP/stream.json")" data.2.accepted)" "false"
ok "丢弃原因：$(field "$(cat "$TMP/stream.json")" data.1.reason)"

step "8. 窗口过后同样的帧应被放行（这就是 30 秒心跳能被接受的原因）"
sleep_ms "$((WINDOW_MS + 300))"
req POST "/api/v1/mock/ble/devices/$SN/telemetry?distanceCm=77" > "$TMP/t4.json"
check "超过 ${WINDOW_MS}ms 窗口后放行" "$(field "$(cat "$TMP/t4.json")" data.accepted)" "true"

step "9. 距离优先于状态词：状态说 NEAR 但距离 19cm，必须以距离为准"
req POST "/api/v1/mock/ble/devices/$SN/telemetry?status=NEAR&distanceCm=19" > "$TMP/t5.json"
check "采纳" "$(field "$(cat "$TMP/t5.json")" data.accepted)" "true"
check "按距离判为 DANGER（不是状态词的 NEAR）" "$(field "$(cat "$TMP/t5.json")" data.obstacleStatus)" "DANGER"

step "10. 状态与距离都不可用 → 拒绝入库（104008）"
req POST "/api/v1/mock/ble/devices/$SN/telemetry?battery=90" > "$TMP/t6.json"
check "错误码" "$(field "$(cat "$TMP/t6.json")" code)" "104008"

step "11. 命令下行与回执"
# 紧贴着被测动作另起一个观察端，而不是复用步骤 3 那个：
# 步骤 3 的观察端从脚本开头就挂着，到这一步已经过了 40 多秒，
# 中间任何一次网络抖动 / 心跳超时都会让它静默掉线 —— 于是「没收到广播」
# 到底是服务端没推、还是观察端早就断了，就分不清了。
# 让观察窗口贴着动作，结论才唯一。
if [ "$WATCH" = true ]; then
  "$NODE" "$WIN_TOOLS/stomp-watch.js" \
    --token="$TOKEN" --ward="$WARD" --duration=40 > "$TMP/ws-cmd.log" 2>&1 &
  CMD_WS_PID=$!
  sleep 4
  if grep -q "CONNECTED" "$TMP/ws-cmd.log"; then
    echo "  [OK] 命令观察端已就绪（订阅四个主题）"
  else
    echo "  [WARN] 命令观察端未连上：$(head -3 "$TMP/ws-cmd.log")"
  fi
fi

echo "  · 读取下发前的权威状态"
req POST "/api/v1/mock/ble/devices/$SN/telemetry?distanceCm=150" > "$TMP/t7.json"
MUTE_BEFORE=$(field "$(cat "$TMP/t7.json")" data.muteMode)
LAST_OBSTACLE=$(field "$(cat "$TMP/t7.json")" data.obstacleStatus)
LAST_DISTANCE=$(field "$(cat "$TMP/t7.json")" data.distanceCm)
ok "下发前 muteMode=$MUTE_BEFORE，障碍=$LAST_OBSTACLE ${LAST_DISTANCE}cm"

req POST "/api/v1/devices/$DEVICE_ID/command" '{"command":"M"}' "$TOKEN" > "$TMP/cmd.json"
check "命令下发成功" "$(field "$(cat "$TMP/cmd.json")" code)" "0"
check "返回命令码" "$(field "$(cat "$TMP/cmd.json")" data.command)" "M"
check "返回预期模式（仅用于乐观显示，不代表已生效）" "$(field "$(cat "$TMP/cmd.json")" data.muteMode)" "1"
check "命令体带 wardId（决定广播到哪个主题）" "$(field "$(cat "$TMP/cmd.json")" data.wardId)" "$WARD"

# 再取一次权威状态：只下发未回执时不得改变
req POST "/api/v1/mock/ble/devices/$SN/telemetry?distanceCm=90" > "$TMP/t8.json"
MUTE_AFTER_ISSUE=$(field "$(cat "$TMP/t8.json")" data.muteMode)
LAST_OBSTACLE=$(field "$(cat "$TMP/t8.json")" data.obstacleStatus)
LAST_DISTANCE=$(field "$(cat "$TMP/t8.json")" data.distanceCm)
check "仅下发未回执时 muteMode 仍为 $MUTE_BEFORE" "$MUTE_AFTER_ISSUE" "$MUTE_BEFORE"

echo "  · 回执 success=false：保持原状（手机写 RX 特征失败，云端不能误以为模式变了）"
req POST "/api/v1/mock/ble/devices/$SN/command/ack?command=M&success=false&detail=%E5%86%99%E7%89%B9%E5%BE%81%E5%A4%B1%E8%B4%A5" \
  > "$TMP/ack-fail.json"
check "回执失败后 muteMode 不变" "$(field "$(cat "$TMP/ack-fail.json")" data.muteMode)" "$MUTE_BEFORE"

echo "  · 回执 success=true：提交模式变更"
req POST "/api/v1/mock/ble/devices/$SN/command/ack?command=M&success=true" > "$TMP/ack-ok.json"
ne "回执成功后 muteMode 已翻转" "$(field "$(cat "$TMP/ack-ok.json")" data.muteMode)" "$MUTE_BEFORE"

echo "  · 白名单外的命令应被拒绝（104007），而不是静默忽略"
req POST "/api/v1/devices/$DEVICE_ID/command" '{"command":"P"}' "$TOKEN" > "$TMP/cmd-bad.json"
check "不支持的命令" "$(field "$(cat "$TMP/cmd-bad.json")" code)" "104007"

step "12. 断连：障碍读数必须降级为「最后读数」"
req POST "/api/v1/mock/ble/devices/$SN/disconnect" > "$TMP/disc.json"
check "bleConnected" "$(field "$(cat "$TMP/disc.json")" data.bleConnected)" "false"
check "bleRssi 被清空（断开后不该还挂着信号值）" "$(field "$(cat "$TMP/disc.json")" data.bleRssi)" ""
# 断连后读数被保留，但不能当实时值 —— 这正是 App 里 hasLiveObstacle 存在的理由
check "障碍状态保留为断连前的最后档位" \
  "$(field "$(cat "$TMP/disc.json")" data.obstacleStatus)" "$LAST_OBSTACLE"
check "距离也保留（供界面写「最后读数 xx cm」）" \
  "$(field "$(cat "$TMP/disc.json")" data.obstacleDistanceCm)" "$LAST_DISTANCE"
echo "    → App 侧据此把该读数标为过期（DeviceInfo.hasLiveObstacle=false），不再当作当前状态"

if [ "$WATCH" = true ]; then
  step "13. 确认命令与设备状态确实经 STOMP 推了出去"
  sleep 3   # 给观察端把最后一帧推完的时间
  # 判定"确实收到"而不是"订阅成功"：
  # 日志里「→ 订阅 /topic/ward/1/command」这一行同样含主题名，
  # 只 grep 主题名会在"订阅成功但一条都没推"时判通过（假阳性）。
  # 这里排除掉订阅行，剩下的才是真正的实收消息。
  # （不用 emoji 做匹配：Git Bash 下多字节 pattern 的匹配不可靠）
  RECEIVED=$(grep "/topic/ward/$WARD/" "$TMP/ws-cmd.log" | grep -v "订阅" || true)
  if printf '%s' "$RECEIVED" | grep -q "/topic/ward/$WARD/command"; then
    ok "收到 /topic/ward/$WARD/command 广播"
  else
    bad "未收到命令主题的实收消息，命令将无人执行"
  fi
  if printf '%s' "$RECEIVED" | grep -q "/topic/ward/$WARD/device"; then
    ok "收到 /topic/ward/$WARD/device 状态广播"
  else
    bad "未收到设备状态广播"
  fi
  echo "  ---- 命令观察端实收 ----"
  sed 's/^/  /' "$TMP/ws-cmd.log"

  kill "$WS_PID" 2>/dev/null || true
  kill "$CMD_WS_PID" 2>/dev/null || true
  wait "$WS_PID" 2>/dev/null || true
  wait "$CMD_WS_PID" 2>/dev/null || true
fi

echo
echo "════════ BLE 端到端验证结束：通过 $PASS 项，失败 $FAIL 项 ════════"
if [ "$FAIL" -gt 0 ]; then
  exit 1
fi
echo "下一步（真机）："
echo "  cd app && flutter run -d <android-device> --dart-define=API_BASE_URL=$BASE"
echo "  进「首页 → 手杖连接与实时避障」，数据来源选「真机」，扫描并连接广播名 StarPath 的那台手杖"

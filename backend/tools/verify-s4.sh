#!/usr/bin/env bash
# S4 设备模拟器端到端验证
#   覆盖：位置随机游走 · 电量衰减 + 低电量告警 · SOS · 跌倒 30 秒自动升级 · 跌倒取消幂等
#
# 为缩短验证时间，请用较快的心跳启动后端：
#   java -jar target/guardian-backend-1.0.0.jar \
#        --blindcane.simulator.battery-decay-cron="0/10 * * * * *"
#   （fall-confirm-timeout-seconds 保持默认 30，才能验证真实的 30 秒升级）
set -u

PORT="${PORT:-8001}"
BASE="http://127.0.0.1:$PORT"
MYSQL="/c/Program Files/MySQL/MySQL Server 8.0/bin/mysql"
REDIS="/d/redis/redis-cli"
NODE="C:/Users/Lenovo/.workbuddy/binaries/node/versions/22.22.2-2/node.exe"
export NODE_PATH="C:/Users/Lenovo/.workbuddy/binaries/node/workspace/node_modules"

DB="blind_cane_guardian"
SN="BC-2024-DEMO01"
WARD_ID=1
PHONE="13800138000"      # ward 1 的合法监护人
FALL_TIMEOUT=30          # 与 application.yml 的 fall-confirm-timeout-seconds 保持一致

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WINROOT="$(cygpath -m "$ROOT" 2>/dev/null || echo "$ROOT")"
TMP="$ROOT/target/verify"
WINTMP="$WINROOT/target/verify"
mkdir -p "$TMP"

FAILED=0
pass() { echo "  [PASS] $1"; }
fail() { echo "  [FAIL] $1"; FAILED=1; }
q() { "$MYSQL" -uroot -p"${MYSQL_PASSWORD:-060307}" -N -e "$1" 2>/dev/null; }
# 轮询直到取到非空且不等于 $2 的值（$1=SQL, $2=当前值, $3=超时秒数）
poll_change() {
  local sql="$1" old="$2" timeout="$3" waited=0
  while [ "$waited" -lt "$timeout" ]; do
    local now; now=$(q "$sql")
    if [ -n "$now" ] && [ "$now" != "$old" ]; then echo "$now"; return 0; fi
    sleep 1; waited=$((waited + 1))
  done
  echo "$old"; return 1
}

echo "== 0. 登录（$PHONE） =="
# 先清掉短信限流：开发期同一号码一天会登录很多次，否则会撞上「每日上限」业务规则
curl -s --noproxy '*' -X POST "$BASE/api/v1/mock/sms/reset?phone=$PHONE" > /dev/null
curl -s --noproxy '*' -X POST "$BASE/api/v1/auth/sms/send" -H "Content-Type: application/json" \
  -d "{\"phone\":\"$PHONE\"}" > /dev/null
curl -s --noproxy '*' -X POST "$BASE/api/v1/auth/login" -H "Content-Type: application/json" \
  -d "{\"phone\":\"$PHONE\",\"smsCode\":\"123456\"}" > "$TMP/login.json"
TOKEN=$(cat "$TMP/login.json" | "$NODE" "$WINROOT/tools/json-get.js" data.accessToken)
if [ -n "$TOKEN" ]; then pass "登录成功"; else fail "登录失败: $(cat "$TMP/login.json")"; exit 1; fi

echo "== 1. 位置随机游走（10 秒/次） =="
CNT0=$(q "SELECT COUNT(*) FROM $DB.location_record;")
HOT0=$("$REDIS" GET "loc:ward:$WARD_ID" 2>/dev/null)
echo "  起始记录数=$CNT0"
echo "  起始热数据=$HOT0"
sleep 26
CNT1=$(q "SELECT COUNT(*) FROM $DB.location_record;")
HOT1=$("$REDIS" GET "loc:ward:$WARD_ID" 2>/dev/null)
echo "  26 秒后记录数=$CNT1（新增 $((CNT1 - CNT0))）"
echo "  26 秒后热数据=$HOT1"
if [ $((CNT1 - CNT0)) -ge 2 ]; then pass "随机游走持续产生位置上报"; else fail "未观察到位置漂移"; fi
if [ "$HOT0" != "$HOT1" ]; then pass "Redis 最新位置随时间更新"; else fail "Redis 最新位置未更新"; fi

# 单步位移应落在合理区间：步长 1m，加上 25% 概率静止，允许 0~5m
STEP=$("$NODE" "$WINROOT/tools/geo-delta.js" "$HOT0" "$HOT1" 2>/dev/null)
echo "  相邻采样点位移 ≈ ${STEP} m（步长配置 1m/10s）"
if [ "$STEP" != "n/a" ]; then
  $NODE -e "process.exit(Number('$STEP')<=5?0:1)" && pass "位移量符合步行速度" || fail "位移量异常：${STEP}m"
fi

echo "== 2. 电量衰减 + 低电量告警 =="
# 清掉电量阶梯去重标记与历史低电量告警，让本次断言从干净状态开始
q "DELETE FROM $DB.alert_record WHERE alert_type='LOW_BATTERY';"
DEV_ID=$(q "SELECT id FROM $DB.device WHERE device_sn='$SN';")
"$REDIS" DEL "alert:battery:notified:$DEV_ID" > /dev/null 2>&1
# 先把电量放到阈值 20 的上一格（21），让衰减一步就能触发 LOW_BATTERY
BAT_SET=$(curl -s --noproxy '*' -X POST "$BASE/api/v1/mock/devices/$SN/battery?level=21")
echo "  设置电量响应: $(echo "$BAT_SET" | head -c 120)"
echo "$BAT_SET" | grep -q '"code":0' || fail "Mock 设置电量失败（接口参数名为 level）"
B0=$(q "SELECT battery FROM $DB.device WHERE device_sn='$SN';")
echo "  起始电量=$B0%（阈值 20%）"
B1=$(poll_change "SELECT battery FROM $DB.device WHERE device_sn='$SN';" "$B0" 25 || true)
echo "  衰减后电量=$B1%"
if [ "$B1" -lt "$B0" ]; then pass "电量按 cron 自动衰减"; else fail "电量未衰减（是否用了默认每小时 cron？）"; fi
LOW=$(q "SELECT COUNT(*) FROM $DB.alert_record WHERE alert_type='LOW_BATTERY' AND ward_id=$WARD_ID;")
[ "$LOW" -ge 1 ] && pass "低电量告警已产生（$LOW 条）" || fail "未产生低电量告警"

echo "== 3. SOS 一键求助 =="
q "DELETE FROM $DB.alert_record WHERE alert_type IN ('SOS','FALL_DETECTED');"
SOS=$(curl -s --noproxy '*' -X POST "$BASE/api/v1/mock/devices/$SN/sos")
echo "  $SOS"
SOS_ID=$(echo "$SOS" | "$NODE" "$WINROOT/tools/json-get.js" data.id)
ROW=$(q "SELECT alert_type, severity, status, pending_confirm FROM $DB.alert_record WHERE id=$SOS_ID;")
echo "  落库: $ROW"
echo "$ROW" | grep -q "^SOS	1	0	0$" && pass "SOS 告警：severity=1 紧急 · 待处理 · 无需确认" || fail "SOS 落库字段异常"

echo "== 4. 跌倒检测 30 秒自动升级 =="
FALL=$(curl -s --noproxy '*' -X POST "$BASE/api/v1/mock/devices/$SN/fall")
FALL_ID=$(echo "$FALL" | "$NODE" "$WINROOT/tools/json-get.js" data.id)
R0=$(q "SELECT severity, pending_confirm FROM $DB.alert_record WHERE id=$FALL_ID;")
NOTE0=$(q "SELECT note FROM $DB.alert_record WHERE id=$FALL_ID;")
echo "  创建时 (severity, pending_confirm) = $R0  → 期望 2,1（警示级待确认）"
echo "$R0" | grep -q "^2	1$" && pass "疑似跌倒初始为警示级 + 待确认" || fail "疑似跌倒初始字段异常"
echo "  等待 ${FALL_TIMEOUT}s 触发升级..."
sleep $((FALL_TIMEOUT + 8))
R1=$(q "SELECT severity, pending_confirm FROM $DB.alert_record WHERE id=$FALL_ID;")
NOTE=$(q "SELECT note FROM $DB.alert_record WHERE id=$FALL_ID;")
echo "  升级后 (severity, pending_confirm) = $R1  → 期望 1,0（升级为紧急）"
echo "  备注: $NOTE"
echo "$R1" | grep -q "^1	0$" && pass "超时未确认自动升级为紧急告警" || fail "未按预期升级"
# 断言「备注被追加了升级说明」而不是匹配中文字面量：
# 不同环境下 mysql 客户端输出编码可能不同，中文模式匹配并不可靠，
# 用长度增长做结构化断言，既跨环境稳定，也确实验证了「追加」这个行为。
if [ "${#NOTE}" -gt "${#NOTE0}" ]; then
  pass "升级原因已追加到备注（${#NOTE0} -> ${#NOTE} 字符）"
else
  fail "备注未记录升级原因"
fi

echo "== 5. 跌倒取消（幂等，不应再被升级） =="
FALL2=$(curl -s --noproxy '*' -X POST "$BASE/api/v1/mock/devices/$SN/fall")
FALL2_ID=$(echo "$FALL2" | "$NODE" "$WINROOT/tools/json-get.js" data.id)
CANCEL=$(curl -s --noproxy '*' -X POST "$BASE/api/v1/mock/devices/$SN/fall/$FALL2_ID/cancel")
R2=$(q "SELECT status, pending_confirm FROM $DB.alert_record WHERE id=$FALL2_ID;")
echo "  取消后 (status, pending_confirm) = $R2  → 期望 2,0（误报）"
echo "$R2" | grep -q "^2	0$" && pass "按键取消标记为误报" || fail "取消失败: $(echo "$CANCEL" | head -c 160)"

AGAIN=$(curl -s --noproxy '*' -X POST "$BASE/api/v1/mock/devices/$SN/fall/$FALL2_ID/cancel")
echo "$AGAIN" | grep -q '"code":109003' && pass "重复取消被拦截（109003 幂等）" || fail "重复取消未拦截"

echo "  等待 ${FALL_TIMEOUT}s 确认已取消的告警不会被误升级..."
sleep $((FALL_TIMEOUT + 8))
R3=$(q "SELECT severity, status, pending_confirm FROM $DB.alert_record WHERE id=$FALL2_ID;")
echo "  最终 (severity, status, pending_confirm) = $R3  → 期望仍为 2,2,0"
echo "$R3" | grep -q "^2	2	0$" && pass "已取消的告警未被升级（状态机正确）" || fail "已取消告警被错误升级"

echo
echo "===== Mock 接口清单 ====="
for ep in "" "/$SN/battery?level=50" "/$SN/toggle-online" "/$SN/location" "/$SN/sos" "/$SN/fall"; do
  printf "  POST /api/v1/mock/devices%s\n" "$ep"
done
echo "  POST /api/v1/mock/devices/$SN/fall/{alertId}/cancel"

echo
echo "== 收尾：恢复演示数据（电量回满、清掉验证产生的告警） =="
curl -s --noproxy '*' -X POST "$BASE/api/v1/mock/devices/$SN/battery?level=85" > /dev/null
q "DELETE FROM $DB.alert_record WHERE alert_type IN ('SOS','FALL_DETECTED','LOW_BATTERY');"
"$REDIS" DEL "alert:battery:notified:$DEV_ID" > /dev/null 2>&1
echo "  电量已恢复为 $(q "SELECT battery FROM $DB.device WHERE device_sn='$SN';")%"

echo
if [ "$FAILED" = "0" ]; then echo "===== S4 验证全部通过 ====="; else echo "===== S4 验证存在失败项 ====="; fi
exit $FAILED

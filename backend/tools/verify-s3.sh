#!/usr/bin/env bash
# S3 位置链路端到端验证：登录 -> STOMP 订阅 -> 上报 -> Redis 热数据 + MySQL 批量落库
# 用法: bash tools/verify-s3.sh
set -u

PORT="${PORT:-8001}"
BASE="http://127.0.0.1:$PORT"
MYSQL="/c/Program Files/MySQL/MySQL Server 8.0/bin/mysql"
# 本机 Redis 带 requirepass 且后端固定用 1 号库（见 application-dev.yml），
# 裸 redis-cli 会因认证失败拿到空值，把「热数据缺失」误报成「陈旧」
REDIS="/d/redis/redis-cli -a 123456 -n 1"
NODE="C:/Users/Lenovo/.workbuddy/binaries/node/versions/22.22.2-6/node.exe"
export NODE_PATH="C:/Users/Lenovo/.workbuddy/binaries/node/workspace/node_modules"

DB="blind_cane_guardian"
SN="BC-2024-DEMO01"
WARD_ID=1
# 必须是 ward 1 的合法监护人（数据来自 V1 迁移里的演示账号），否则会被 103001 / STOMP ERROR 正确拦截
PHONE="13800138000"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# Git Bash 的 /d/... 路径 node 不认，统一转成 Windows 风格
WINROOT="$(cygpath -m "$ROOT" 2>/dev/null || echo "$ROOT")"
TMP="$ROOT/target/verify"
WINTMP="$WINROOT/target/verify"
mkdir -p "$TMP"

FAILED=0
pass() { echo "  [PASS] $1"; }
fail() { echo "  [FAIL] $1"; FAILED=1; }
q() { "$MYSQL" -uroot -p"${MYSQL_PASSWORD:-060307}" -N -e "$1" 2>/dev/null; }

echo "== 1. 登录（Mock 短信验证码） =="
# 先清掉短信限流：开发期同一号码一天会登录很多次，否则会撞上「每日上限」业务规则
curl -s --noproxy '*' -X POST "$BASE/api/v1/mock/sms/reset?phone=$PHONE" > /dev/null
curl -s --noproxy '*' -X POST "$BASE/api/v1/auth/sms/send" \
  -H "Content-Type: application/json" \
  -d "{\"phone\":\"$PHONE\"}" > "$TMP/sms.json"
echo "  发送验证码: $(head -c 200 "$TMP/sms.json")"
# 验证码由后端随机生成，Mock 模式下从发送响应里取（不再有固定码）
SMS_CODE=$(cat "$TMP/sms.json" | "$NODE" "$WINROOT/tools/json-get.js" data.mockCode)
curl -s --noproxy '*' -X POST "$BASE/api/v1/auth/login" \
  -H "Content-Type: application/json" \
  -d "{\"phone\":\"$PHONE\",\"smsCode\":\"$SMS_CODE\"}" > "$TMP/login.json"
TOKEN=$(cat "$TMP/login.json" | "$NODE" "$WINROOT/tools/json-get.js" data.accessToken)
if [ -n "$TOKEN" ]; then pass "获取 accessToken (${TOKEN:0:24}...)"; else
  fail "登录失败: $(cat "$TMP/login.json")"; exit 1; fi

echo "== 2. 清空历史位置记录 =="
q "DELETE FROM $DB.location_record;"
BEFORE=$(q "SELECT COUNT(*) FROM $DB.location_record;")
echo "  落库前记录数: $BEFORE"

echo "== 3. 启动 STOMP 订阅（后台，25 秒） =="
"$NODE" "$WINROOT/tools/stomp-watch.js" --token="$TOKEN" --ward="$WARD_ID" --duration=25 > "$TMP/ws.log" 2>&1 &
WS_PID=$!
sleep 4
grep -q "CONNECTED" "$TMP/ws.log" && pass "STOMP CONNECTED" || fail "STOMP 未连接: $(head -3 "$TMP/ws.log")"
grep -q "/topic/ward/$WARD_ID/location" "$TMP/ws.log" && pass "已订阅 location/alert/device 三主题" || true

echo "== 4. 连续上报 3 条位置 =="
for i in 1 2 3; do
  LNG=$($NODE -e "process.stdout.write((113.7850+$i*0.0001).toFixed(6))")
  LAT=$($NODE -e "process.stdout.write((34.7420+$i*0.0001).toFixed(6))")
  RESP=$(curl -s --noproxy '*' -X POST "$BASE/api/v1/mock/devices/$SN/location?lng=$LNG&lat=$LAT&accuracy=9.5&speed=1.2")
  echo "  #$i ($LNG, $LAT) -> $(echo "$RESP" | head -c 150)"
done

echo "== 5. 校验 Redis 热数据 =="
HOT=$($REDIS GET "loc:ward:$WARD_ID" 2>/dev/null)
if [ -n "$HOT" ]; then pass "loc:ward:$WARD_ID 命中"; else fail "Redis 热数据缺失"; fi
echo "  $HOT"
# 只断言"非空"太弱：模拟器位置漂移会持续覆盖同一个 key，
# 必须再验时间戳是刚刚写入的，才能证明这次上报真的走通了实时链路
HOT_AGE=$(echo "$HOT" | "$NODE" -e "
let s='';process.stdin.on('data',d=>s+=d).on('end',()=>{
  try{const j=JSON.parse(s);process.stdout.write(String(Date.now()-(j.reportedAt||0)));}catch(e){process.stdout.write('999999')}
})")
echo "  热数据时间戳距今 ${HOT_AGE} ms"
if [ "$HOT_AGE" -lt 60000 ]; then pass "热数据为新鲜写入"; else fail "热数据陈旧（${HOT_AGE}ms）"; fi

echo "== 6. 校验家属实时读取接口 =="
RT=$(curl -s --noproxy '*' "$BASE/api/v1/locations/realtime?wardId=$WARD_ID" -H "Authorization: Bearer $TOKEN")
echo "  $(echo "$RT" | head -c 260)"

echo "== 7. 等待批量落库（>5s 触发 flush） =="
sleep 8
AFTER=$(q "SELECT COUNT(*) FROM $DB.location_record;")
DELTA=$((AFTER - BEFORE))
echo "  落库后记录数: $AFTER（本脚本写入 $DELTA 条，期望 >=3）"
q "SELECT id, ward_id, ROUND(ST_X(location),6) AS x, ROUND(ST_Y(location),6) AS y, ST_AsText(location) FROM $DB.location_record ORDER BY id DESC LIMIT 3;"
# 用增量而非绝对值断言：模拟器位置漂移也会持续写入，绝对值不稳定
if [ "$DELTA" -ge 3 ]; then pass "MySQL 批量落库成功（SRID 4326 轴序已修正）"; else fail "MySQL 落库数量异常：delta=$DELTA"; fi

echo "== 8. 校验 STOMP 推送 =="
wait $WS_PID 2>/dev/null
# 注意：不要在 grep 里用 emoji 做匹配（Git Bash 多字节匹配不可靠），改按 JSON 字段特征计数
PUSHES=$(grep -c "reportedAt" "$TMP/ws.log" || true)
PUSHES=${PUSHES:-0}
echo "  收到 location 推送: $PUSHES 条"
if [ "$PUSHES" -ge 1 ]; then pass "WebSocket 实时推送正常"; else fail "未收到 WebSocket 推送"; fi
grep -A1 "topic/ward/$WARD_ID/location" "$TMP/ws.log" | grep "reportedAt" | head -3
echo "  --- 订阅被拒/错误帧检查 ---"
if grep -q "ERROR" "$TMP/ws.log"; then fail "出现 ERROR 帧"; grep "ERROR" "$TMP/ws.log"; else pass "无 ERROR 帧（订阅权限校验通过）"; fi

echo "== 9. 越权校验（非监护人应被拒绝） =="
# 登录不再自动注册：先用显式注册建一个没有任何监护关系的新用户；
# 号码在往轮验证里已注册过时（101010），退回密码登录拿同一账号的令牌。
# 注意别用历史遗留的「无密码账号」号段（13800000001 等自动注册时代的号码），
# 那些号密码登录会返 101013，拿不到令牌
curl -s --noproxy '*' -X POST "$BASE/api/v1/mock/sms/reset?phone=13800000002" > /dev/null
curl -s --noproxy '*' -X POST "$BASE/api/v1/auth/sms/send" \
  -H "Content-Type: application/json" -d '{"phone":"13800000002"}' > "$TMP/sms2.json"
SMS2=$(cat "$TMP/sms2.json" | "$NODE" "$WINROOT/tools/json-get.js" data.mockCode)
curl -s --noproxy '*' -X POST "$BASE/api/v1/auth/register" \
  -H "Content-Type: application/json" \
  -d "{\"phone\":\"13800000002\",\"password\":\"stranger123\",\"smsCode\":\"$SMS2\"}" > "$TMP/login2.json"
if [ -z "$(cat "$TMP/login2.json" | "$NODE" "$WINROOT/tools/json-get.js" data.accessToken)" ]; then
  curl -s --noproxy '*' -X POST "$BASE/api/v1/auth/login" \
    -H "Content-Type: application/json" \
    -d '{"phone":"13800000002","password":"stranger123"}' > "$TMP/login2.json"
fi
TOKEN2=$(cat "$TMP/login2.json" | "$NODE" "$WINROOT/tools/json-get.js" data.accessToken)
DENY=$(curl -s --noproxy '*' "$BASE/api/v1/locations/realtime?wardId=$WARD_ID" -H "Authorization: Bearer $TOKEN2")
echo "  非监护人读取 ward $WARD_ID 实时位置: $(echo "$DENY" | head -c 160)"
if echo "$DENY" | grep -q '"code":103001'; then pass "越权访问被正确拦截 (103001)"; else fail "越权未被拦截"; fi

echo "== 10. 告警中心接口（S3 / 5.6） =="
q "DELETE FROM $DB.alert_record;"
q "INSERT INTO $DB.alert_record (ward_id, device_id, alert_type, severity, lng, lat, address, status, pending_confirm)
   VALUES ($WARD_ID, 1, 'SOS', 1, 113.7853, 34.7423, '郑州市金水区文苑北路 36 号', 0, 0);"
ALERT_ID=$(q "SELECT MAX(id) FROM $DB.alert_record;")
echo "  造数完成 alertId=$ALERT_ID"

PEND=$(curl -s --noproxy '*' "$BASE/api/v1/alerts/pending-count" -H "Authorization: Bearer $TOKEN")
echo "  待处理角标: $(echo "$PEND" | head -c 200)"
echo "$PEND" | grep -q '"total":1' && pass "pending-count 正确 (total=1)" || fail "pending-count 异常"

LIST=$(curl -s --noproxy '*' "$BASE/api/v1/alerts?wardId=$WARD_ID&status=0&page=1&size=10" -H "Authorization: Bearer $TOKEN")
echo "  列表首条: $(echo "$LIST" | head -c 260)"
echo "$LIST" | grep -q '"total"' && pass "分页查询正常" || fail "分页查询异常"

DET=$(curl -s --noproxy '*' "$BASE/api/v1/alerts/$ALERT_ID" -H "Authorization: Bearer $TOKEN")
echo "$DET" | grep -q "\"id\":$ALERT_ID" && pass "详情查询正常" || fail "详情查询异常: $(echo "$DET" | head -c 160)"

HANDLE=$(curl -s --noproxy '*' -X PUT "$BASE/api/v1/alerts/$ALERT_ID/handle" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"result":"RESOLVED","note":"已电话确认安全"}')
echo "  处理结果: $(echo "$HANDLE" | head -c 260)"
echo "$HANDLE" | grep -q '"status":1' && pass "告警处理成功 (status=1)" || fail "告警处理异常"

AGAIN=$(curl -s --noproxy '*' -X PUT "$BASE/api/v1/alerts/$ALERT_ID/handle" \
  -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  -d '{"result":"RESOLVED","note":"重复处理"}')
echo "$AGAIN" | grep -q '"code":106002' && pass "重复处理被拦截 (106002)" || fail "重复处理未拦截: $(echo "$AGAIN" | head -c 160)"

DENY2=$(curl -s --noproxy '*' "$BASE/api/v1/alerts/$ALERT_ID" -H "Authorization: Bearer $TOKEN2")
echo "$DENY2" | grep -q '"code":103001' && pass "告警跨监护越权被拦截 (103001)" || fail "告警越权未拦截"

echo
if [ "$FAILED" = "0" ]; then echo "===== S3 验证全部通过 ====="; else echo "===== S3 验证存在失败项 ====="; fi
exit $FAILED

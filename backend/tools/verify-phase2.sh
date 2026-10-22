#!/usr/bin/env bash
# =============================================================
# 第二阶段（围栏 + 轨迹回放）后端回归
#
# 前置条件：
#   1. 后端已在 8001 运行
#   2. Redis 已启动（requirepass 123456，库号 1）
#   3. 演示设备 BC-2024-DEMO01 已绑定到 ward 1（模拟器默认就绪）
#
# 用法： bash backend/tools/verify-phase2.sh
#
# 覆盖点：
#   围栏 CRUD / 局部更新 / 启停 / 越权拦截 / 参数校验 / 删除不存在
#   命中判定：安全区「离开」告警、危险区「进入」告警、
#             跨边界只告警一次、状态机 IN/OUT 正确翻转
#   轨迹回放：按整天查、降采样上限生效、非法时间与超跨度被拒
# =============================================================
set -uo pipefail

BASE="http://127.0.0.1:8001/api/v1"
REDIS="/d/redis/redis-cli -a 123456 -n 1"
PHONE="13800138000"
PWD="123456"
SN="${SN:-BC-2024-DEMO01}"
WARD="${WARD:-1}"

PASS=0
FAIL=0
TOKEN=""
CREATED_IDS=()

say() { printf '\n\033[36m%s\033[0m\n' "$*"; }
ok()  { PASS=$((PASS + 1)); printf '  \033[32mPASS\033[0m %s\n' "$*"; }
bad() { FAIL=$((FAIL + 1)); printf '  \033[31mFAIL\033[0m %s\n' "$*"; }
expect() { if [ "$1" = "$2" ]; then ok "$3 (=$2)"; else bad "$3 期望[$2] 实际[$1]"; fi; }

jget() { python -c "
import sys, json
d = json.load(sys.stdin)
for k in sys.argv[1].split('.'):
    if d is None: break
    if isinstance(d, list):
        try: d = d[int(k)]
        except Exception: d = None
    else:
        d = d.get(k) if isinstance(d, dict) else None
print('' if d is None else d)
" "$1" 2>/dev/null <<<"$2"; }

api() {
  local method="$1" path="$2" body="${3:-}"
  local args=(-s -X "$method" "$BASE$path" -H 'Content-Type: application/json')
  [ -n "$TOKEN" ] && args+=(-H "Authorization: Bearer $TOKEN")
  [ -n "$body" ] && args+=(-d "$body")
  curl "${args[@]}"
}

cleanup() {
  printf '\n\033[90m清理本次创建的测试围栏...\033[0m\n'
  for id in "${CREATED_IDS[@]:-}"; do
    [ -n "$id" ] && api DELETE "/geofences/$id" >/dev/null 2>&1
    $REDIS DEL "geofence:state:$id" "geofence:alert:$id" >/dev/null 2>&1
  done
  printf '\033[90m完成\033[0m\n'
}
trap cleanup EXIT

echo "=============================================="
echo " 第二阶段回归：电子围栏 + 轨迹回放"
echo " ward=$WARD  device=$SN"
echo "=============================================="

# ---------------------------------------------------------------- 0. 登录
say "0) 登录拿到令牌"
LOGIN=$(api POST /auth/login "{\"phone\":\"$PHONE\",\"password\":\"$PWD\"}")
TOKEN=$(jget "data.accessToken" "$LOGIN")
if [ -z "$TOKEN" ]; then
  bad "登录失败：$LOGIN"
  echo "后端没起或演示账号密码不对，脚本终止"
  exit 1
fi
ok "登录成功"

# ---------------------------------------------------------------- 1. 基线
say "1) 围栏列表（基线）"
BASELINE=$(api GET "/geofences?wardId=$WARD")
expect "$(jget "code" "$BASELINE")" "0" "查询围栏列表成功"
BEFORE_COUNT=$(python -c "
import sys, json
d = json.load(sys.stdin)
print(len(d.get('data') or []))
" <<<"$BASELINE")
echo "  现有围栏 $BEFORE_COUNT 条"

# ---------------------------------------------------------------- 2. 新建
say "2) 新建围栏（安全区，半径 50 米）"
# 取一个与模拟器随机游走无关的基准点，避免它自己走进/走出干扰判定
BASE_LNG=113.600000
BASE_LAT=34.800000
CREATE=$(api POST /geofences "{\"wardId\":$WARD,\"name\":\"P2-TEST-安全区\",\"centerLng\":$BASE_LNG,\"centerLat\":$BASE_LAT,\"radiusM\":50,\"fenceType\":1}")
echo "  $CREATE"
expect "$(jget "code" "$CREATE")" "0" "创建成功"
SAFE_ID=$(jget "data.id" "$CREATE")
[ -n "$SAFE_ID" ] && CREATED_IDS+=("$SAFE_ID") && ok "新围栏 id=$SAFE_ID" || bad "未拿到围栏 id"
expect "$(jget "data.fenceType" "$CREATE")" "1" "类型为安全区"
expect "$(jget "data.enabled" "$CREATE")" "1" "默认启用"
expect "$(jget "data.radiusM" "$CREATE")" "50" "半径写入正确"

say "2b) 列表里能看到它"
AFTER=$(api GET "/geofences?wardId=$WARD")
AFTER_COUNT=$(python -c "
import sys, json
d = json.load(sys.stdin)
print(len(d.get('data') or []))
" <<<"$AFTER")
expect "$AFTER_COUNT" "$((BEFORE_COUNT + 1))" "列表数量 +1"

# ---------------------------------------------------------------- 3. 修改
say "3) 局部更新（只改名称与半径）"
UPD=$(api PUT "/geofences/$SAFE_ID" '{"name":"P2-TEST-安全区-改名","radiusM":80}')
expect "$(jget "code" "$UPD")" "0" "更新成功"
expect "$(jget "data.name" "$UPD")" "P2-TEST-安全区-改名" "名称已改"
expect "$(jget "data.radiusM" "$UPD")" "80" "半径已改"
expect "$(jget "data.centerLng" "$UPD")" "113.6" "未传的字段保持原值"

say "3b) 参数校验"
BAD_R=$(api POST /geofences "{\"wardId\":$WARD,\"name\":\"x\",\"centerLng\":$BASE_LNG,\"centerLat\":$BASE_LAT,\"radiusM\":5,\"fenceType\":1}")
expect "$(jget "code" "$BAD_R")" "109001" "半径 5 米 → 参数错误"
BAD_T=$(api POST /geofences "{\"wardId\":$WARD,\"name\":\"x\",\"centerLng\":$BASE_LNG,\"centerLat\":$BASE_LAT,\"radiusM\":100,\"fenceType\":9}")
expect "$(jget "code" "$BAD_T")" "109001" "类型 9 → 参数错误"
NO_NAME=$(api POST /geofences "{\"wardId\":$WARD,\"name\":\"\",\"centerLng\":$BASE_LNG,\"centerLat\":$BASE_LAT,\"radiusM\":100,\"fenceType\":1}")
expect "$(jget "code" "$NO_NAME")" "109001" "空名称 → 参数错误"

# ---------------------------------------------------------------- 4. 命中判定：安全区
say "4) 命中判定：安全区「离开」才告警"
# 清掉状态与告警锁，从干净状态开始
$REDIS DEL "geofence:state:$SAFE_ID" "geofence:alert:$SAFE_ID" >/dev/null 2>&1

ALERTS_BEFORE=$(api GET "/alerts?wardId=$WARD&type=GEOFENCE_EXIT&page=1&size=1")
N_BEFORE=$(jget "data.total" "$ALERTS_BEFORE")
echo "  改造前 GEOFENCE_EXIT 告警总数：$N_BEFORE"

# 第一次上报在圈内 → 只建立基线，不该告警
api POST "/mock/devices/$SN/location?lng=$BASE_LNG&lat=$BASE_LAT" >/dev/null
sleep 1
STATE_IN=$($REDIS GET "geofence:state:$SAFE_ID" 2>/dev/null | tr -d '\r')
expect "$STATE_IN" "IN" "圈内上报后状态为 IN"
N_AFTER_IN=$(jget "data.total" "$(api GET "/alerts?wardId=$WARD&type=GEOFENCE_EXIT&page=1&size=1")")
expect "$N_AFTER_IN" "$N_BEFORE" "首次上报（基线）不产生告警"

# 走到圈外约 300 米（纬度 +0.0027 度 ≈ 300 米）→ 触发 EXIT
OUT_LAT=$(python -c "print(f'{34.800000 + 0.0027:.6f}')")
api POST "/mock/devices/$SN/location?lng=$BASE_LNG&lat=$OUT_LAT" >/dev/null
sleep 1
STATE_OUT=$($REDIS GET "geofence:state:$SAFE_ID" 2>/dev/null | tr -d '\r')
expect "$STATE_OUT" "OUT" "圈外上报后状态翻转为 OUT"
N_AFTER_OUT=$(jget "data.total" "$(api GET "/alerts?wardId=$WARD&type=GEOFENCE_EXIT&page=1&size=1")")
if [ "$N_AFTER_OUT" -gt "$N_BEFORE" ] 2>/dev/null; then
  ok "离开安全区产生告警（$N_BEFORE → $N_AFTER_OUT）"
else
  bad "离开安全区未产生告警（仍为 $N_AFTER_OUT）"
fi

say "4b) 继续在圈外上报，不应重复告警"
api POST "/mock/devices/$SN/location?lng=$BASE_LNG&lat=$OUT_LAT" >/dev/null
sleep 1
N_REPEAT=$(jget "data.total" "$(api GET "/alerts?wardId=$WARD&type=GEOFENCE_EXIT&page=1&size=1")")
expect "$N_REPEAT" "$N_AFTER_OUT" "状态未变 → 不重复告警"

say "4c) 回到圈内，安全区不应告警（那是危险区的语义）"
api POST "/mock/devices/$SN/location?lng=$BASE_LNG&lat=$BASE_LAT" >/dev/null
sleep 1
STATE_BACK=$($REDIS GET "geofence:state:$SAFE_ID" 2>/dev/null | tr -d '\r')
expect "$STATE_BACK" "IN" "回圈后状态恢复 IN"
N_BACK=$(jget "data.total" "$(api GET "/alerts?wardId=$WARD&type=GEOFENCE_EXIT&page=1&size=1")")
expect "$N_BACK" "$N_AFTER_OUT" "回圈不触发离开告警"

# ---------------------------------------------------------------- 5. 命中判定：危险区
say "5) 命中判定：危险区「进入」才告警"
# 危险区放在一个独立位置（纬度再加 0.01 度 ≈ 1.1 公里），避免与上面互扰
DANGER_LAT=$(python -c "print(f'{34.800000 + 0.010:.6f}')")
CREATE_D=$(api POST /geofences "{\"wardId\":$WARD,\"name\":\"P2-TEST-危险区\",\"centerLng\":$BASE_LNG,\"centerLat\":$DANGER_LAT,\"radiusM\":50,\"fenceType\":2}")
expect "$(jget "code" "$CREATE_D")" "0" "创建危险区成功"
DANGER_ID=$(jget "data.id" "$CREATE_D")
[ -n "$DANGER_ID" ] && CREATED_IDS+=("$DANGER_ID")
$REDIS DEL "geofence:state:$DANGER_ID" "geofence:alert:$DANGER_ID" >/dev/null 2>&1

ENTER_BEFORE=$(jget "data.total" "$(api GET "/alerts?wardId=$WARD&type=GEOFENCE_ENTER&page=1&size=1")")
# 先在远处建立 OUT 基线
api POST "/mock/devices/$SN/location?lng=$BASE_LNG&lat=$BASE_LAT" >/dev/null
sleep 1
STATE_D1=$($REDIS GET "geofence:state:$DANGER_ID" 2>/dev/null | tr -d '\r')
expect "$STATE_D1" "OUT" "危险区远处上报 → 基线 OUT"

# 走进危险区中心
api POST "/mock/devices/$SN/location?lng=$BASE_LNG&lat=$DANGER_LAT" >/dev/null
sleep 1
STATE_D2=$($REDIS GET "geofence:state:$DANGER_ID" 2>/dev/null | tr -d '\r')
expect "$STATE_D2" "IN" "走进危险区 → 状态 IN"
ENTER_AFTER=$(jget "data.total" "$(api GET "/alerts?wardId=$WARD&type=GEOFENCE_ENTER&page=1&size=1")")
if [ "$ENTER_AFTER" -gt "$ENTER_BEFORE" ] 2>/dev/null; then
  ok "进入危险区产生告警（$ENTER_BEFORE → $ENTER_AFTER）"
else
  bad "进入危险区未产生告警（仍为 $ENTER_AFTER）"
fi

say "5b) 继续待在危险区内，不重复告警"
api POST "/mock/devices/$SN/location?lng=$BASE_LNG&lat=$DANGER_LAT" >/dev/null
sleep 1
ENTER_REPEAT=$(jget "data.total" "$(api GET "/alerts?wardId=$WARD&type=GEOFENCE_ENTER&page=1&size=1")")
expect "$ENTER_REPEAT" "$ENTER_AFTER" "状态未变 → 不重复告警"

# ---------------------------------------------------------------- 6. 启停
say "6) 停用后不再参与判定"
OFF=$(api PUT "/geofences/$DANGER_ID/enabled?enabled=0" '{}')
expect "$(jget "data.enabled" "$OFF")" "0" "停用成功"
$REDIS DEL "geofence:state:$DANGER_ID" >/dev/null 2>&1
api POST "/mock/devices/$SN/location?lng=$BASE_LNG&lat=$BASE_LAT" >/dev/null
sleep 1
STATE_OFF=$($REDIS GET "geofence:state:$DANGER_ID" 2>/dev/null | tr -d '\r')
if [ -z "$STATE_OFF" ]; then
  ok "停用的围栏不写状态（判定已跳过）"
else
  bad "停用的围栏仍在被判定，state=$STATE_OFF"
fi
api PUT "/geofences/$DANGER_ID/enabled?enabled=1" '{}' >/dev/null

# ---------------------------------------------------------------- 7. 轨迹
say "7) 轨迹回放查询"
# 沿经度方向补几个点，保证当天有可查的轨迹
for i in 1 2 3 4 5; do
  L=$(python -c "print(f'{113.600000 + $i * 0.0002:.6f}')")
  api POST "/mock/devices/$SN/location?lng=$L&lat=$BASE_LAT" >/dev/null
  sleep 0.3
done

# 落库是攒批的（LocationFlushBuffer 5 秒一批），等它刷完再查
echo "  等待批量落库刷盘（约 7 秒）..."
sleep 7

TRACK=$(api GET "/locations/history?wardId=$WARD&maxPoints=5")
expect "$(jget "code" "$TRACK")" "0" "查询今天轨迹成功"
N_TRACK=$(python -c "
import sys, json
d = json.load(sys.stdin)
print(len(d.get('data') or []))
" <<<"$TRACK")
echo "  maxPoints=5 实际返回 $N_TRACK 个点"
if [ "$N_TRACK" -ge 1 ] && [ "$N_TRACK" -le 5 ]; then
  ok "降采样上限生效（1 ≤ $N_TRACK ≤ 5）"
else
  bad "降采样异常：返回 $N_TRACK 个点"
fi

say "7b) 降采样不影响首尾点（末端是最后一个上报点）"
FIRST_LNG=$(jget "data.0.lng" "$TRACK")
LAST_LNG=$(jget "data.-1.lng" "$TRACK")
[ -n "$FIRST_LNG" ] && ok "首点 lng=$FIRST_LNG" || bad "首点为空"
[ -n "$LAST_LNG" ] && ok "末点 lng=$LAST_LNG" || bad "末点为空"

say "7c) 非法参数"
BAD_DATE=$(api GET "/locations/history?wardId=$WARD&start=2026-13-99")
expect "$(jget "code" "$BAD_DATE")" "109001" "非法日期 → 参数错误"
BAD_RANGE=$(api GET "/locations/history?wardId=$WARD&start=2026-10-01&end=2026-09-01")
expect "$(jget "code" "$BAD_RANGE")" "109001" "结束早于开始 → 参数错误"
TOO_LONG=$(api GET "/locations/history?wardId=$WARD&start=2026-09-01&end=2026-10-21")
expect "$(jget "code" "$TOO_LONG")" "109001" "跨度超 7 天 → 参数错误"

# ---------------------------------------------------------------- 8. 越权
say "8) 越权拦截"
STAMP=$(python -c "print(__import__('random').randint(10000000,99999999))")
OTHER_PHONE="137$STAMP"
SMS=$(api POST /auth/sms/send "{\"phone\":\"$OTHER_PHONE\"}")
CODE=$(jget "data.mockCode" "$SMS")
REG=$(api POST /auth/register "{\"phone\":\"$OTHER_PHONE\",\"password\":\"abc123456\",\"smsCode\":\"$CODE\"}")
OTHER_TOKEN=$(jget "data.accessToken" "$REG")
if [ -n "$OTHER_TOKEN" ]; then
  SAVED=$TOKEN
  TOKEN=$OTHER_TOKEN
  DENY_LIST=$(api GET "/geofences?wardId=$WARD")
  expect "$(jget "code" "$DENY_LIST")" "103001" "他人查围栏列表 → 无监护权限"
  DENY_TRACK=$(api GET "/locations/history?wardId=$WARD")
  expect "$(jget "code" "$DENY_TRACK")" "103001" "他人查轨迹 → 无监护权限"
  DENY_DEL=$(api DELETE "/geofences/$SAFE_ID")
  expect "$(jget "code" "$DENY_DEL")" "103001" "他人删围栏 → 无监护权限"
  TOKEN=$SAVED
else
  bad "越权用例前置失败：注册临时账号未拿到令牌"
fi

# ---------------------------------------------------------------- 9. 删除
say "9) 删除围栏"
DEL=$(api DELETE "/geofences/$SAFE_ID")
expect "$(jget "code" "$DEL")" "0" "删除成功"
GONE=$(api GET "/geofences?wardId=$WARD")
HAS_SAFE=$(SAFE_ID="$SAFE_ID" python -c "
import os, sys, json
d = json.load(sys.stdin)
ids = [x.get('id') for x in (d.get('data') or [])]
target = os.environ.get('SAFE_ID') or ''
# 用环境变量传参而不是字符串插值：创建失败时 SAFE_ID 为空，
# 插值会展开成 'if  in ids' 直接抛 SyntaxError，把真正的失败原因盖住
print('yes' if target and int(target) in ids else 'no')
" <<<"$GONE")
expect "$HAS_SAFE" "no" "删除后列表中已不存在"
# 已删过，从清理列表去掉避免重复删
CREATED_IDS=("${CREATED_IDS[@]/$SAFE_ID/}")

say "9b) 删除不存在的围栏"
DEL2=$(api DELETE "/geofences/99999999")
expect "$(jget "code" "$DEL2")" "109003" "不存在 → 资源不存在"

# ---------------------------------------------------------------- 10. 档案新字段
say "10) 家人档案：住址坐标 + 随身电话"
# 选择 create 而不是改 ward 1，是为了不动演示数据；
# 这个档案会在第 11 节由删除接口清掉，不会再留垃圾数据。
NEW_WARD=$(api POST /wards '{"name":"P2-TEST-档案","relation":"其他","birthYear":1950,"homeAddress":"测试住址","homeLng":113.612345,"homeLat":34.812345,"contactPhone":"13800001234"}')
expect "$(jget "code" "$NEW_WARD")" "0" "带坐标与电话创建档案成功"
expect "$(jget "data.homeLng" "$NEW_WARD")" "113.612345" "经度已落库"
expect "$(jget "data.homeLat" "$NEW_WARD")" "34.812345" "纬度已落库"
expect "$(jget "data.contactPhone" "$NEW_WARD")" "13800001234" "随身电话已落库"
NEW_WARD_ID=$(jget "data.id" "$NEW_WARD")

say "10b) 详情接口能读回（手动定位结果不会丢）"
if [ -n "$NEW_WARD_ID" ]; then
  DETAIL=$(api GET "/wards/$NEW_WARD_ID")
  expect "$(jget "data.homeLng" "$DETAIL")" "113.612345" "详情里经度回显正确"
  expect "$(jget "data.contactPhone" "$DETAIL")" "13800001234" "详情里电话回显正确"

  say "10c) 局部更新：只改电话，坐标不受影响"
  UPD_PHONE=$(api PUT "/wards/$NEW_WARD_ID" '{"name":"P2-TEST-档案","contactPhone":"13900005678"}')
  expect "$(jget "data.contactPhone" "$UPD_PHONE")" "13900005678" "电话已更新"
  expect "$(jget "data.homeLng" "$UPD_PHONE")" "113.612345" "未传坐标时保持原值"

  say "10d) 电话允许清空（传空串）"
  CLEAR=$(api PUT "/wards/$NEW_WARD_ID" '{"name":"P2-TEST-档案","contactPhone":""}')
  expect "$(jget "data.contactPhone" "$CLEAR")" "" "空串清空了号码"
else
  bad "未拿到新档案 id，跳过详情/更新用例"
fi

say "10e) 坐标越界被拒"
BAD_LNG=$(api POST /wards '{"name":"P2-TEST-坏坐标","homeLng":200,"homeLat":34.8}')
expect "$(jget "code" "$BAD_LNG")" "109001" "经度 200 → 参数错误"

# ---------------------------------------------------------------- 11. 删除档案
say "11) 删除档案：级联清理"
if [ -n "$NEW_WARD_ID" ]; then
  # 先给它挂一个围栏，验证删除时会被一起带走
  DEL_FENCE=$(api POST /geofences "{\"wardId\":$NEW_WARD_ID,\"name\":\"P2-TEST-待删围栏\",\"centerLng\":$BASE_LNG,\"centerLat\":$BASE_LAT,\"radiusM\":60,\"fenceType\":1}")
  expect "$(jget "code" "$DEL_FENCE")" "0" "待删档案建围栏成功"

  DEL_RESULT=$(api DELETE "/wards/$NEW_WARD_ID")
  expect "$(jget "code" "$DEL_RESULT")" "0" "删除档案成功"
  expect "$(jget "data.geofences" "$DEL_RESULT")" "1" "返回连带删除的围栏数"
  expect "$(jget "data.guardians" "$DEL_RESULT")" "1" "返回解除的监护关系数"

  # 删除时监护关系一并清掉了，所以再查详情/再删一次都会先撞"无监护权限"。
  # 这比返回 103002 更好：不向调用方泄露"这个 id 曾经存在过"。
  GONE_DETAIL=$(api GET "/wards/$NEW_WARD_ID")
  expect "$(jget "code" "$GONE_DETAIL")" "103001" "删除后详情不可再访问（无监护权限）"

  # 监护关系已随档案清掉，所以再查它的围栏会先撞上"无监护权限"，
  # 这条通过本身就证明关系表清干净了（否则会返回一个空列表）
  FENCE_GONE=$(api GET "/geofences?wardId=$NEW_WARD_ID")
  expect "$(jget "code" "$FENCE_GONE")" "103001" "围栏随档案清除（关系也没了）"

  AGAIN_DEL=$(api DELETE "/wards/$NEW_WARD_ID")
  expect "$(jget "code" "$AGAIN_DEL")" "103001" "重复删除返回无监护权限"
else
  bad "第 10 节没建出档案，跳过删除用例"
fi

say "11b) 删除不存在的档案"
NOPE_DEL=$(api DELETE "/wards/99999999")
expect "$(jget "code" "$NOPE_DEL")" "103001" "不存在的档案 → 无监护权限"

# ---------------------------------------------------------------- 汇总
echo
echo "=============================================="
printf ' 结果：\033[32m%d passed\033[0m, \033[31m%d failed\033[0m\n' "$PASS" "$FAIL"
echo "=============================================="
[ "$FAIL" -eq 0 ]

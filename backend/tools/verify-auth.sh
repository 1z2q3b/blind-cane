#!/usr/bin/env bash
# 登录 / 注册功能回归测试
#
# 前置条件：
#   1. 后端已在 8001 端口启动（Mock 短信模式，simulator.enabled=true）
#   2. Redis 已启动且带 requirepass（D:/redis/redis.windows.conf），库号 1
#
# 用法： bash backend/tools/verify-auth.sh
#
# 覆盖点：
#   发送验证码（随机 6 位 / Redis 落库 / TTL / 60 秒间隔）
#   注册（成功 / 验证码一次性 / 重复注册 / 密码格式 / 缺验证码）
#   密码登录（成功 / 密码错误）
#   验证码登录（成功 / 一次性 / 码错误）
#   方式二选一（同时传 / 都不传）
#   存量无密码账号（101013）
#   令牌可用性、刷新、登出后失效

set -uo pipefail

BASE="http://127.0.0.1:8001/api/v1"
REDIS="/d/redis/redis-cli -a 123456 -n 1"
PROTECTED="$BASE/wards"
PASS=0
FAIL=0

say() { printf '\n\033[36m%s\033[0m\n' "$*"; }
ok()  { PASS=$((PASS + 1)); printf '  \033[32mPASS\033[0m %s\n' "$*"; }
bad() { FAIL=$((FAIL + 1)); printf '  \033[31mFAIL\033[0m %s\n' "$*"; }

# 断言：$1=实际  $2=期望  $3=用例名
expect() {
  if [ "$1" = "$2" ]; then ok "$3 (=$2)"; else bad "$3 期望[$2] 实际[$1]"; fi
}

jget() { python -c "
import sys, json
d = json.load(sys.stdin)
for k in sys.argv[1].split('.'):
    if d is None: break
    d = d.get(k) if isinstance(d, dict) else None
print('' if d is None else d)
" "$1" 2>/dev/null <<<"$2"; }

post() {
  local path="$1" body="${2:-}"
  if [ -z "$body" ]; then body='{}'; fi
  curl -s -X POST "$BASE$path" -H 'Content-Type: application/json' -d "$body"
}

# 取本轮全新手机号，避免历史数据干扰每日计数与「已注册」判定
STAMP=$(python -c "print(__import__('random').randint(10000000,99999999))")
PHONE="139${STAMP}"
NEWCOMER="138${STAMP}"

echo "=============================================="
echo " 登录 / 注册功能测试"
echo " 主号码: $PHONE   副号码: $NEWCOMER"
echo "=============================================="

# ---------------------------------------------------------------- 1. 发送验证码
say "1) 发送验证码"
SEND=$(post /auth/sms/send "{\"phone\":\"$PHONE\"}")
echo "  $SEND"
CODE=$(jget "data.mockCode" "$SEND")

expect "$(jget "code" "$SEND")" "0" "发送验证码成功"
if [ ${#CODE} -eq 6 ] && [ -z "$(echo "$CODE" | tr -d '0-9')" ]; then
  ok "验证码为 6 位纯数字：$CODE"
else
  bad "验证码格式异常：'$CODE'"
fi
expect "$(jget "data.mock" "$SEND")" "True" "Mock 模式回显 mockCode"
expect "$(jget "data.expireSeconds" "$SEND")" "300" "有效期 300 秒"

say "1b) 验证码写入 Redis（库 1，带 TTL）"
RAW=$($REDIS GET "auth:sms:code:$PHONE" 2>/dev/null | tr -d '\r')
TTL=$($REDIS TTL "auth:sms:code:$PHONE" 2>/dev/null | tr -d '\r')
expect "$RAW" "$CODE" "Redis 中验证码与响应一致"
if [ -n "$TTL" ] && [ "$TTL" -gt 0 ] 2>/dev/null; then
  ok "验证码 TTL=${TTL}s（应 ≤300）"
else
  bad "TTL 异常：[$TTL]"
fi

say "1c) 60 秒内重复发送应被拦截"
AGAIN=$(post /auth/sms/send "{\"phone\":\"$PHONE\"}")
echo "  $AGAIN"
expect "$(jget "code" "$AGAIN")" "101005" "重复发送 → 发送过频"

# ---------------------------------------------------------------- 2. 未注册号码
say "2) 未注册号码登录"
NOACC=$(post /auth/login "{\"phone\":\"$PHONE\",\"smsCode\":\"123456\"}")
echo "  $NOACC"
expect "$(jget "code" "$NOACC")" "101011" "未注册 → 账号不存在（不再自动注册）"

# ---------------------------------------------------------------- 3. 注册
say "3) 注册（手机号 + 密码 + 验证码）"
REG=$(post /auth/register "{\"phone\":\"$PHONE\",\"password\":\"abc123456\",\"smsCode\":\"$CODE\"}")
echo "  $REG"
expect "$(jget "code" "$REG")" "0" "注册成功"
TOKEN_R=$(jget "data.accessToken" "$REG")
REFRESH_R=$(jget "data.refreshToken" "$REG")
expect "$(jget "data.tokenType" "$REG")" "Bearer" "tokenType = Bearer"
expect "$(jget "data.expiresIn" "$REG")" "7200" "accessToken 有效期 7200 秒"
[ -n "$TOKEN_R" ] && ok "直接下发 accessToken（长度 ${#TOKEN_R}）" || bad "未拿到 accessToken"
[ -n "$REFRESH_R" ] && ok "直接下发 refreshToken（长度 ${#REFRESH_R}）" || bad "未拿到 refreshToken"
expect "$(jget "data.userInfo.phone" "$REG")" "$PHONE" "返回手机号正确"
expect "$(jget "data.userInfo.nickname" "$REG")" "家属${PHONE: -4}" "默认昵称取手机尾号"
# 注意：不能用 UID 作变量名——bash 里 UID 是只读内建变量
USER_ID=$(jget "data.userInfo.id" "$REG")
[ -n "$USER_ID" ] && ok "新用户 id=$USER_ID" || bad "未拿到用户 id"

say "3b) 同一验证码不可重复使用"
REUSE=$(post /auth/register "{\"phone\":\"$PHONE\",\"password\":\"abc123456\",\"smsCode\":\"$CODE\"}")
echo "  $REUSE"
expect "$(jget "code" "$REUSE")" "101002" "已消费的验证码 → 已过期"

say "3c) 重复注册同一手机号"
$REDIS DEL "auth:sms:interval:$PHONE" >/dev/null 2>&1
RE2=$(post /auth/sms/send "{\"phone\":\"$PHONE\"}")
CODE3=$(jget "data.mockCode" "$RE2")
DUP=$(post /auth/register "{\"phone\":\"$PHONE\",\"password\":\"abc123456\",\"smsCode\":\"$CODE3\"}")
echo "  $DUP"
expect "$(jget "code" "$DUP")" "101010" "重复注册 → 手机号已注册"

say "3d) 注册参数校验"
BADPWD=$(post /auth/register "{\"phone\":\"$NEWCOMER\",\"password\":\"123\",\"smsCode\":\"123456\"}")
expect "$(jget "code" "$BADPWD")" "109001" "密码 3 位 → 参数错误"
NOCODE=$(post /auth/register "{\"phone\":\"$NEWCOMER\",\"password\":\"abc123456\"}")
expect "$(jget "code" "$NOCODE")" "109001" "缺验证码 → 参数错误"
BADPHONE=$(post /auth/register "{\"phone\":\"12345\",\"password\":\"abc123456\",\"smsCode\":\"123456\"}")
expect "$(jget "code" "$BADPHONE")" "109001" "手机号格式非法 → 参数错误"

# ---------------------------------------------------------------- 4. 密码登录
say "4) 密码登录"
LP=$(post /auth/login "{\"phone\":\"$PHONE\",\"password\":\"abc123456\"}")
echo "  $(jget "message" "$LP")"
expect "$(jget "code" "$LP")" "0" "密码登录成功"
TOKEN_P=$(jget "data.accessToken" "$LP")
[ -n "$TOKEN_P" ] && ok "下发 accessToken" || bad "未拿到 token"

say "4b) 密码错误"
LB=$(post /auth/login "{\"phone\":\"$PHONE\",\"password\":\"wrong9999\"}")
echo "  $LB"
expect "$(jget "code" "$LB")" "101012" "密码错误 → 101012"

say "4c) 密码可重复使用（BCrypt 哈希正确落库）"
LP2=$(post /auth/login "{\"phone\":\"$PHONE\",\"password\":\"abc123456\"}")
expect "$(jget "code" "$LP2")" "0" "二次密码登录仍成功"

# ---------------------------------------------------------------- 5. 验证码登录
say "5) 验证码登录"
$REDIS DEL "auth:sms:interval:$PHONE" >/dev/null 2>&1
RE3=$(post /auth/sms/send "{\"phone\":\"$PHONE\"}")
CODE4=$(jget "data.mockCode" "$RE3")
LS=$(post /auth/login "{\"phone\":\"$PHONE\",\"smsCode\":\"$CODE4\"}")
echo "  验证码 $CODE4 → $(jget "message" "$LS")"
expect "$(jget "code" "$LS")" "0" "验证码登录成功"
TOKEN_S=$(jget "data.accessToken" "$LS")
[ -n "$TOKEN_S" ] && ok "下发 accessToken" || bad "未拿到 token"

say "5b) 验证码一次性消费"
LR=$(post /auth/login "{\"phone\":\"$PHONE\",\"smsCode\":\"$CODE4\"}")
expect "$(jget "code" "$LR")" "101002" "同一验证码二次使用 → 已过期"

say "5c) 验证码错误"
$REDIS DEL "auth:sms:interval:$PHONE" >/dev/null 2>&1
RE4=$(post /auth/sms/send "{\"phone\":\"$PHONE\"}")
CODE5=$(jget "data.mockCode" "$RE4")
WRONG="000000"; [ "$CODE5" = "000000" ] && WRONG="135790"
LW=$(post /auth/login "{\"phone\":\"$PHONE\",\"smsCode\":\"$WRONG\"}")
echo "  正确码 $CODE5 / 提交 $WRONG → $(jget "message" "$LW")"
expect "$(jget "code" "$LW")" "101001" "验证码错误 → 101001"

say "5d) 输错后验证码仍可用（不因一次输错被作废）"
LOK=$(post /auth/login "{\"phone\":\"$PHONE\",\"smsCode\":\"$CODE5\"}")
expect "$(jget "code" "$LOK")" "0" "改回正确码即可登录"

# ---------------------------------------------------------------- 6. 二选一
say "6) 登录方式二选一"
BOTH=$(post /auth/login "{\"phone\":\"$PHONE\",\"smsCode\":\"$CODE5\",\"password\":\"abc123456\"}")
echo "  $BOTH"
expect "$(jget "code" "$BOTH")" "101014" "同时传 → 101014"
NEITHER=$(post /auth/login "{\"phone\":\"$PHONE\"}")
echo "  $NEITHER"
expect "$(jget "code" "$NEITHER")" "101014" "都不传 → 101014"

# ---------------------------------------------------------------- 7. 存量无密码账号
say "7) 存量账号（未设密码）"
LEGACY=$(post /auth/login "{\"phone\":\"13800000001\",\"password\":\"abc123456\"}")
echo "  $LEGACY"
expect "$(jget "code" "$LEGACY")" "101013" "未设密码 → 101013"

# ---------------------------------------------------------------- 8. 令牌可用性
say "8) 令牌可访问受保护接口 /wards"
H1=$(curl -s -o /dev/null -w '%{http_code}' "$PROTECTED" -H "Authorization: Bearer $TOKEN_P")
expect "$H1" "200" "accessToken 访问 /wards"
H2=$(curl -s -o /dev/null -w '%{http_code}' "$PROTECTED")
expect "$H2" "401" "匿名访问被拒"
H3=$(curl -s -o /dev/null -w '%{http_code}' "$PROTECTED" -H "Authorization: Bearer not-a-real-token")
expect "$H3" "401" "伪造 token 被拒"

# ---------------------------------------------------------------- 9. 刷新 / 登出
say "9) 刷新令牌"
RF=$(post /auth/refresh "{\"refreshToken\":\"$REFRESH_R\"}")
expect "$(jget "code" "$RF")" "0" "refreshToken 换新 accessToken"
NEW_ACCESS=$(jget "data.accessToken" "$RF")
[ -n "$NEW_ACCESS" ] && ok "拿到新 accessToken" || bad "未拿到新 accessToken"

say "9b) 访问令牌不能当刷新令牌用"
RFA=$(post /auth/refresh "{\"refreshToken\":\"$NEW_ACCESS\"}")
expect "$(jget "code" "$RFA")" "101004" "accessToken 换令牌被拒"

say "9c) 登出后 refreshToken 失效"
curl -s -X POST "$BASE/auth/logout" -H 'Content-Type: application/json' \
  -H "Authorization: Bearer $NEW_ACCESS" -d "{\"refreshToken\":\"$REFRESH_R\"}" >/dev/null
RF2=$(post /auth/refresh "{\"refreshToken\":\"$REFRESH_R\"}")
echo "  $RF2"
expect "$(jget "code" "$RF2")" "101004" "已登出 refreshToken 不可再用"
H4=$(curl -s -o /dev/null -w '%{http_code}' "$PROTECTED" -H "Authorization: Bearer $NEW_ACCESS")
expect "$H4" "401" "已登出 accessToken 立即失效"

# ---------------------------------------------------------------- 汇总
echo
echo "=============================================="
printf ' 结果：\033[32m%d passed\033[0m, \033[31m%d failed\033[0m\n' "$PASS" "$FAIL"
echo " 测试账号：$PHONE / abc123456"
echo "=============================================="
[ "$FAIL" -eq 0 ]

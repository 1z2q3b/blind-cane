#!/usr/bin/env bash
# S5 联调验证：用家属端 App 真实的网络层 + WebSocket 层直连后端跑一遍完整链路。
#
# 覆盖：验证码 -> 登录 -> 会话落盘 -> 被监护人列表/详情 -> 设备状态 ->
#       位置链路 -> 告警分页 -> STOMP 三主题推送 -> SOS 处置闭环 ->
#       跌倒取消闭环 -> 令牌轮换 -> 越权拦截
#
# 用法:
#   bash tools/verify-s5.sh              # 快测集（约 15 秒）
#   bash tools/verify-s5.sh --slow       # 追加「跌倒 30 秒自动升级」（约 60 秒）
#
# 前置：后端已在 127.0.0.1:8001 运行，且 blindcane.simulator.enabled = true
set -u

APP_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PORT="${PORT:-8001}"
BASE="${BASE:-http://127.0.0.1:$PORT}"
SLOW_FLAG=false
for arg in "$@"; do
  [ "$arg" = "--slow" ] && SLOW_FLAG=true
done

export PATH="/d/Flutter/flutter/bin:$PATH"
# 代理会让 127.0.0.1 的请求绕出去，联调必须清掉
unset http_proxy https_proxy HTTP_PROXY HTTPS_PROXY

echo "== 前置检查 =="
# 不用 curl -o /dev/null 判活：Git Bash 自带的 curl 写 /dev/null 会返回 23（写错误），
# 把「后端正常」误判成「后端没起」。直接看响应体里的业务码更可靠。
PROBE=$(curl -s --noproxy '*' --max-time 6 -X POST "$BASE/api/v1/mock/sms/reset?phone=0" 2>/dev/null || true)
case "$PROBE" in
  *'"code":0'*)
    echo "  [PASS] 后端在线，Mock 维护接口可用"
    ;;
  *)
    echo "  [FAIL] 后端未在 $BASE 正常响应（或 simulator 已关闭）"
    echo "         实际响应: $(echo "$PROBE" | head -c 200)"
    exit 1
    ;;
esac

cd "$APP_ROOT" || exit 1

DEFINES=(--dart-define=BACKEND_E2E=true --dart-define=API_BASE_URL="$BASE")
if [ "$SLOW_FLAG" = true ]; then
  DEFINES+=(--dart-define=BACKEND_E2E_SLOW=true)
  echo "  [INFO] 已开启慢测集（跌倒自动升级，约多 45 秒）"
fi

flutter test test/link/backend_link_test.dart "${DEFINES[@]}" --reporter expanded
STATUS=$?

echo
if [ $STATUS -eq 0 ]; then
  echo "== 联调结果: 全部通过 =="
else
  echo "== 联调结果: 存在失败项，见上方输出 =="
fi
exit $STATUS

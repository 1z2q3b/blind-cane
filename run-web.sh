#!/usr/bin/env bash
# =============================================================================
# 一键启动「导盲杖家属端」Web 版：打包最新前端 + 起静态服务。
#
# 用法：
#   ./run-web.sh            # 默认 9100 端口
#   ./run-web.sh 9999       # 指定端口
#
# 为什么每次都要重新 build：这个脚本会生成一个唯一的「构建标识」并烧进包里，
# 页面页脚会显示它。你看到的标识和脚本输出的一致，才说明跑的是最新代码；
# 对不上就说明浏览器拿的是旧包（旧包会被 Service Worker 缓存，本项目已在
# web/flutter_bootstrap.js 里禁用了 SW，正常情况下不会再出现这种问题）。
#
# 前置条件：后端要在 8001 端口跑着（脚本会检查，没跑会给出启动命令）。
# =============================================================================
set -e

PORT="${1:-9100}"
STAMP="$(date +%Y%m%d-%H%M%S)"
ROOT="$(cd "$(dirname "$0")" && pwd)"

# --- 检查后端 ---
if curl -s -o /dev/null --max-time 3 "http://127.0.0.1:8001/api/v1/wards"; then
  echo "[ok] 后端 8001 在线"
else
  echo "[警告] 后端 8001 未响应，请先在另一个终端启动："
  echo "    cd \"$ROOT/backend\" && ./build.sh -q spring-boot:run -Dspring-boot.run.arguments=--server.port=8001"
  echo ""
  read -r -p "仍要继续启动前端？[y/N] " ans
  [[ "$ans" =~ ^[Yy]$ ]] || exit 1
fi

# --- 构建前端 ---
echo "[1/2] 构建前端，构建标识 = $STAMP ..."
cd "$ROOT/app"
# --no-web-resources-cdn：把 CanvasKit 引擎打进本地包。
#   默认构建会从 gstatic.com  CDN 拉引擎，网络一被重置页面就是全白——
#   这个坑已经浪费过大量排查时间，宁可包大一点也绝不依赖外网。
flutter build web --release --no-web-resources-cdn --dart-define=BUILD_STAMP="$STAMP"

# --- 起静态服务 ---
echo ""
echo "[2/2] 静态服务已启动："
echo ""
echo "      http://127.0.0.1:$PORT"
echo ""
echo "    页脚显示的「构建 $STAMP」和此处一致 = 跑的是最新代码。"
echo "    停止服务：Ctrl+C"
echo ""
python -m http.server "$PORT" --directory build/web --bind 127.0.0.1

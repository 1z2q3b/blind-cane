#!/usr/bin/env bash
# =============================================================
# Maven 启动器（本机 mvn 脚本损坏时的替代方案）
#
# 背景：本机 D:\Maven\MavenDownload\apache-maven-3.8.9 安装完整，但
#       mvn / mvn.cmd 均报 ClassNotFoundException: plexus-classworlds.launcher，
#       根因是 MAVEN_HOME / JAVA_HOME 未设置导致脚本拼不出 boot 类路径。
#       这里直接用 java 加载 classworlds 启动 Maven，绕过损坏的启动脚本。
#
# 用法（Git Bash）：
#   ./build.sh clean compile
#   ./build.sh spring-boot:run
#   ./build.sh -DskipTests package
# 如需换 Maven 版本：MAVEN_HOME_DIR=... ./build.sh -v
# =============================================================
set -e

MAVEN_HOME_DIR="${MAVEN_HOME_DIR:-D:/Maven/MavenDownload/apache-maven-3.8.9}"
CLASSWORLDS_JAR="$(ls "$MAVEN_HOME_DIR"/boot/plexus-classworlds-*.jar 2>/dev/null | head -1)"

if [ -z "$CLASSWORLDS_JAR" ]; then
  echo "❌ 找不到 $MAVEN_HOME_DIR/boot/plexus-classworlds-*.jar，请检查 MAVEN_HOME_DIR" >&2
  exit 1
fi

# 取 Windows 风格路径（Maven 内部会自己转，但混用绝对路径更稳）
if PROJECT_DIR="$(pwd -W 2>/dev/null)"; then :; else PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"; fi
PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -W 2>/dev/null || cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

exec java \
  -classpath "$CLASSWORLDS_JAR" \
  "-Dclassworlds.conf=$MAVEN_HOME_DIR/bin/m2.conf" \
  "-Dmaven.home=$MAVEN_HOME_DIR" \
  "-Dmaven.multiModuleProjectDirectory=$PROJECT_DIR" \
  org.codehaus.plexus.classworlds.launcher.Launcher "$@"

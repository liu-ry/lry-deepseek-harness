#!/usr/bin/env bash
# dsh.sh — DeepSeek Harness (lry-deepseek-harness) 本地启停脚本
#
# 用法:
#   ./dsh.sh start      后台启动 Web UI,并打印带 token 的访问地址
#   ./dsh.sh stop       停止 Web UI
#   ./dsh.sh restart    重启
#   ./dsh.sh status     查看运行状态
#   ./dsh.sh url        只打印当前访问地址(含 token)
#   ./dsh.sh logs       实时跟踪日志(Ctrl-C 退出)
#   ./dsh.sh build      安装依赖并重新构建
#   ./dsh.sh help       帮助
#
# 可用环境变量覆盖默认值:
#   DSH_REPO=/path/to/lry-deepseek-harness   仓库位置
#   DSH_PORT=3080                            监听端口
#   DSH_NODE_VERSION=24                      nvm 使用的 Node 版本
#   DSH_RUN_DIR=<仓库>/.dsh-run              pid/日志目录

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="${DSH_REPO:-$SCRIPT_DIR}"
RUN_DIR="${DSH_RUN_DIR:-$REPO_DIR/.dsh-run}"
PID_FILE="$RUN_DIR/dsh-web.pid"
LOG_FILE="$RUN_DIR/dsh-web.log"
PORT="${DSH_PORT:-3080}"
NODE_VERSION="${DSH_NODE_VERSION:-24}"
export NVM_DIR="${NVM_DIR:-$HOME/.nvm}"

# pnpm dsh 实际执行的进程(相对路径,所以按 cwd 过滤,避免误杀其他仓库)
SERVER_PATTERN='apps/cli/src/bin\.ts web'
READY_TIMEOUT=180

die() { echo "错误: $*" >&2; exit 1; }
info() { echo "$*"; }

# 满足仓库要求 ^22.19 || >=24 才算可用
node_ok() {
  local v
  command -v node >/dev/null 2>&1 || return 1
  v="$(node -v 2>/dev/null)" || return 1
  [ "$(printf '%s\nv22.19.0\n' "$v" | sort -V | head -1)" = "v22.19.0" ]
}

# 直接使用 nvm 安装目录,不依赖 nvm 函数的退出码(它会被 ~/.npmrc 的 prefix 设置干扰)
load_node() {
  if node_ok; then return 0; fi
  local bin best=""
  for bin in "$NVM_DIR"/versions/node/v"$NODE_VERSION"*/bin; do
    [ -x "$bin/node" ] || continue
    if [ -z "$best" ] || [ "$(printf '%s\n%s\n' "$best" "$bin" | sort -V | tail -1)" = "$bin" ]; then
      best="$bin"
    fi
  done
  [ -n "$best" ] && export PATH="$best:$PATH"
  node_ok && return 0
  die "找不到满足要求的 Node (^22.19 || >=24),当前是 $(node -v 2>/dev/null || echo '无')。可执行: nvm install $NODE_VERSION"
}

# 打印属于本仓库的 server 进程 PID
server_pids() {
  local pid cwd
  for pid in $(pgrep -f "$SERVER_PATTERN" 2>/dev/null || true); do
    cwd="$(readlink "/proc/$pid/cwd" 2>/dev/null || true)"
    [ "$cwd" = "$REPO_DIR" ] && echo "$pid"
  done
}

is_running() { [ -n "$(server_pids)" ]; }

port_busy() { ss -ltn 2>/dev/null | grep -q ":${PORT} "; }

current_url() {
  [ -f "$LOG_FILE" ] || return 0
  grep -o "http://[0-9.]*:${PORT}/?token=[A-Za-z0-9_-]*" "$LOG_FILE" | tail -1
}

cmd_start() {
  [ -d "$REPO_DIR" ] || die "仓库不存在: $REPO_DIR"
  load_node
  mkdir -p "$RUN_DIR"

  if is_running; then
    info "已经在运行中 (pid: $(server_pids | tr '\n' ' '))"
    print_url
    return 0
  fi
  if port_busy; then
    die "端口 $PORT 已被其他进程占用,请先释放,或用 DSH_PORT=其他端口 启动"
  fi
  [ -f "$REPO_DIR/apps/web/dist/index.html" ] \
    || info "提示: 没检测到 Web 构建产物 (apps/web/dist),如果启动失败请先执行 $0 build"

  cd "$REPO_DIR"
  : > "$LOG_FILE"
  setsid nohup corepack pnpm dsh web --no-open --port "$PORT" >>"$LOG_FILE" 2>&1 </dev/null &
  echo $! > "$PID_FILE"

  info "正在启动 (端口 $PORT) ..."
  local waited=0
  while [ "$waited" -lt "$READY_TIMEOUT" ]; do
    if [ -n "$(current_url)" ]; then
      print_url
      return 0
    fi
    if ! is_running && [ "$waited" -gt 10 ]; then
      echo "--- 日志最后 30 行 ---" >&2
      tail -30 "$LOG_FILE" >&2 || true
      die "进程已退出,启动失败。完整日志: $LOG_FILE"
    fi
    sleep 1
    waited=$((waited + 1))
  done
  die "等待 $READY_TIMEOUT 秒仍未就绪,请查看日志: $LOG_FILE"
}

print_url() {
  local url
  url="$(current_url)"
  if [ -n "$url" ]; then
    info "访问地址: $url"
    info "(token 每次重启都会变,以本地址为准)"
  else
    info "日志中还没有地址,稍后再试: $0 url"
  fi
}

# 只输出地址本身,方便 `URL="$(./dsh.sh url)"` 这类用法
cmd_url() {
  local url
  url="$(current_url)"
  if [ -n "$url" ]; then
    echo "$url"
  else
    echo "日志中还没有访问地址" >&2
    exit 1
  fi
}

cmd_stop() {
  local pids pid waited=0 stopped=0
  pids="$(server_pids)"

  if [ -n "$pids" ]; then
    info "正在停止 server 进程: $(echo "$pids" | tr '\n' ' ')"
    kill -TERM $pids 2>/dev/null || true
    stopped=1
  fi
  if [ -f "$PID_FILE" ]; then
    pid="$(cat "$PID_FILE" 2>/dev/null || true)"
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
      kill -TERM "-$pid" 2>/dev/null || kill -TERM "$pid" 2>/dev/null || true
      stopped=1
    fi
  fi
  [ "$stopped" -eq 1 ] || { info "没有在运行"; cleanup; return 0; }

  while [ "$waited" -lt 40 ]; do
    is_running || break
    sleep 0.5
    waited=$((waited + 1))
  done
  if is_running; then
    info "优雅退出超时,强制结束"
    kill -KILL $(server_pids) 2>/dev/null || true
    sleep 1
  fi
  cleanup
  if is_running; then die "仍有残留进程: $(server_pids | tr '\n' ' ')"; fi
  info "已停止"
}

cleanup() { find "$RUN_DIR" -maxdepth 1 -type f -name 'dsh-web.pid' -delete 2>/dev/null || true; }

cmd_status() {
  if is_running; then
    info "状态: 运行中"
    info "pid : $(server_pids | tr '\n' ' ')"
    info "端口: $PORT"
    local url; url="$(current_url)"
    [ -n "$url" ] && info "地址: $url"
  else
    info "状态: 未运行"
    port_busy && info "注意: 端口 $PORT 被其他进程占用"
  fi
  info "仓库: $REPO_DIR"
  info "日志: $LOG_FILE"
}

cmd_build() {
  [ -d "$REPO_DIR" ] || die "仓库不存在: $REPO_DIR"
  load_node
  cd "$REPO_DIR"
  info "== 安装依赖 =="
  corepack pnpm install
  info "== 构建 =="
  corepack pnpm run build
  info "构建完成"
}

cmd_logs() {
  [ -f "$LOG_FILE" ] || die "还没有日志文件: $LOG_FILE"
  tail -f "$LOG_FILE"
}

# 打印文件头部的注释块(遇到第一行非注释即停止)
cmd_help() {
  awk 'NR>1 { if ($0 !~ /^#/) exit; sub(/^# ?/, ""); print }' "${BASH_SOURCE[0]}"
}

case "${1:-help}" in
  start)   cmd_start ;;
  stop)    cmd_stop ;;
  restart) cmd_stop; cmd_start ;;
  status)  cmd_status ;;
  url)     cmd_url ;;
  logs)    cmd_logs ;;
  build)   cmd_build ;;
  help|-h|--help) cmd_help ;;
  *) die "未知命令: $1 (可用: start|stop|restart|status|url|logs|build|help)" ;;
esac

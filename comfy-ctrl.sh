#!/usr/bin/env bash
#
# comfy-ctrl.sh — control the ComfyUI server (binds 0.0.0.0).
#
#   ./comfy-ctrl.sh start      start in the background
#   ./comfy-ctrl.sh stop       stop it
#   ./comfy-ctrl.sh restart    stop then start
#   ./comfy-ctrl.sh status     is it running? (PID + URL)
#   ./comfy-ctrl.sh log [N]    tail -f the log (optionally last N lines first)
#
set -uo pipefail

COMFY_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PY="$COMFY_DIR/.venv/bin/python"
PIDFILE="$COMFY_DIR/.comfy.pid"
LOGFILE="$COMFY_DIR/logs/comfyui.log"

HOST="0.0.0.0"
PORT="8188"
# RTX 5090 (Blackwell) tuning: --fast = fp16 accumulation + fp8 matmul,
# plus SageAttention; --enable-manager turns on ComfyUI-Manager.
ARGS=(--listen "$HOST" --port "$PORT" --fast --use-sage-attention --enable-manager)

is_running() {
    [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE" 2>/dev/null)" 2>/dev/null
}

start() {
    if is_running; then
        echo "already running (PID $(cat "$PIDFILE")) on http://$HOST:$PORT"
        return 0
    fi
    rm -f "$PIDFILE"
    [ -x "$PY" ] || { echo "venv python not found at $PY — run the install first." >&2; exit 1; }
    mkdir -p "$(dirname "$LOGFILE")"
    echo "===== $(date '+%F %T') starting: main.py ${ARGS[*]} =====" >>"$LOGFILE"
    cd "$COMFY_DIR" || { echo "cannot cd to $COMFY_DIR" >&2; exit 1; }
    nohup "$PY" main.py "${ARGS[@]}" >>"$LOGFILE" 2>&1 &
    echo $! >"$PIDFILE"
    sleep 3
    if is_running; then
        echo "started (PID $(cat "$PIDFILE")) on http://$HOST:$PORT"
        echo "watch startup with: $0 log"
    else
        echo "failed to start — last log lines:" >&2
        tail -n 20 "$LOGFILE" >&2
        rm -f "$PIDFILE"
        exit 1
    fi
}

stop() {
    if is_running; then
        local pid; pid="$(cat "$PIDFILE")"
        kill "$pid" 2>/dev/null || true
        for _ in $(seq 1 20); do is_running || break; sleep 0.5; done
        if is_running; then
            echo "did not stop gracefully, sending SIGKILL"
            kill -9 "$pid" 2>/dev/null || true
        fi
        echo "stopped"
    else
        echo "not running"
    fi
    rm -f "$PIDFILE"
}

status() {
    if is_running; then
        echo "running (PID $(cat "$PIDFILE")) on http://$HOST:$PORT"
    else
        echo "stopped"
        return 1
    fi
}

logs() {
    [ -f "$LOGFILE" ] || { echo "no log yet at $LOGFILE"; exit 1; }
    if [ -n "${1:-}" ]; then
        tail -n "$1" -f "$LOGFILE"
    else
        tail -f "$LOGFILE"
    fi
}

case "${1:-}" in
    start)   start ;;
    stop)    stop ;;
    restart) stop; start ;;
    status)  status ;;
    log)     logs "${2:-}" ;;
    *) echo "usage: $0 {start|stop|restart|status|log [N]}" >&2; exit 2 ;;
esac

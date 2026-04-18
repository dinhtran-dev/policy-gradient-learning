#!/usr/bin/env bash
# run.sh
# Kill any running Jupyter Lab instance for this project and launch a fresh one
# serving policy_gradient.ipynb.
#
# Usage:
#   ./run.sh              # launch on default port 8888
#   PORT=8890 ./run.sh    # launch on a custom port

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV_DIR="${PROJECT_DIR}/.venv"
NOTEBOOK="policy_gradient.ipynb"
PORT="${PORT:-8888}"
PIDFILE="${PROJECT_DIR}/.jupyter.pid"
LOGFILE="${PROJECT_DIR}/.jupyter.log"

log()  { printf '\033[1;34m[run]\033[0m  %s\n' "$*"; }
warn() { printf '\033[1;33m[warn]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[fail]\033[0m %s\n' "$*" >&2; exit 1; }

# --- 1. Kill any existing Jupyter for this project --------------------------
kill_pid() {
  local pid="$1"
  if kill -0 "${pid}" 2>/dev/null; then
    log "stopping pid ${pid}"
    kill "${pid}" 2>/dev/null || true
    for _ in 1 2 3 4 5; do
      kill -0 "${pid}" 2>/dev/null || return 0
      sleep 1
    done
    warn "pid ${pid} still alive, sending SIGKILL"
    kill -9 "${pid}" 2>/dev/null || true
  fi
}

if [[ -f "${PIDFILE}" ]]; then
  kill_pid "$(cat "${PIDFILE}")"
  rm -f "${PIDFILE}"
fi

# Also sweep any Jupyter processes rooted in this project or bound to the port.
if command -v pgrep >/dev/null 2>&1; then
  while read -r pid; do
    [[ -n "${pid}" ]] && kill_pid "${pid}"
  done < <(pgrep -f "jupyter-lab.*${PROJECT_DIR}" || true)
fi

if command -v lsof >/dev/null 2>&1; then
  while read -r pid; do
    [[ -n "${pid}" ]] && kill_pid "${pid}"
  done < <(lsof -ti tcp:"${PORT}" || true)
fi

# --- 2. Activate the project virtualenv -------------------------------------
if [[ ! -d "${VENV_DIR}" ]]; then
  die "No virtualenv at ${VENV_DIR}. Run ./environment_setup.sh first."
fi
# shellcheck disable=SC1091
source "${VENV_DIR}/bin/activate"

if ! command -v jupyter >/dev/null 2>&1; then
  die "jupyter not found in venv. Re-run ./environment_setup.sh."
fi

# --- 3. Launch JupyterLab ---------------------------------------------------
log "launching JupyterLab on port ${PORT}"
: > "${LOGFILE}"

nohup jupyter lab \
  --no-browser \
  --ip=127.0.0.1 \
  --port="${PORT}" \
  --notebook-dir="${PROJECT_DIR}" \
  >"${LOGFILE}" 2>&1 &

JUPYTER_PID=$!
echo "${JUPYTER_PID}" > "${PIDFILE}"
log "pid ${JUPYTER_PID} (logs: ${LOGFILE})"

# --- 4. Wait for the server to print its URL, then open the notebook --------
URL=""
for _ in $(seq 1 30); do
  URL="$(grep -Eo 'https?://127\.0\.0\.1:[0-9]+/lab\?token=[A-Za-z0-9]+' "${LOGFILE}" | head -n1 || true)"
  [[ -n "${URL}" ]] && break
  sleep 1
done

if [[ -z "${URL}" ]]; then
  warn "did not see a URL in ${LOGFILE} after 30s; tailing last lines:"
  tail -n 20 "${LOGFILE}" || true
  die "jupyter failed to start"
fi

NOTEBOOK_URL="${URL/\/lab?/\/lab/tree/${NOTEBOOK}?}"
log "ready: ${NOTEBOOK_URL}"

if [[ "$(uname -s)" == "Darwin" ]] && command -v open >/dev/null 2>&1; then
  open "${NOTEBOOK_URL}" || true
fi

cat <<EOF

[run] JupyterLab is running (pid ${JUPYTER_PID}).
  stop: kill \$(cat ${PIDFILE#${PROJECT_DIR}/})   # or rerun ./run.sh
  logs: tail -f ${LOGFILE#${PROJECT_DIR}/}
EOF

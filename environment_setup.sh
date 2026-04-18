#!/usr/bin/env bash
# environment_setup.sh
# Bootstrap a local Python environment for the policy_gradient.ipynb notebook
# on Apple Silicon Macs (M1/M2/M3/M4, arm64).
#
# Usage:
#   ./environment_setup.sh
#   source .venv/bin/activate
#   jupyter lab policy_gradient.ipynb

set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VENV_DIR="${PROJECT_DIR}/.venv"
PYTHON_VERSION="${PYTHON_VERSION:-3.11}"

log()  { printf '\033[1;34m[setup]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[warn]\033[0m  %s\n' "$*"; }
die()  { printf '\033[1;31m[fail]\033[0m  %s\n' "$*" >&2; exit 1; }

# --- 1. Sanity checks -------------------------------------------------------
if [[ "$(uname -s)" != "Darwin" ]]; then
  die "This script targets macOS. Detected: $(uname -s)."
fi

ARCH="$(uname -m)"
if [[ "${ARCH}" != "arm64" ]]; then
  warn "Detected arch ${ARCH}; this script is tuned for Apple Silicon (arm64)."
fi

CHIP="$(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo 'unknown')"
log "macOS $(sw_vers -productVersion) on ${CHIP} (${ARCH})"

# --- 2. Homebrew ------------------------------------------------------------
if ! command -v brew >/dev/null 2>&1; then
  die "Homebrew not found. Install it from https://brew.sh then re-run this script."
fi

# Ensure Apple Silicon brew prefix is on PATH for this shell.
if [[ -x /opt/homebrew/bin/brew ]]; then
  eval "$(/opt/homebrew/bin/brew shellenv)"
fi

log "Installing system dependencies via Homebrew"
brew update >/dev/null
brew install "python@${PYTHON_VERSION}" >/dev/null

# SDL2 is used by pygame, which gymnasium's classic-control rendering depends on.
brew install sdl2 sdl2_image sdl2_mixer sdl2_ttf >/dev/null

# --- 3. Python virtualenv ---------------------------------------------------
PYTHON_BIN="$(brew --prefix)/opt/python@${PYTHON_VERSION}/libexec/bin/python3"
if [[ ! -x "${PYTHON_BIN}" ]]; then
  PYTHON_BIN="python${PYTHON_VERSION}"
fi

log "Creating virtualenv at ${VENV_DIR} (Python ${PYTHON_VERSION})"
"${PYTHON_BIN}" -m venv "${VENV_DIR}"
# shellcheck disable=SC1091
source "${VENV_DIR}/bin/activate"

python -m pip install --upgrade pip wheel setuptools

# --- 4. PyTorch (with Metal / MPS support) ----------------------------------
# The default wheels on PyPI for macOS arm64 already include MPS support,
# so no special index-url is needed.
log "Installing PyTorch (MPS-enabled)"
pip install --upgrade torch torchvision

# --- 5. Project dependencies ------------------------------------------------
log "Installing RL + notebook dependencies"
pip install \
  "gymnasium[classic-control]" \
  numpy \
  matplotlib \
  jupyterlab \
  ipywidgets \
  tqdm

# --- 6. Smoke test ----------------------------------------------------------
log "Verifying install"
python - <<'PY'
import platform, torch, gymnasium as gym
print(f"  python  : {platform.python_version()} ({platform.machine()})")
print(f"  torch   : {torch.__version__}")
print(f"  mps     : built={torch.backends.mps.is_built()} available={torch.backends.mps.is_available()}")
env = gym.make("CartPole-v1")
obs, _ = env.reset(seed=0)
print(f"  gym     : CartPole-v1 obs shape={obs.shape}, actions={env.action_space.n}")
env.close()
PY

cat <<EOF

[setup] Done.

Next steps:
  source ${VENV_DIR#${PROJECT_DIR}/}/bin/activate
  jupyter lab policy_gradient.ipynb

Inside the notebook, the training code auto-detects MPS:
  device = torch.device("mps" if torch.backends.mps.is_available() else "cpu")
(CartPole is tiny — CPU is actually faster than MPS for this workload.)
EOF

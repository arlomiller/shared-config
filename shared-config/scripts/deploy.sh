#!/usr/bin/env bash
set -euo pipefail
trap 'echo "[SHARED-DEPLOY ERROR] Command failed at line $LINENO with exit code $?" >&2' ERR

log() {
  local level="${1:-INFO}"
  shift
  echo "[SHARED-DEPLOY $(date -u +%Y-%m-%dT%H:%M:%SZ)] [$level] $*"
}

# Shared deploy wrapper — delegates to repo-local installer and performs safe
# workstation-side steps: commit/push, copy installer to Pi, and execute it.
# This is adapted from Pi-Baseline/deploy.sh to provide a canonical deploy
# implementation usable by multiple repos (Pi-Baseline, Wallboard, etc.).

PI_CONFIGS_DIR=${PI_CONFIGS_DIR:-/c/Repos/Pi-Configs}
PI_HOST=${PI_HOST:-pi-kitchen}
PI_USER=${PI_USER:-piadmin}
REPO_DIR=${REPO_DIR:-/home/${PI_USER}/$(basename "$(pwd)")}
LOCAL_INSTALLER=${LOCAL_INSTALLER:-scripts/deployment/deploy-on-pi.sh}
BRANCH=${BRANCH:-main}
PI_SSH_PORT=${PI_SSH_PORT:-22}
PI_KEY_DIR=${PI_KEY_DIR:-/c/PiKeys/${PI_HOST}}
PI_KEY_PATH=${PI_KEY_PATH:-${PI_KEY_DIR}/id_ed25519}
SKIP_PI_KEY_INSTALL=${SKIP_PI_KEY_INSTALL:-0}
FORCE_KEY_INSTALL=${FORCE_KEY_INSTALL:-0}
SETUP_NONINTERACTIVE=${SETUP_NONINTERACTIVE:-1}

SCP_OPTS=""
SSH_OPTS=""
if [ -n "${PI_SSH_PORT}" ] && [ "${PI_SSH_PORT}" != "22" ]; then
  SCP_OPTS="-P ${PI_SSH_PORT}"
  SSH_OPTS="-p ${PI_SSH_PORT}"
fi

# Directory of this script (canonical shared-config scripts dir)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# If the repo-local installer isn't present, try the canonical installer
# packaged with shared-config (i.e. next to this script).
if [ ! -f "${LOCAL_INSTALLER}" ]; then
  if [ -f "${SCRIPT_DIR}/deploy-on-pi.sh" ]; then
    LOCAL_INSTALLER="${SCRIPT_DIR}/deploy-on-pi.sh"
    log "INFO" "Repo-local installer not found; using canonical installer: ${LOCAL_INSTALLER}"
  fi
fi

if ! command -v git >/dev/null 2>&1; then
  log "ERROR" "git is not installed"
  exit 1
fi

if ! command -v ssh >/dev/null 2>&1; then
  log "ERROR" "ssh is not installed"
  exit 1
fi

if ! command -v scp >/dev/null 2>&1; then
  log "ERROR" "scp is not installed"
  exit 1
fi

log "INFO" "Preparing deployment to ${PI_HOST} (branch: ${BRANCH})"

ensure_known_host() {
  mkdir -p "${HOME}/.ssh" && chmod 700 "${HOME}/.ssh" || true
  local known_hosts="${HOME}/.ssh/known_hosts"
  local ssh_check=""

  ssh_check=$(ssh -o BatchMode=yes -o StrictHostKeyChecking=yes -o ConnectTimeout=5 ${SSH_OPTS} "${PI_USER}@${PI_HOST}" true 2>&1) && return 0 || true

  if echo "${ssh_check}" | grep -q "REMOTE HOST IDENTIFICATION HAS CHANGED"; then
    log "WARN" "Host key changed for ${PI_HOST}; removing old key"
    ssh-keygen -R "${PI_HOST}" >/dev/null 2>&1 || true
  fi

  if ! ssh-keygen -F "${PI_HOST}" >/dev/null 2>&1; then
    ssh-keyscan -p "${PI_SSH_PORT}" -H "${PI_HOST}" 2>/dev/null >> "${known_hosts}" || true
  fi

  chmod 600 "${known_hosts}" || true
}

ensure_known_host

# Quick SSH auth check
if ! ssh -o BatchMode=yes -o ConnectTimeout=5 ${SSH_OPTS} "${PI_USER}@${PI_HOST}" true 2>/dev/null; then
  log "WARN" "SSH key auth failed; ensure your public key is installed on ${PI_HOST} for ${PI_USER}"
fi

ensure_pi_keypair() {
  mkdir -p "${PI_KEY_DIR}"
  if [ ! -f "${PI_KEY_PATH}" ]; then
    log "INFO" "Generating per-Pi keypair at ${PI_KEY_PATH}"
    ssh-keygen -t ed25519 -f "${PI_KEY_PATH}" -N "" -C "${PI_HOST}" >/dev/null
  fi
  if [ ! -f "${PI_KEY_PATH}.pub" ]; then
    ssh-keygen -y -f "${PI_KEY_PATH}" > "${PI_KEY_PATH}.pub"
  fi
}

install_pi_keypair_on_pi() {
  REMOTE_TARGET="${PI_USER}@${PI_HOST}"
  if [ "${SKIP_PI_KEY_INSTALL}" = "1" ]; then
    log "INFO" "Skipping Pi SSH key install (SKIP_PI_KEY_INSTALL=1)"
    return 0
  fi
  ensure_pi_keypair
  scp -q -P "${PI_SSH_PORT}" "${PI_KEY_PATH}" "${REMOTE_TARGET}:/home/${PI_USER}/.ssh/id_ed25519" || true
  scp -q -P "${PI_SSH_PORT}" "${PI_KEY_PATH}.pub" "${REMOTE_TARGET}:/home/${PI_USER}/.ssh/id_ed25519.pub" || true
}

# Commit & push changes (idempotent)
log "INFO" "Committing and pushing changes to origin/${BRANCH}"
git add -A -- ':!config/customization.env'
if git diff --cached --quiet; then
  log "INFO" "No changes to commit"
else
  git commit -m "Deploy: $(date +%Y%m%d%H%M%S)" || true
fi
git push origin "${BRANCH}" || log "WARN" "git push failed"

ORIGIN_URL=$(git remote get-url origin 2>/dev/null || true)
if [ -z "${ORIGIN_URL}" ]; then
  log "ERROR" "Could not determine git origin URL"
  exit 1
fi

REMOTE_TARGET="${PI_USER}@${PI_HOST}"

log "INFO" "Ensuring remote directory ${REPO_DIR} exists on ${REMOTE_TARGET}"
ssh ${SSH_OPTS} "${REMOTE_TARGET}" "mkdir -p '${REPO_DIR}'" || true

install_pi_keypair_on_pi

if [ ! -f "${LOCAL_INSTALLER}" ]; then
  log "ERROR" "Installer file not found: ${LOCAL_INSTALLER}"
  exit 1
fi

log "INFO" "Copying ${LOCAL_INSTALLER} to ${REMOTE_TARGET}:${REPO_DIR}"
scp ${SCP_OPTS} -q "${LOCAL_INSTALLER}" "${REMOTE_TARGET}:${REPO_DIR}/" || { log "ERROR" "Failed to copy installer to remote"; exit 1; }

REMOTE_INSTALLER=$(basename "${LOCAL_INSTALLER}")

log "INFO" "Running remote installer on ${REMOTE_TARGET}"
ORIGIN_URL_ESCAPED=${ORIGIN_URL//\'/\'\\\'\'}
SSH_TTY_OPT=""
if [ -t 0 ]; then SSH_TTY_OPT="-t"; fi
ssh ${SSH_OPTS} ${SSH_TTY_OPT} "${REMOTE_TARGET}" "REPO_URL='${ORIGIN_URL_ESCAPED}' BRANCH='${BRANCH}' SETUP_NONINTERACTIVE='${SETUP_NONINTERACTIVE}' bash -l -c 'cd \"${REPO_DIR}\" && chmod +x \"${REMOTE_INSTALLER}\" && ./\"${REMOTE_INSTALLER}\"'" || { log "ERROR" "Remote deployment failed"; exit 1; }

log "INFO" "Deploy finished. Review remote output for backup path and results."

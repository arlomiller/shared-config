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

PI_CONFIGS_DIR=${PI_CONFIGS_DIR:-/c/Repos/PiConfigs}
PI_HOST=${PI_HOST:-pi-kitchen}
PI_USER=${PI_USER:-piadmin}
REPO_DIR=${REPO_DIR:-/home/${PI_USER}/$(basename "$(pwd)")}
LOCAL_INSTALLER=${LOCAL_INSTALLER:-scripts/deployment/deploy-on-pi.sh}
BRANCH=${BRANCH:-main}
PI_SSH_PORT=${PI_SSH_PORT:-22}
SETUP_NONINTERACTIVE=${SETUP_NONINTERACTIVE:-1}

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

# Ensure known_hosts entry
mkdir -p "${HOME}/.ssh" && chmod 700 "${HOME}/.ssh" || true
if ! ssh-keygen -F "${PI_HOST}" >/dev/null 2>&1; then
  ssh-keyscan -p "${PI_SSH_PORT}" -H "${PI_HOST}" 2>/dev/null >> "${HOME}/.ssh/known_hosts" || true
  chmod 600 "${HOME}/.ssh/known_hosts" || true
fi

# Quick SSH auth check
if ! ssh -o BatchMode=yes -o ConnectTimeout=5 "${PI_USER}@${PI_HOST}" true 2>/dev/null; then
  log "WARN" "SSH key auth failed; will install workstation key to Pi's authorized_keys"
fi

# Find workstation's public key early (before any SSH commands)
WORKSTATION_PUBKEY=""
for key in "${HOME}/.ssh/id_ed25519.pub" "${HOME}/.ssh/id_rsa.pub" "${HOME}/.ssh/id_ecdsa.pub"; do
  if [ -f "$key" ]; then
    WORKSTATION_PUBKEY="$key"
    log "INFO" "Found workstation SSH key: $key"
    break
  fi
done

if [ -z "$WORKSTATION_PUBKEY" ]; then
  log "WARN" "No workstation SSH public key found; you'll need to enter password for each SSH command"
  log "WARN" "Generate a key with: ssh-keygen -t ed25519"
fi

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

# Convert HTTPS URLs to SSH for Pi (Pi uses SSH key for GitHub, not HTTPS)
# HTTPS: https://github.com/user/repo.git → SSH: git@github.com:user/repo.git
if [[ "${ORIGIN_URL}" =~ ^https://github\.com/(.+)$ ]]; then
  REPO_PATH="${BASH_REMATCH[1]}"
  ORIGIN_URL="git@github.com:${REPO_PATH}"
  log "INFO" "Converted HTTPS URL to SSH for Pi"
fi

REMOTE_TARGET="${PI_USER}@${PI_HOST}"
SCP_OPTS=""
SSH_OPTS=""
if [ -n "${PI_SSH_PORT}" ] && [ "${PI_SSH_PORT}" != "22" ]; then
  SCP_OPTS="-P ${PI_SSH_PORT}"
  SSH_OPTS="-p ${PI_SSH_PORT}"
fi

log "INFO" "Setting up remote directory and SSH key (will request password once)"
# Combine ALL setup into ONE SSH command to minimize password prompts
if [ -n "$WORKSTATION_PUBKEY" ] && [ -f "$WORKSTATION_PUBKEY" ]; then
  PUBKEY_CONTENT=$(cat "$WORKSTATION_PUBKEY")
  # Single SSH command: create dir, setup .ssh, install key - ONLY 1 PASSWORD PROMPT
  ssh ${SSH_OPTS} "${REMOTE_TARGET}" "mkdir -p '${REPO_DIR}' ~/.ssh && chmod 700 ~/.ssh && touch ~/.ssh/authorized_keys && chmod 600 ~/.ssh/authorized_keys && (grep -qF '${PUBKEY_CONTENT}' ~/.ssh/authorized_keys 2>/dev/null || echo '${PUBKEY_CONTENT}' >> ~/.ssh/authorized_keys)" && {
    log "INFO" "Setup complete - workstation SSH key installed, subsequent commands will be passwordless"
  } || {
    log "WARN" "Setup failed; you may need to enter password for remaining commands"
    # Fallback: just try to create the directory
    ssh ${SSH_OPTS} "${REMOTE_TARGET}" "mkdir -p '${REPO_DIR}'" 2>/dev/null || log "ERROR" "Could not create remote directory"
  }
else
  log "WARN" "No workstation SSH key found; will need password for each command"
  ssh ${SSH_OPTS} "${REMOTE_TARGET}" "mkdir -p '${REPO_DIR}'" || log "ERROR" "Could not create remote directory"
fi

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

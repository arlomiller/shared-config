#!/usr/bin/env bash
# =============================================================================
# deploy-on-pi.sh (canonical copy)
# =============================================================================
# This is the canonical Pi-side installer. It is a direct copy of
# `Pi-Baseline/scripts/deployment/deploy-on-pi.sh` so other repos (Wallboard)
# can reference the exact installer that will be placed on the Pi by
# `deploy.sh` during deployment.
#
set -euo pipefail

trap 'echo "[DEPLOY-ON-PI ERROR] Command failed at line $LINENO with exit code $?" >&2' ERR

log() {
  local level="${1:-INFO}"
  shift
  local msg="$*"
  echo "[DEPLOY-ON-PI $(date -u +%Y-%m-%dT%H:%M:%SZ)] [$level] $msg"
}

TS=$(date +%Y%m%d%H%M%S)

# Ensure we're in a directory (not a symlink or broken path)
if [ ! -d "${PWD}" ]; then
  log "ERROR" "Current directory does not exist or is not a directory: ${PWD}"
  exit 1
fi

# Source customization if present so BASE_BACKUP_DIR and PI_USER can be respected
if [ -f config/customization.env ]; then
  # shellcheck disable=SC1090
  . config/customization.env
fi
BKBASE="${BASE_BACKUP_DIR:-${HOME}/backups}"
BKDIR="${BKBASE}/${TS}"
BRANCH="${BRANCH:-main}"
REPO_URL="${REPO_URL:-}"

# Validate backup directory creation and permissions
log "INFO" "Creating backup folder: ${BKDIR}"
mkdir -p "${BKDIR}" || {
  log "ERROR" "Failed to create backup directory: ${BKDIR}"
  exit 1
}

# Verify directory is writable
if [ ! -w "${BKDIR}" ]; then
  log "ERROR" "Backup directory not writable: ${BKDIR}"
  exit 1
fi

log "INFO" "Backing up system files"

# Backup /etc/fstab if present
if [ -f /etc/fstab ]; then
  cp /etc/fstab "${BKDIR}/" || log "WARN" "Failed to backup /etc/fstab"
fi

# Backup any systemd unit files we might touch (best-effort)
mkdir -p "${BKDIR}/etc-systemd"
cp -a /etc/systemd/system/*.service "${BKDIR}/etc-systemd/" 2>/dev/null || log "WARN" "No systemd service files to backup"

# Backup the repo state (git archive of current commit)
if command -v git >/dev/null 2>&1 && [ -d .git ]; then
  if git rev-parse --verify HEAD >/dev/null 2>&1; then
    log "INFO" "Creating git archive of current state"
    if git archive -o "${BKDIR}/repo-archive.tar" HEAD 2>/dev/null; then
      if [ -f "${BKDIR}/repo-archive.tar" ] && [ -s "${BKDIR}/repo-archive.tar" ]; then
        log "INFO" "Git archive validated: ${BKDIR}/repo-archive.tar"
      else
        log "WARN" "Git archive is empty"
      fi
    else
      log "WARN" "Failed to create git archive (may not be a git repo)"
    fi
  else
    log "WARN" "No valid HEAD commit found, skipping git archive"
  fi
fi

# Create a restore script (captures BKDIR in-place)
log "INFO" "Creating restore script: ${BKDIR}/restore.sh"
cat > "${BKDIR}/restore.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
BKDIR="'"${BKDIR}"'"
if [ -f "${BKDIR}/fstab" ]; then
  sudo cp -a "${BKDIR}/fstab" /etc/fstab
fi
if [ -d "${BKDIR}/etc-systemd" ]; then
  sudo cp -a "${BKDIR}/etc-systemd/" /etc/systemd/system/ || true
  sudo systemctl daemon-reload || true
fi
echo "Restored files from ${BKDIR}"
SH

chmod +x "${BKDIR}/restore.sh" || {
  log "ERROR" "Failed to make restore.sh executable"
  exit 1
}

log "INFO" "Backup complete. Backup folder: ${BKDIR}"

# Run SSH key setup early (before git pull) so GitHub/git host auth is ready
if [ -x ./setup-ssh-keys.sh ]; then
  log "INFO" "Running SSH key setup before git pull..."
  if ! bash ./setup-ssh-keys.sh 2>&1 | grep -v "^$" | head -5; then
    log "WARN" "SSH key setup may have failed, continuing anyway"
  fi
fi

log "INFO" "Updating repository and running setup if available..."

KEY_MARKER="${HOME}/.ssh/.pi-baseline-deploy-key-registered"

print_deploy_key() {
  if [ -f "${HOME}/.ssh/id_ed25519.pub" ]; then
    echo ""
    echo "=== GitHub Deploy Key (add to repo, read-only) ==="
    cat "${HOME}/.ssh/id_ed25519.pub"
    echo "=================================================="
    echo ""
    return 0
  fi
  log "ERROR" "No SSH public key found at ~/.ssh/id_ed25519.pub"
  return 1
}

prompt_for_deploy_key() {
  if ! print_deploy_key; then
    return 1
  fi
  if [ -t 0 ]; then
    read -r -p "Press Enter after adding the deploy key to GitHub: " _
    return 0
  fi
  log "ERROR" "No TTY available to pause; add the deploy key then re-run deploy"
  return 1
}

git_host_from_url() {
  local url="$1"
  if echo "${url}" | grep -qE "@[^:]+:"; then
    echo "${url}" | sed -E 's/.*@([^:]+):.*/\1/'
  elif echo "${url}" | grep -qE "https?://"; then
    echo "${url}" | sed -E 's|https?://([^/]+)/.*|\1|'
  fi
}

ensure_git_host_key() {
  local url="$1"
  local host=""
  host=$(git_host_from_url "${url}")
  if [ -z "${host}" ]; then
    return 0
  fi
  mkdir -p "${HOME}/.ssh" && chmod 700 "${HOME}/.ssh" || true
  if ! ssh-keygen -F "${host}" >/dev/null 2>&1; then
    log "INFO" "Adding ${host} to known_hosts to avoid host key prompts"
    ssh-keyscan -t rsa,ed25519 "${host}" >> "${HOME}/.ssh/known_hosts" 2>/dev/null || true
    chmod 600 "${HOME}/.ssh/known_hosts" || true
  fi
}

fetch_with_prompt() {
  local output=""
  if output=$(git fetch origin "${BRANCH}" --depth=1 2>&1); then
    touch "${KEY_MARKER}" 2>/dev/null || true
    return 0
  fi
  if echo "${output}" | grep -qiE "Permission denied \(publickey\)|Could not read from remote repository"; then
    log "WARN" "GitHub SSH auth failed; add deploy key and retry"
    if [ -f "${KEY_MARKER}" ]; then
      log "WARN" "Deploy key marker exists but auth still fails; re-add deploy key and retry"
    fi
    if ! prompt_for_deploy_key; then
      return 1
    fi
    if git fetch origin "${BRANCH}" --depth=1; then
      touch "${KEY_MARKER}" 2>/dev/null || true
      return 0
    fi
    return 1
  fi
  log "WARN" "Git fetch failed: ${output%%$'\n'*}"
  return 1
}

# If the repo exists, ensure it's clean or handle changes before pulling.
if command -v git >/dev/null 2>&1 && [ -d .git ]; then
  PORCELAIN=$(git status --porcelain)
  if [ -n "${PORCELAIN}" ]; then
    log "WARN" "Repository has local changes on remote."
    if [ "${FORCE_REMOTE_RESET:-0}" = "1" ]; then
      log "INFO" "FORCE_REMOTE_RESET=1 set — resetting remote to origin/${BRANCH}"
      git fetch origin || log "WARN" "git fetch failed"
      git reset --hard "origin/${BRANCH}" || log "ERROR" "git reset failed"
      git clean -fdx || log "WARN" "git clean failed"
      printf '%s | ACTION | force-reset to origin/%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${BRANCH}" >> "${BKDIR}/changes.log" || true
    else
      STASH_MSG="deploy-autostash-$(date -Iseconds)"
      if git stash push --include-untracked -m "${STASH_MSG}" >/dev/null 2>&1; then
        STASH_REF=$(git stash list -1 --format="%gd: %s" 2>/dev/null || echo "stash created")
        log "INFO" "Stashed remote changes: ${STASH_REF}"
        printf '%s | ACTION | stashed changes: %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "${STASH_REF}" >> "${BKDIR}/changes.log" || true
      else
        log "WARN" "No stash was created (working tree may be clean)"
      fi
    fi
  fi
fi

# If repo has no commits yet, fetch + checkout before pulling
if command -v git >/dev/null 2>&1 && [ -d .git ]; then
  if ! git rev-parse --verify HEAD >/dev/null 2>&1; then
    log "WARN" "Repository has no commits; fetching and checking out origin/${BRANCH}"
    ORIG_URL=$(git remote get-url origin 2>/dev/null || true)
    if [ -z "${ORIG_URL}" ] && [ -n "${REPO_URL}" ]; then
      git remote add origin "${REPO_URL}" || { log "ERROR" "Failed to add origin"; exit 1; }
      ORIG_URL="${REPO_URL}"
    elif [ -n "${REPO_URL}" ] && [ "${ORIG_URL}" != "${REPO_URL}" ]; then
      git remote set-url origin "${REPO_URL}" || { log "ERROR" "Failed to set origin URL"; exit 1; }
      ORIG_URL="${REPO_URL}"
    fi

    if [ -n "${ORIG_URL}" ]; then
      ensure_git_host_key "${ORIG_URL}"
    fi

    if ! fetch_with_prompt; then
      log "ERROR" "Git fetch failed"
      log "INFO" "To rollback, run: ${BKDIR}/restore.sh"
      exit 1
    fi

    git checkout -B "${BRANCH}" "origin/${BRANCH}" || { log "ERROR" "git checkout failed"; exit 1; }
  fi
fi

# Pre-pull: ensure git host key is present in known_hosts to avoid interactive prompts
if command -v git >/dev/null 2>&1 && [ -d .git ]; then
  ORIG_URL=$(git remote get-url origin 2>/dev/null || true)
  if [ -n "${ORIG_URL}" ]; then
    ensure_git_host_key "${ORIG_URL}"
  fi
fi

GIT_PULL_OUTPUT=""
if ! GIT_PULL_OUTPUT=$(git pull --rebase 2>&1); then
  log "WARN" "Git pull failed: ${GIT_PULL_OUTPUT%%$'\n'*}"
  if echo "${GIT_PULL_OUTPUT}" | grep -qiE "Permission denied \(publickey\)|Could not read from remote repository"; then
    log "WARN" "GitHub SSH auth failed; add deploy key and retry"
    if ! prompt_for_deploy_key; then
      log "INFO" "To rollback, run: ${BKDIR}/restore.sh"
      exit 1
    fi
    if ! git pull --rebase 2>&1; then
      log "ERROR" "Git pull failed after deploy key prompt"
      log "INFO" "To rollback, run: ${BKDIR}/restore.sh"
      exit 1
    fi
  else
    log "ERROR" "Git pull failed"
    log "INFO" "To rollback, run: ${BKDIR}/restore.sh"
    exit 1
  fi
fi

if [ -x ./scripts/deployment/setup.sh ]; then
  log "INFO" "Running ./scripts/deployment/setup.sh"
  if ! bash ./scripts/deployment/setup.sh; then
    log "ERROR" "Setup failed"
    log "INFO" "To rollback, run: ${BKDIR}/restore.sh"
    exit 1
  fi
else
  log "WARN" "No executable setup.sh found — skipping."
fi

log "INFO" "Installer finished. Backup: ${BKDIR}"

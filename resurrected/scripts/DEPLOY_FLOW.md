# Deployment Flow Documentation

**CRITICAL: DO NOT REWRITE THESE SCRIPTS FROM SCRATCH**  
**If something breaks, make SURGICAL fixes only. These scripts work.**

---

## Working State Baseline

- Last verified working: 2026-02-14
- Git commit: `721de91` (canonical scripts established)
- **These scripts have been restored from working version**

---

## HOW TO DEPLOY TO A FRESH PI

**From your Windows workstation, in the Pi-Baseline directory:**

```powershell
$env:PI_HOST="pi-hostname" ; $env:PI_USER="piadmin" ; $env:REPO_DIR="/home/piadmin/Pi-Baseline" ; bash ./deploy.sh
```

**That's it.** The script will handle everything.

---

## Deployment Flow (Fresh Pi Setup)

### Phase 1: Workstation (deploy.sh)

1. **Commits/pushes** local changes to GitHub
2. **Creates remote directory** `/home/piadmin/Pi-Baseline` on Pi
3. **Installs workstation SSH key** to Pi's `~/.ssh/authorized_keys` (enables passwordless SSH)
4. **Copies `deploy-on-pi.sh`** to Pi
5. **Runs `deploy-on-pi.sh`** remotely, passing `REPO_URL` and `BRANCH`

**Password prompts: 1 time** (for initial setup combining all operations, then passwordless)

**TWO DIFFERENT SSH KEYS:**
- **Workstation → Pi**: Your workstation's public key in Pi's `authorized_keys` (handled by deploy.sh)
- **Pi → GitHub**: Pi generates its own key for GitHub (handled by setup-ssh-keys.sh on Pi)

### Phase 2: Pi (deploy-on-pi.sh)

1. **Creates timestamped backup** at `~/backups/<timestamp>/`
2. **Checks for `.git` directory**:
   - If missing: **Clones repo** from `REPO_URL` (fix applied 2026-02-14)
   - If exists: **Pulls latest** with `git pull --rebase`
3. **Handles GitHub SSH auth failures**:
   - Runs `setup-ssh-keys.sh` (from repo) to generate Pi's GitHub key
   - Prints key and **pauses** for you to add to GitHub
   - Retries git operation
4. **Runs `scripts/deployment/setup.sh`**

### Phase 3: Pi (setup.sh)

1. Installs system packages (git, python3, build tools)
2. Creates Python venv
3. **Calls `scripts/deployment/setup-ssh-keys.sh`**:
   - Creates `.ssh` directory if missing
   - Generates GitHub SSH key (ed25519)
   - Configures ssh-agent systemd service
   - **Displays public key for GitHub**
4. **Calls `scripts/deployment/setup-git.sh`**:
   - Configures git user.name and user.email
5. Installs Python dev dependencies (Black, Flake8, pytest)
6. Sets up pre-commit hooks

---

## Key Scripts (Do NOT Rewrite)

### deploy.sh
- **Purpose**: Workstation-side orchestration
- **Critical sections**:
  - Lines 70-93: `ensure_pi_keypair()` and `install_pi_keypair_on_pi()` - **DO NOT REMOVE `.ssh` directory creation**
  - Lines 110-138: Remote execution setup - passes `REPO_URL` to Pi

### deploy-on-pi.sh
- **Purpose**: Pi-side installer
- **Critical sections**:
  - Lines 103-115: Initial clone logic when `.git` doesn't exist - **DO NOT REMOVE**
  - Lines 116-187: GitHub key generation and prompt flow - **DO NOT REMOVE**
  - Lines 189-268: Git pull with retry logic - **WORKING AS-IS**
  - Lines 270-281: Calls `setup.sh` - **DO NOT MODIFY**

### scripts/deployment/setup.sh
- **Purpose**: Full Pi environment setup
- **Calls**: `setup-ssh-keys.sh` → `setup-git.sh` → Python venv → systemd services
- **DO NOT bypass this script** - it handles SSH keys correctly

---

## Common Issues & Solutions

### Issue: "Permission denied" during SSH key copy
**Solution**: Already fixed - deploy.sh creates `.ssh` directory first

### Issue: "not a git repository" on fresh Pi
**Solution**: Already fixed - deploy-on-pi.sh clones when `.git` missing

### Issue: "Could not read from remote repository" during clone
**Expected behavior**: Script generates GitHub key, prints it, and pauses for you to add to GitHub

---

## What NOT To Do

❌ **Don't remove the `.ssh` directory creation** from deploy.sh  
❌ **Don't remove the initial clone logic** from deploy-on-pi.sh  
❌ **Don't remove the GitHub key prompt/retry flow** from deploy-on-pi.sh  
❌ **Don't try to handle SSH key generation** in deploy.sh - let setup.sh do it  
❌ **Don't add complex clone logic** to deploy.sh - it belongs in deploy-on-pi.sh  

---

## Making Changes

If something breaks:

1. **Check git history**: `git log --oneline -- scripts/`
2. **Restore from working commit**: `git show 721de91:scripts/deploy-on-pi.sh`
3. **Make SURGICAL fixes only** - change the minimum needed
4. **Test on a fresh Pi** before committing

---

## Testing Checklist

Fresh Pi deployment test:
- [ ] Password prompts: 1-2 times only (not 10+)
- [ ] SSH keys copied successfully to Pi
- [ ] Repo cloned successfully on Pi
- [ ] GitHub key generated and displayed
- [ ] setup.sh completes successfully
- [ ] Subsequent deploys are passwordless

---

**Last updated**: 2026-02-14  
**Status**: Working with surgical fixes applied

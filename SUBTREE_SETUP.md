# Adding Pi-Configs to a Repository

This guide explains how to add Pi-Configs as a git subtree to a new repository (like Wallboards).

## Prerequisites

- The target repository should already exist and have a deploy.sh wrapper
- You have access to push to the target repository
- Git is installed and configured

## Steps

### 1. Add Pi-Configs as a subtree

From the root of your target repository:

```bash
git subtree add --prefix=Pi-Configs git@github.com:arlomiller/Pi-Configs.git main --squash
```

This creates a `Pi-Configs/` folder in your repo containing all Pi-Configs content (pi-list.json, select-pi scripts, shared-config).

### 2. Update the deploy.sh wrapper

Edit your repo's `deploy.sh` to reference the shared deploy script from Pi-Configs:

```bash
#!/usr/bin/env bash
# Thin wrapper that invokes the canonical shared deploy script
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHARED_DEPLOY="${SCRIPT_DIR}/Pi-Configs/shared-config/scripts/deploy.sh"

if [ ! -f "$SHARED_DEPLOY" ]; then
  echo "Error: Shared deploy script not found at $SHARED_DEPLOY"
  echo "Run: git subtree pull --prefix=Pi-Configs git@github.com:arlomiller/Pi-Configs.git main --squash"
  exit 1
fi

exec "$SHARED_DEPLOY" "$@"
```

### 3. Create deploy-select wrappers

**deploy-select.ps1** (PowerShell):

```powershell
# Interactive Pi selector + deploy wrapper
# Usage: .\deploy-select.ps1

$ErrorActionPreference = "Stop"

# Dot-source the Pi selector to set environment variables
. .\Pi-Configs\select-pi.ps1

# Verify variables were set
if (-not $env:PI_HOST -or -not $env:PI_USER -or -not $env:REPO_DIR) {
    Write-Host "Error: Environment variables not set. Pi selection may have failed." -ForegroundColor Red
    exit 1
}

# Run deployment
.\deploy.sh
```

**deploy-select.sh** (Git Bash):

```bash
#!/usr/bin/env bash
# Interactive Pi selector + deploy wrapper
# Usage: ./deploy-select.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Source the Pi selector to set environment variables
source "${SCRIPT_DIR}/Pi-Configs/select-pi.sh"

# Verify variables were set
if [ -z "${PI_HOST:-}" ] || [ -z "${PI_USER:-}" ] || [ -z "${REPO_DIR:-}" ]; then
    echo "Error: Environment variables not set. Pi selection may have failed." >&2
    exit 1
fi

# Run deployment
"${SCRIPT_DIR}/deploy.sh"
```

Make the bash script executable:
```bash
chmod +x deploy-select.sh
```

### 4. Update repository documentation

Update your repo's README.md to document the new deployment workflow:

```markdown
## Deployment

### Quick Deploy with Pi Selection

**PowerShell:**
```powershell
.\deploy-select.ps1
```

**Git Bash:**
```bash
./deploy-select.sh
```

### Manual Deploy (if environment variables already set)

```bash
./deploy.sh
```

### Select Pi without deploying

**PowerShell:**
```powershell
. .\Pi-Configs\select-pi.ps1
```

**Git Bash:**
```bash
source ./Pi-Configs/select-pi.sh
```
```

### 5. Commit and push changes

```bash
git add .
git commit -m "Add Pi-Configs subtree and deploy-select wrappers"
git push
```

## Updating Pi-Configs in the Future

When Pi-Configs is updated (new Pis added to pi-list.json, deploy scripts changed, etc.), pull the updates:

```bash
git subtree pull --prefix=Pi-Configs git@github.com:arlomiller/Pi-Configs.git main --squash
git push
```

## Troubleshooting

### "Shared deploy script not found"

Run the subtree pull command to sync Pi-Configs:
```bash
git subtree pull --prefix=Pi-Configs git@github.com:arlomiller/Pi-Configs.git main --squash
```

### "jq is not installed" (Git Bash only)

Install jq:
- **Chocolatey:** `choco install jq`
- **Scoop:** `scoop install jq`
- **Manual:** Download from https://stedolan.github.io/jq/

### Environment variables not persisting

Make sure to **dot-source** the selector script:
- PowerShell: `. .\Pi-Configs\select-pi.ps1` (note the leading dot and space)
- Bash: `source ./Pi-Configs/select-pi.sh`

Running without dot-sourcing/source will not persist the variables to your current session.

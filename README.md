# Pi-Configs shared setup

This folder contains shared configuration and deployment tools for managing multiple Raspberry Pis across workspaces (Pi-Baseline, Wallboards, etc.).

## Repository Structure

Pi-Configs is added to each workspace as a **git subtree**, ensuring all repos use identical shared configuration without manual syncing.

### Contents

- **pi-list.json**: Inventory of all Pis with connection details
- **select-pi.ps1 / select-pi.sh**: Interactive Pi selector scripts
- **shared-config/**: Canonical deploy scripts and VS Code settings (synced via git subtree)

## Quick Start

### 1. Select a Pi for deployment

**PowerShell:**
```powershell
. .\Pi-Configs\select-pi.ps1
```

**Git Bash:**
```bash
source ./Pi-Configs/select-pi.sh
```

This displays a numbered menu of Pis from `pi-list.json` and sets these environment variables for your current session:
- `PI_HOST` - Pi hostname or IP address
- `PI_USER` - SSH username
- `REPO_DIR` - Remote repository path (auto-detected if not specified)

### 2. Deploy to the selected Pi

After selecting a Pi, run the repo-specific deployment wrapper:

**PowerShell:**
```powershell
.\deploy-select.ps1
```

**Git Bash:**
```bash
./deploy-select.sh
```

Or manually run `./deploy.sh` if environment variables are already set.

## Managing the Pi Inventory

Edit [pi-list.json](pi-list.json) to add, remove, or modify Pis:

```json
[
  {
    "name": "pi-server-FDT",
    "host": "192.168.11.50",
    "user": "piadmin",
    "repo_dir": null
  },
  {
    "name": "pi-display-01",
    "host": "pi-display-01.local",
    "user": "piadmin",
    "repo_dir": "/home/piadmin/Wallboards"
  }
]
```

**Field descriptions:**
- `name`: Display name for the Pi
- `host`: Hostname or IP address
- `user`: SSH username
- `repo_dir`: Remote path to the repository (set to `null` to auto-detect as `/home/<user>/<repo-name>`)

## Adding Pi-Configs to a New Repository

See [SUBTREE_SETUP.md](SUBTREE_SETUP.md) for instructions on adding Pi-Configs as a git subtree to new workspaces.

## Updating Pi-Configs in Existing Repositories

After making changes to Pi-Configs (editing pi-list.json, shared-config, etc.), update all repos:

**In each workspace (Pi-Baseline, Wallboards, etc.):**
```bash
git subtree pull --prefix=Pi-Configs git@github.com:arlomiller/Pi-Configs.git main --squash
```

This merges the latest Pi-Configs changes into your workspace.

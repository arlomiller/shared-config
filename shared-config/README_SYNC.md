# shared-config sync and usage

This repo contains canonical `.vscode` settings and tasks shared across local projects.

Usage
- Submodule: added to each repo at `shared-config/`.
- Sync locally: run `sync-settings.ps1 <target-repo>` (Windows) or `sync-settings.sh <target-repo>` (Unix) from `C:/Repos/PiConfigs`.

Auto-sync on push
- Each repo can include the provided GitHub Action (`.github/workflows/sync-shared-config.yml`) to copy `.vscode` from this submodule into the repo on push and commit changes automatically.

Auto-sync on workspace open
- VS Code doesn't natively run tasks on folder open. Options:
  - Use an extension such as "Run On Folder Open" (recommended) and configure it to run the sync script.
  - Keep a short README note and run the `Tasks: Run Task` → `Sync shared .vscode` when you open the workspace.

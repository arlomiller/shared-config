# Copilot Instructions Task — reuse info

This file explains how to use the provided workspace task that quickly shows the repository's Copilot/agent instructions (`.github/copilot-instructions.md`) and how to copy it into another workspace.

How it works
- The task added to the `Pi-Baseline` workspace (`.vscode/tasks.json`) runs a shell command to print the contents of `.github/copilot-instructions.md` into the VS Code Tasks terminal. There are two tasks: one for Windows (`type`) and one for Unix (`cat`).

Run the task
1. Open the workspace in VS Code.
2. Open the Command Palette (Ctrl+Shift+P) and run `Tasks: Run Task`.
3. Choose `Open Copilot Instructions (Windows)` or `Open Copilot Instructions (Unix)` depending on your system.

Copying the task to another workspace
1. Create (or open) the folder for the other workspace in VS Code.
2. Create a `.vscode` directory at the workspace root if it doesn't exist.
3. Create a `tasks.json` file under `.vscode` and paste the following content (or merge with existing tasks):

```json
{
  "version": "2.0.0",
  "tasks": [
    {
      "label": "Open Copilot Instructions (Windows)",
      "type": "shell",
      "command": "type .github\\copilot-instructions.md",
      "presentation": { "echo": true, "reveal": "always", "panel": "shared" },
      "problemMatcher": []
    },
    {
      "label": "Open Copilot Instructions (Unix)",
      "type": "shell",
      "command": "cat .github/copilot-instructions.md",
      "presentation": { "echo": true, "reveal": "always", "panel": "shared" },
      "problemMatcher": []
    }
  ]
}
```

Notes and customization
- If your workspace root does not contain the `.github/copilot-instructions.md` file, update the `command` path to point to the correct location (for example `..\\other-repo\\.github\\copilot-instructions.md`).
- On systems where neither `type` nor `cat` are available, replace the `command` with a suitable command or script that prints the file (for example `powershell -Command Get-Content .github\\copilot-instructions.md`).

Want me to add the same `tasks.json` directly into another workspace folder here? I can do that if you point me to the target path.

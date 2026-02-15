#!/usr/bin/env bash
set -euo pipefail
# Copy canonical files from shared-config into target repo (defaults to current dir)
TARGET_DIR=${1:-$(pwd)}
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
for f in .gitattributes .gitignore .pre-commit-config.yaml; do
  if [ -f "${SCRIPT_DIR}/${f}" ]; then
    cp "${SCRIPT_DIR}/${f}" "${TARGET_DIR}/${f}"
    echo "Copied ${f} -> ${TARGET_DIR}/${f}"
  fi
done

# Also sync .vscode folder if present in shared-config
if [ -d "${SCRIPT_DIR}/.vscode" ]; then
  DST_DIR="${TARGET_DIR}/.vscode"
  mkdir -p "${DST_DIR}"
  cp -a "${SCRIPT_DIR}/.vscode/." "${DST_DIR}/"
  echo "Copied .vscode -> ${DST_DIR}"
fi

# Also copy the sync script itself and README_SYNC.md if present
for sf in sync-shared-files.sh README_SYNC.md; do
  if [ -f "${SCRIPT_DIR}/${sf}" ]; then
    cp "${SCRIPT_DIR}/${sf}" "${TARGET_DIR}/${sf}"
    echo "Copied ${sf} -> ${TARGET_DIR}/${sf}"
  fi
done

# Also copy shared validation workflow if present
if [ -f "${SCRIPT_DIR}/.github/workflows/validation.yml" ]; then
  DST_DIR="${TARGET_DIR}/.github/workflows"
  mkdir -p "${DST_DIR}"
  cp "${SCRIPT_DIR}/.github/workflows/validation.yml" "${DST_DIR}/validation.yml"
  echo "Copied .github/workflows/validation.yml -> ${DST_DIR}/validation.yml"
fi

echo "Sync complete. Remember to review and commit changes in the target repo."

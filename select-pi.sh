#!/usr/bin/env bash
# select-pi.sh
# Select a Pi from the inventory and set environment variables for the current session
# Usage: source ./select-pi.sh  (or . ./select-pi.sh to persist environment variables)

set -euo pipefail

# Locate pi-list.json relative to this script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PI_LIST_PATH="${SCRIPT_DIR}/pi-list.json"

if [ ! -f "$PI_LIST_PATH" ]; then
    echo "Error: pi-list.json not found at $PI_LIST_PATH" >&2
    return 1
fi

# Check for jq
if ! command -v jq >/dev/null 2>&1; then
    echo "Error: jq is not installed. Please install jq to use this script." >&2
    echo "  Windows (via Chocolatey): choco install jq" >&2
    echo "  Windows (via Scoop): scoop install jq" >&2
    return 1
fi

# Load the Pi list
PI_COUNT=$(jq 'length' "$PI_LIST_PATH")

if [ "$PI_COUNT" -eq 0 ]; then
    echo "Error: pi-list.json is empty" >&2
    return 1
fi

# Display menu
echo ""
echo "Available Pis:"
for ((i=0; i<PI_COUNT; i++)); do
    name=$(jq -r ".[$i].name" "$PI_LIST_PATH")
    host=$(jq -r ".[$i].host" "$PI_LIST_PATH")
    user=$(jq -r ".[$i].user" "$PI_LIST_PATH")
    echo "  [$((i+1))] $name ($user@$host)"
done

# Prompt for selection
echo ""
read -r -p "Enter number: " selection
index=$((selection - 1))

if [ "$index" -lt 0 ] || [ "$index" -ge "$PI_COUNT" ]; then
    echo "Error: Invalid selection" >&2
    return 1
fi

# Extract selected Pi details
SELECTED_NAME=$(jq -r ".[$index].name" "$PI_LIST_PATH")
export PI_HOST=$(jq -r ".[$index].host" "$PI_LIST_PATH")
export PI_USER=$(jq -r ".[$index].user" "$PI_LIST_PATH")
REPO_DIR_JSON=$(jq -r ".[$index].repo_dir" "$PI_LIST_PATH")

# Default REPO_DIR if not specified (null or empty)
if [ "$REPO_DIR_JSON" = "null" ] || [ -z "$REPO_DIR_JSON" ]; then
    # Auto-detect current repo name from git or directory name
    if git rev-parse --show-toplevel >/dev/null 2>&1; then
        REPO_NAME=$(basename "$(git rev-parse --show-toplevel)")
    else
        REPO_NAME=$(basename "$PWD")
    fi
    export REPO_DIR="/home/${PI_USER}/${REPO_NAME}"
else
    export REPO_DIR="$REPO_DIR_JSON"
fi

echo ""
echo "Selected: $SELECTED_NAME"
echo "  PI_HOST=$PI_HOST"
echo "  PI_USER=$PI_USER"
echo "  REPO_DIR=$REPO_DIR"
echo ""
echo "Environment variables set for current session."

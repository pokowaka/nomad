#!/bin/bash
#
# Runs the remote verification script on the Nomad router.
# Usage: ./run_tests.sh [ROUTER_IP]

# --- Configuration & Safety ---
set -e # Exit on first error

ROUTER_IP="${1:-192.168.10.1}"
ROUTER_DEST="root@${ROUTER_IP}"
REMOTE_SCRIPT_PATH="/tmp/verify_state.sh"
LOCAL_SCRIPT_PATH="tests/verify_state.sh"

echo "--- Running Remote Test Suite on ${ROUTER_IP} ---"

if [ ! -f "$LOCAL_SCRIPT_PATH" ]; then
    echo "Error: Test script not found at ${LOCAL_SCRIPT_PATH}" >&2
    exit 1
fi

echo "[1/2] Copying test script to router..."
scp "${LOCAL_SCRIPT_PATH}" "${ROUTER_DEST}:${REMOTE_SCRIPT_PATH}"

echo "[2/2] Executing test script on router..."
# The remote script will print its own pass/fail messages.
# We add a final message here based on the script's exit code.
if ssh "${ROUTER_DEST}" "chmod +x ${REMOTE_SCRIPT_PATH} && ${REMOTE_SCRIPT_PATH}"; then
    echo "--- SUCCESS: All remote checks passed. ---"
else
    echo "--- FAILURE: One or more remote checks failed. Review output above. ---" >&2
    # The script will have already exited with a non-zero code from the ssh command failing.
fi

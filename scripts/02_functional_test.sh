#!/bin/bash
# ==========================================================
# Script 02: Functional Test — Does the TURN server work?
# Run from your RPi5 AFTER the VM is up and Coturn is running
# Usage: bash 02_functional_test.sh <CIVO_VM_IP> <TURN_SECRET>
# Example: bash 02_functional_test.sh 103.57.8.123 abc123def456
# ==========================================================

TURN_IP=${1:?"ERROR: Provide the Civo VM IP. Usage: $0 <IP> <SECRET>"}
TURN_SECRET=${2:?"ERROR: Provide TURN secret. Usage: $0 <IP> <SECRET>"}
TURN_USER="poctest"
TURN_PORT="3478"

echo "================================================"
echo " Civo Coturn PoC — Functional Test"
echo " Target: ${TURN_IP}:${TURN_PORT}"
echo "================================================"

# --- Test 1: Basic ping ---
echo ""
echo "[TEST 1] Ping (basic connectivity)..."
ping -c 5 ${TURN_IP}
echo ""

# --- Test 2: STUN port reachability ---
echo "[TEST 2] STUN port reachability (TCP 3478)..."
if nc -zv -w 5 ${TURN_IP} ${TURN_PORT} 2>&1 | grep -q "open\|succeeded"; then
  echo "  ✅ PASS — Port 3478 is open"
else
  echo "  ❌ FAIL — Port 3478 is not reachable (check firewall)"
fi

# --- Test 3: turnutils_uclient — 1 session smoke test ---
echo ""
echo "[TEST 3] TURN relay smoke test (1 session for 10 seconds)..."
timeout 15 turnutils_uclient \
  -m 1 \
  -y \
  -n 100 \
  -e 8.8.8.8 \
  -u ${TURN_USER} \
  -w ${TURN_SECRET} \
  ${TURN_IP} \
  && echo "  ✅ PASS — TURN relay is working" \
  || echo "  ❌ FAIL — RELAY failed (check Coturn logs on VM)"

echo ""
echo "================================================"
echo " Functional test complete."
echo ""
echo " Next step: Open https://webrtc.github.io/samples/src/content/peerconnection/trickle-ice/"
echo " Add this TURN server:"
echo "   URI:      turn:${TURN_IP}:3478"
echo "   Username: ${TURN_USER}"
echo "   Password: ${TURN_SECRET}"
echo " Look for 'relay' candidates in the output to confirm."
echo "================================================"

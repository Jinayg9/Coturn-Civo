#!/bin/bash
# ==========================================================
# Script 03: Load Test — Concurrent TURN Sessions
# Uses turnutils_uclient (comes with coturn package)
#
# Run from your RPi5.
# Usage: bash 03_load_test.sh <CIVO_VM_IP> <TURN_SECRET>
# Example: bash 03_load_test.sh 103.57.8.123 abc123
#
# turnutils_uclient flags used in this script:
#   -m <N>   Number of concurrent clients (fake locks/phones)
#   -y       Client-to-client mode: each pair talks through the relay
#            (simulates lock→TURN→phone without needing a peer server)
#   -l <N>   Payload size in bytes per packet (1000 ≈ real video frame)
#   -z <N>   Interval between packets in ms (10ms = 100 pkts/sec = ~800kbps)
#   -u/-w    Username and password for TURN authentication
#   -v       Verbose: print each message sent/received
#   -s       Use TURN Send method instead of channels (tests different code path)
#   -c       Disable RTCP (we only care about RTP/media, same as real WebRTC)
#   -O       DOS/intense mode: flood as fast as possible (stress ceiling test)
#   -n <N>   Number of messages per client before exiting
#   -T       Use TCP for relay transport (not UDP) — tests TCP fallback path
# ==========================================================

TURN_IP=${1:?"ERROR: Provide TURN IP. Usage: $0 <IP> <SECRET>"}
TURN_SECRET=${2:?"ERROR: Provide TURN secret. Usage: $0 <IP> <SECRET>"}
TURN_USER="poctest"
RESULTS_DIR="../results"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOGFILE="${RESULTS_DIR}/load_test_${TIMESTAMP}.log"

mkdir -p ${RESULTS_DIR}

log() { echo "$@" | tee -a ${LOGFILE}; }

log "================================================"
log " Civo Coturn PoC — Load Test"
log " Target: ${TURN_IP}"
log " Started: $(date)"
log "================================================"

# ---------------------------------------------------------
# Helper: run one load test round
# Args: $1=sessions, $2=duration_seconds, $3=extra_flags
# ---------------------------------------------------------
run_test() {
  local SESSIONS=$1
  local DURATION=$2
  local EXTRA_FLAGS=$3
  local LABEL=$4
  log ""
  log "--- [${LABEL}] ${SESSIONS} sessions for ${DURATION}s ---"
  timeout ${DURATION} turnutils_uclient \
    -m ${SESSIONS} \
    -e 8.8.8.8 \
    -c \
    -l 1000 \
    -z 10 \
    -u ${TURN_USER} \
    -w ${TURN_SECRET} \
    ${EXTRA_FLAGS} \
    ${TURN_IP} 2>&1 | tee -a ${LOGFILE}
  log "[Done: ${LABEL} at $(date)]"
}

# ==========================================================
# TEST SUITE 1: UDP Ramp-Up (Standard Mode)
# Tests the main path — UDP relay, which is what WebRTC uses
# ==========================================================
log ""
log "=========================================="
log "SUITE 1: UDP Ramp-Up Test"
log "Tests normal WebRTC relay path over UDP"
log "=========================================="

run_test 10  30  ""  "WARMUP-10"
run_test 50  60  ""  "RAMP-50"
run_test 100 60  ""  "RAMP-100"
run_test 150 60  ""  "RAMP-150"
run_test 200 120 ""  "TARGET-200"   # ← This is your production target
run_test 300 60  ""  "STRESS-300"   # ← Push past target to find breaking point

# ==========================================================
# TEST SUITE 2: Send Method (vs Channels)
# TURN has two ways to send data: "channels" (default, efficient)
# and "send method" (older, slightly more overhead).
# Real browsers sometimes use Send method — this tests that path.
# ==========================================================
log ""
log "=========================================="
log "SUITE 2: Send Method Test (-s flag)"
log "Tests TURN Send method (alternate code path)"
log "=========================================="

run_test 100 60 "-s" "SEND-METHOD-100"
run_test 200 60 "-s" "SEND-METHOD-200"

# ==========================================================
# TEST SUITE 3: TCP Relay Transport
# By default TURN relays UDP. But some networks block UDP entirely
# (e.g. strict corporate firewalls). In that case the client
# requests TCP relay instead (-T flag). This tests that fallback.
# ==========================================================
log ""
log "=========================================="
log "SUITE 3: TCP Relay Transport (-T flag)"
log "Tests what happens when UDP is blocked"
log "(TCP is slower but the fallback must still work)"
log "=========================================="

run_test 50  60 "-T" "TCP-RELAY-50"
run_test 100 60 "-T" "TCP-RELAY-100"

# ==========================================================
# TEST SUITE 4: Bandwidth Ceiling / Intense Mode
# -O flag = "DOS mode" — floods packets as fast as possible
# ignoring the -z interval. This finds the raw throughput
# ceiling of the Civo instance's network port.
# WARNING: This will spike to 1Gbps attempt. Run briefly.
# ==========================================================
log ""
log "=========================================="
log "SUITE 4: Bandwidth Ceiling Test (-O flag)"
log "Floods 50 sessions at maximum speed"
log "Watch bmon on the VM — look for port throttling"
log "=========================================="

run_test 50 30 "-O" "CEILING-FLOOD-50"

# ==========================================================
# TEST SUITE 5: Large Payload Simulation
# Increasing -l to 1400 bytes tests behavior near the
# ethernet MTU (Maximum Transmission Unit = 1500 bytes).
# Packets above MTU get fragmented, which adds relay overhead.
# Real 720p video frames are often near this size.
# ==========================================================
log ""
log "=========================================="
log "SUITE 5: Large Payload / MTU Test (-l 1400)"
log "Tests near-MTU packet sizes (realistic 720p video)"
log "=========================================="

run_test 100 60 "-l 1400 -z 10" "MTU-PAYLOAD-100"
run_test 200 60 "-l 1400 -z 10" "MTU-PAYLOAD-200"

log ""
log "================================================"
log " All load tests complete."
log " Results saved to: ${LOGFILE}"
log ""
log " KEY THINGS TO CHECK ON THE VM DURING TESTS:"
log "   ssh ubuntu@${TURN_IP}"
log "   docker logs coturn-poc -f     ← Live Coturn output"
log "   htop                           ← CPU: watch 'si' (SoftIRQ)"
log "   bmon                           ← Bandwidth in Mbps"
log "   telnet 127.0.0.1 5766 → ps     ← Active relay sessions"
log "================================================"

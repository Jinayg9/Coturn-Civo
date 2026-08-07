#!/bin/bash
# ==========================================================
# Script 04: Network Quality Test — Jitter, Packet Loss, Latency
# Run from your RPi5 AFTER starting iperf3 server on Civo VM:
#   ssh ubuntu@<VM_IP> "iperf3 -s -D"
# Usage: bash 04_network_quality.sh <CIVO_VM_IP>
# ==========================================================

TURN_IP=${1:?"ERROR: Provide TURN IP. Usage: $0 <IP>"}
RESULTS_DIR="../results"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
LOGFILE="${RESULTS_DIR}/network_quality_${TIMESTAMP}.log"

mkdir -p ${RESULTS_DIR}

# Known Indian ISP IPs for route testing
JIO_IP="49.44.0.1"
AIRTEL_IP="182.72.0.0"
BSNL_IP="117.96.0.0"

echo "================================================" | tee ${LOGFILE}
echo " Civo Coturn PoC — Network Quality Tests" | tee -a ${LOGFILE}
echo " Target: ${TURN_IP}" | tee -a ${LOGFILE}
echo " Time: $(date)" | tee -a ${LOGFILE}
echo "================================================" | tee -a ${LOGFILE}

# --- Test 1: RTT Latency (ping) ---
echo "" | tee -a ${LOGFILE}
echo "[TEST 1] RTT Latency — 100 pings to TURN server" | tee -a ${LOGFILE}
echo "  Target: <80ms average, <5ms mdev (jitter)" | tee -a ${LOGFILE}
ping -c 100 -i 0.2 ${TURN_IP} | tail -2 | tee -a ${LOGFILE}

# --- Test 2: UDP Jitter & Packet Loss (the most important test) ---
echo "" | tee -a ${LOGFILE}
echo "[TEST 2] UDP Jitter & Packet Loss — 5 minute test at 280 Mbps" | tee -a ${LOGFILE}
echo "  Target: Jitter <20ms, Packet Loss <1%" | tee -a ${LOGFILE}
echo "  NOTE: Make sure iperf3 server is running on the VM first!" | tee -a ${LOGFILE}
iperf3 \
  -u \
  -c ${TURN_IP} \
  -b 280M \
  -t 300 \
  -i 30 \
  --json | tee -a ${LOGFILE} | python3 -c "
import sys, json
try:
  d = json.load(sys.stdin)
  end = d.get('end', {})
  sum_data = end.get('sum', {})
  jitter = sum_data.get('jitter_ms', 'N/A')
  loss = sum_data.get('lost_percent', 'N/A')
  print(f'  --> Jitter: {jitter:.2f}ms  |  Lost: {loss:.2f}%')
  if float(jitter) < 20 and float(loss) < 1:
    print('  --> PASS ✅')
  else:
    print('  --> FAIL ❌')
except:
  print('  (raw output above — check jitter_ms and lost_percent fields)')
"

# --- Test 3: Route tracing to Indian ISPs ---
echo "" | tee -a ${LOGFILE}
echo "[TEST 3] Route trace from TURN server to Jio, Airtel, BSNL" | tee -a ${LOGFILE}
echo "  (Run this from the Civo VM via SSH)" | tee -a ${LOGFILE}
echo "" | tee -a ${LOGFILE}
echo "  SSH into your Civo VM and run:" | tee -a ${LOGFILE}
echo "    mtr --report --report-cycles 50 ${JIO_IP}    # Jio" | tee -a ${LOGFILE}
echo "    mtr --report --report-cycles 50 ${AIRTEL_IP} # Airtel" | tee -a ${LOGFILE}
echo "    mtr --report --report-cycles 50 ${BSNL_IP}   # BSNL" | tee -a ${LOGFILE}
echo "" | tee -a ${LOGFILE}
echo "  Look for: How many hops? Any >5% packet loss at any hop?" | tee -a ${LOGFILE}

# --- Test 4: Peak hours test reminder ---
echo "" | tee -a ${LOGFILE}
echo "[TEST 4] ⚠️  IMPORTANT — Repeat Tests at Peak Hours" | tee -a ${LOGFILE}
echo "  Run this script again at these times:" | tee -a ${LOGFILE}
echo "    20:00 IST (8 PM)  — Indian internet peak" | tee -a ${LOGFILE}
echo "    22:00 IST (10 PM) — Heaviest peak" | tee -a ${LOGFILE}
echo "    02:00 IST (2 AM)  — Off-peak (baseline comparison)" | tee -a ${LOGFILE}

echo "" | tee -a ${LOGFILE}
echo "================================================" | tee -a ${LOGFILE}
echo " Network quality tests complete." | tee -a ${LOGFILE}
echo " Results saved to: ${LOGFILE}" | tee -a ${LOGFILE}
echo "================================================" | tee -a ${LOGFILE}

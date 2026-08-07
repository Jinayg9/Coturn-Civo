#!/bin/bash
# ==========================================================
# Script 05: Daily Soak Monitor — Run on the CIVO VM itself
# Set this up as a daily cron job on the Civo VM
# Usage: bash 05_soak_monitor.sh
# Add to cron: 0 8 * * * bash /home/ubuntu/civo-poc/scripts/05_soak_monitor.sh
# ==========================================================

RESULTS_DIR="/home/ubuntu/soak_results"
LOGFILE="${RESULTS_DIR}/soak_$(date +%Y%m%d).log"

mkdir -p ${RESULTS_DIR}

echo "============================================" >> ${LOGFILE}
echo " Daily Soak Report — $(date)" >> ${LOGFILE}
echo "============================================" >> ${LOGFILE}

# --- CPU & Memory snapshot ---
echo "" >> ${LOGFILE}
echo "[CPU & MEMORY]" >> ${LOGFILE}
top -bn1 | head -8 >> ${LOGFILE}

# --- Disk usage ---
echo "" >> ${LOGFILE}
echo "[DISK USAGE]" >> ${LOGFILE}
df -h >> ${LOGFILE}

# --- Network interface stats (total bytes since boot) ---
echo "" >> ${LOGFILE}
echo "[NETWORK STATS (total since boot)]" >> ${LOGFILE}
cat /proc/net/dev | grep -E "eth0|ens" >> ${LOGFILE}

# --- Docker container status ---
echo "" >> ${LOGFILE}
echo "[DOCKER STATUS]" >> ${LOGFILE}
docker ps >> ${LOGFILE}
docker stats --no-stream coturn-poc >> ${LOGFILE}

# --- Coturn log tail (last 20 lines) ---
echo "" >> ${LOGFILE}
echo "[COTURN LOG (last 20 lines)]" >> ${LOGFILE}
docker logs coturn-poc --tail 20 2>> ${LOGFILE}

# --- Uptime ---
echo "" >> ${LOGFILE}
echo "[UPTIME]" >> ${LOGFILE}
uptime >> ${LOGFILE}

echo "" >> ${LOGFILE}
echo "============================================" >> ${LOGFILE}
echo " End of daily report" >> ${LOGFILE}
echo "============================================" >> ${LOGFILE}

echo "Soak report written to ${LOGFILE}"

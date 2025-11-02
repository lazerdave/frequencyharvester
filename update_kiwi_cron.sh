#!/usr/bin/env bash
set -euo pipefail

LOG="/home/pi/Shipping_Forecast_SDR_Recordings.log"
PY=/usr/bin/python3
SCAN=/home/pi/weekly_scan_198.py
REC=/home/pi/record_198_from_best.py

# Helper: convert a London clock time (HH:MM) to today's *local* HH MM
to_local_hm() {
  local lon_time="$1"
  local ts
  ts=$(TZ=Europe/London date -d "today ${lon_time}" +%s)
  date -d "@${ts}" +'%H %M'
}

# Resolve today's local times for London targets
read LH_REC0 LM_REC0 <<<"$(to_local_hm "00:47")"
read LH_SCAN0 LM_SCAN0 <<<"$(to_local_hm "00:42")"   # 5 min before 00:47
read LH_REC1 LM_REC1 <<<"$(to_local_hm "05:19")"

BLOCK_START="# >>> KIWI-SDR AUTO (managed) >>>"
BLOCK_END="# <<< KIWI-SDR AUTO (managed) <<<"

# Build the managed cron block (note the escaped $ signs: \$f, \$t, \$(...))
MANAGED=$(cat <<EOF
${BLOCK_START}
# Recompute this block daily just after midnight local:
2 0 * * * /bin/bash /home/pi/update_kiwi_cron.sh >> ${LOG} 2>&1

# Scan ~5 min before 00:47 London
${LM_SCAN0} ${LH_SCAN0} * * * { echo -e "\\n\\n==== \$(TZ=Europe/London date) ==== SCAN START ====" >> ${LOG}; ${PY} ${SCAN} >> ${LOG} 2>&1; }

# Record at 00:47 London
${LM_REC0} ${LH_REC0} * * * { echo -e "\\n==== \$(TZ=Europe/London date) ==== RECORD START ====" >> ${LOG}; ${PY} ${REC} >> ${LOG} 2>&1; }

# Record at 05:19 London
${LM_REC1} ${LH_REC1} * * * { echo -e "\\n==== \$(TZ=Europe/London date) ==== MORNING RECORD START ====" >> ${LOG}; ${PY} ${REC} >> ${LOG} 2>&1; }

# Weekly log trim (keep last 20000 lines), Sunday 00:20 local
20 0 * * 0 /bin/bash -lc 'f="${LOG}"; t=\$(mktemp); tail -n 20000 "\$f" > "\$t" && mv "\$t" "\$f"'
${BLOCK_END}
EOF
)

# Preserve anything outside the managed block; replace the block
EXISTING=$(crontab -l 2>/dev/null || true)
CLEANED=$(printf "%s\n" "$EXISTING" | awk -v s="${BLOCK_START}" -v e="${BLOCK_END}" '
  $0==s {inb=1; next} $0==e {inb=0; next} !inb {print}
')

printf "%s\n%s\n" "$CLEANED" "$MANAGED" | crontab -
echo "[$(date)] Updated crontab for London targets (00:47 & 05:19). Local times -> scan ${LH_SCAN0}:${LM_SCAN0}, record ${LH_REC0}:${LM_REC0} & ${LH_REC1}:${LM_REC1}." >> "${LOG}"

#!/usr/bin/env bash
# health_check.sh v2.2 - Linux System Health Monitor
# Grades CPU load, memory, disk, services and network as PASS / WARN / FAIL.
# Exit code: 0 = all PASS, 1 = at least one WARN, 2 = at least one FAIL.
# Every run is saved to logs/health-YYYY-MM-DD.log and summarised in logs/history.log.

set -u

# --- Track limits (thresholds) ---
# WARN at or above the first number, FAIL at or above the second.
DISK_WARN=80;  DISK_FAIL=90     # percent of root disk used
MEM_WARN=80;   MEM_FAIL=90      # percent of memory used
LOAD_WARN=1.0; LOAD_FAIL=2.0    # 1-minute load per CPU core

# --- Network test targets ---
DNS_TEST_HOST="github.com"      # name that must resolve (DNS check)
NET_TEST_HOST="github.com"      # host that must accept HTTPS on port 443 (internet check)

# --- Logging ---
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
LOG_DIR="${LOG_DIR:-$SCRIPT_DIR/logs}"   # override with: LOG_DIR=/path ./health_check.sh
KEEP_DAYS=14                             # delete daily logs older than this
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/health-$(date '+%Y-%m-%d').log"
# Send everything printed below to the screen AND the daily log file.
exec > >(tee -a "$LOG_FILE") 2>&1

WORST=0   # worst result so far: 0 = PASS, 1 = WARN, 2 = FAIL

# report LEVEL "message"  - prints one graded line and remembers the worst level
report() {
  local level=$1; shift
  printf '[%-4s] %s\n' "$level" "$*"
  case $level in
    WARN) if [ "$WORST" -lt 1 ]; then WORST=1; fi ;;
    FAIL) WORST=2 ;;
  esac
}

# grade VALUE WARN FAIL  - prints PASS, WARN or FAIL (handles decimals like 0.25)
grade() {
  awk -v v="$1" -v w="$2" -v f="$3" 'BEGIN { if (v >= f) print "FAIL"; else if (v >= w) print "WARN"; else print "PASS" }'
}

echo "=== System Health Report ==="
echo "Host:   $(hostname)"
echo "Date:   $(date '+%Y-%m-%d %H:%M:%S %Z')"
echo "Uptime: $(uptime -p)"

echo ""
echo "--- CPU ---"
CORES=$(nproc)
LOAD1=$(cut -d ' ' -f1 /proc/loadavg)
LOAD_PER_CORE=$(awk -v l="$LOAD1" -v c="$CORES" 'BEGIN { printf "%.2f", l / c }')
report "$(grade "$LOAD_PER_CORE" "$LOAD_WARN" "$LOAD_FAIL")" "Load $LOAD1 on $CORES core(s) = $LOAD_PER_CORE per core"

echo ""
echo "--- Memory ---"
MEM_PCT=$(awk '/^MemTotal:/ {t=$2} /^MemAvailable:/ {a=$2} END { printf "%d", (t - a) * 100 / t }' /proc/meminfo)
report "$(grade "$MEM_PCT" "$MEM_WARN" "$MEM_FAIL")" "Memory ${MEM_PCT}% used ($(free -h | awk 'NR==2 {print $7}') available)"

echo ""
echo "--- Disk ---"
DISK_PCT=$(df --output=pcent / | tail -1 | tr -dc '0-9')
report "$(grade "$DISK_PCT" "$DISK_WARN" "$DISK_FAIL")" "Disk / ${DISK_PCT}% used ($(df -h --output=used,size / | tail -1 | awk '{print $1 " of " $2}'))"

echo ""
echo "--- Services ---"
if command -v systemctl >/dev/null 2>&1 && [ -d /run/systemd/system ]; then
  FAILED=$(systemctl --failed --no-legend --plain 2>/dev/null | awk '{print $1}' | paste -sd ' ')
  if [ -z "$FAILED" ]; then
    report PASS "No failed services"
  else
    report FAIL "Failed services: $FAILED"
  fi
else
  report WARN "systemd not running here; services not checked"
fi

echo ""
echo "--- Network ---"
GATEWAY=$(ip route show default 2>/dev/null | awk '/^default/ {print $3; exit}')
if [ -z "$GATEWAY" ]; then
  report FAIL "No default route (no gateway configured)"
else
  # Ping may be blocked by a firewall, so the real test is layer 2:
  # did the gateway answer ARP (does it have a MAC address in the neighbour table)?
  ping -c 1 -W 2 "$GATEWAY" >/dev/null 2>&1
  if ip neigh show "$GATEWAY" 2>/dev/null | grep -q lladdr; then
    report PASS "Gateway $GATEWAY reachable"
  else
    report FAIL "Gateway $GATEWAY not reachable"
  fi
fi

if getent hosts "$DNS_TEST_HOST" >/dev/null 2>&1; then
  report PASS "DNS resolves $DNS_TEST_HOST"
else
  report FAIL "DNS cannot resolve $DNS_TEST_HOST"
fi

if timeout 5 bash -c "exec 3<>/dev/tcp/$NET_TEST_HOST/443" 2>/dev/null; then
  report PASS "Internet: HTTPS to $NET_TEST_HOST works"
else
  report FAIL "Internet: cannot reach $NET_TEST_HOST on port 443"
fi

echo ""
case $WORST in
  0) OVERALL=PASS ;;
  1) OVERALL=WARN ;;
  *) OVERALL=FAIL ;;
esac
echo "OVERALL: $OVERALL"
echo ""

# One line per run in history.log, so trends are easy to scan: date, host, result.
echo "$(date '+%Y-%m-%d %H:%M:%S %Z')  $(hostname)  $OVERALL" >> "$LOG_DIR/history.log"
# Housekeeping: remove daily logs older than KEEP_DAYS (history.log is kept).
find "$LOG_DIR" -name 'health-*.log' -type f -mtime +"$KEEP_DAYS" -delete 2>/dev/null

exit "$WORST"

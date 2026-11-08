#!/usr/bin/env bash
# health_check.sh - Linux System Health Monitor
# Reports CPU, memory, disk, and service health.

echo "=== System Health Report ==="
echo "Host:   $(hostname)"
echo "Date:   $(date '+%Y-%m-%d %H:%M:%S')"
echo "Uptime: $(uptime -p)"


echo ""
echo "--- CPU ---"
echo "Cores:        $(nproc)"
echo "Load (1/5/15 min): $(cut -d ' ' -f1-3 /proc/loadavg)"

echo ""
echo "--- Memory ---"
free -h | awk 'NR==2 {print "Used: " $3 " of " $2 " (available: " $7 ")"}'

echo ""
echo "--- Disk ---"
df -h / | awk 'NR==2 {print "Root (/): " $3 " used of " $2 " (" $5 " full)"}'

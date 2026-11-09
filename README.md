# Linux System Health Monitor

A single Bash script that checks a Linux server and grades each result **PASS / WARN / FAIL**, so a person can read it at a glance and automation can act on its **exit code**.

Built and tested on Debian 13 inside a Proxmox VE LXC container, as part of a home-lab portfolio.

## What it checks

| Area | Check | WARN | FAIL |
|---|---|---|---|
| CPU | 1-minute load **per core** | ≥ 1.0 | ≥ 2.0 |
| Memory | % used (total minus *available*, so cache isn't counted) | ≥ 80 % | ≥ 90 % |
| Disk | % used on `/` | ≥ 80 % | ≥ 90 % |
| Services | `systemctl --failed` | systemd not running | any failed unit |
| Network | Default gateway answers ARP (layer 2, works even if ping is blocked) | | not reachable |
| Network | DNS resolves a test name (`getent hosts`) | | no answer |
| Network | HTTPS (TCP 443) to a test host, using Bash `/dev/tcp` | | no connection |

Thresholds and test hosts are variables at the top of the script.

## Logs

Every run is shown on screen **and** saved:

| File | Contents |
|---|---|
| `logs/health-YYYY-MM-DD.log` | full report of every run that day |
| `logs/history.log` | one line per run: date, host, PASS/WARN/FAIL |

Daily logs older than 14 days (`KEEP_DAYS`) are deleted automatically; `history.log` is kept. Use another folder with `LOG_DIR=/path ./health_check.sh`. The `logs/` folder is git-ignored, so results are never committed.

```
$ tail -3 logs/history.log
2026-11-09 17:36:03 UTC  telemetry  PASS
```

## Usage

```bash
git clone https://github.com/Sleyk6/linux-system-health-monitor.git
cd linux-system-health-monitor
./health_check.sh
echo "exit code: $?"
```

### JSON output
For dashboards, scripts or phone shortcuts, `--json` prints one JSON object instead of the text report. The text report still goes to the daily log.

```bash
./health_check.sh --json
```
```json
{"host":"lab-server","time":"2026-11-09T22:11:59Z","overall":"PASS","exit_code":0,
 "checks":[{"check":"cpu","status":"PASS","message":"Load 0.00 on 1 core(s) = 0.00 per core"},
           {"check":"memory","status":"PASS","message":"Memory 6% used (924Mi available)"},
           {"check":"disk","status":"PASS","message":"Disk / 11% used (757M of 7.8G)"}]}
```
Abbreviated above (3 of 7 checks). Check names: `cpu`, `memory`, `disk`, `services`, `gateway`, `dns`, `internet`. Example with `jq`: `./health_check.sh --json | jq -r '.checks[] | select(.status != "PASS") | .message'`

No packages to install: it uses only standard tools (`bash`, `awk`, `df`, `free`, `ip`, `getent`, `ping`, `systemctl`, `timeout`). No root access is needed for the checks.

## Sample output

```
=== System Health Report ===
Host:   telemetry
Date:   2026-11-09 17:36:03 UTC
Uptime: up 38 minutes

--- CPU ---
[PASS] Load 0.09 on 1 core(s) = 0.09 per core

--- Memory ---
[PASS] Memory 2% used (1.0Gi available)

--- Disk ---
[PASS] Disk / 11% used (757M of 7.8G)

--- Services ---
[PASS] No failed services

--- Network ---
[PASS] Gateway 10.0.0.1 reachable
[PASS] DNS resolves github.com
[PASS] Internet: HTTPS to github.com works

OVERALL: PASS
```
(Gateway address changed to an example.)

## Exit codes

| Code | Meaning |
|---|---|
| 0 | every check PASS |
| 1 | at least one WARN, no FAIL |
| 2 | at least one FAIL |
| 3 | unknown option (see `--help`) |

This lets cron jobs, monitoring tools or scripts react without parsing text, for example:

```bash
./health_check.sh > /dev/null || echo "health check needs attention"
```

## How it was tested

- Normal run on the target container: all PASS, exit 0.
- Forced WARN (disk limit lowered to 1 %): OVERALL WARN, exit 1.
- Forced FAIL (load limit set to 0): OVERALL FAIL, exit 2.
- Run on a host with no network or systemd: network checks FAIL and services WARN, as expected.
- Logging: two runs produce one daily file with both reports and two `history.log` lines; a log file aged 20 days is removed; `LOG_DIR` override writes to the chosen folder; exit codes unchanged.
- JSON mode: output validated with `python3 -m json.tool`; same exit code as text mode; text report still written to the log; unknown option exits 3.
- `bash -n` syntax check before every commit.

## Version history

| Version | Change |
|---|---|
| v1 | Report host, uptime, CPU, memory, disk |
| v2 | PASS/WARN/FAIL grading, thresholds, exit codes |
| v2.1 | Service, gateway, DNS and internet checks |
| v2.2 | Daily log files, run history, automatic log clean-up |
| v2.3 | `--json` output mode, `--help`, exit code 3 for bad options |

## Roadmap

- Schedule it (cron / systemd timer) and keep a history

## License

MIT, see [LICENSE](LICENSE).

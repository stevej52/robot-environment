#!/usr/bin/env bash
# Rosie's drives, analysed on H2-Host minutes after they happen (Steve, 2026-09-30: the host
# as her analyst). rosie-drives.timer runs this every 15 minutes:
#
#   1. if she is up: pull new recordings (~/bags, incremental) and ~/audit into the mirror
#   2. for every recording in the mirror without analysis/summary.md: drive_report (the
#      robot's own reporter, run here with the current code), the heading-drift check
#      (extract_heading + heading_drift) and the lidar-odometry gap check, into
#      mirror/bags/<drive>/analysis/, and a summary.md that puts the headlines first
#
# Nothing runs on the robot except rsync. A recording still being written (no metadata.yaml
# yet) is left for the next round. Log: ~/rosie-backup/drives.log.
set +u                                   # ROS's setup.bash reads unset variables
ROBOT=${ROBOT:-jeston@192.168.1.7}
KEY=${KEY:-$HOME/.ssh/id_ed25519_rosie}
BASE=${BASE:-$HOME/rosie-backup}
TOOLS=$HOME/ros2_ws/src/jetnano_robot/tools/drive_analysis
PY=$HOME/venv-analysis/bin/python
SSH="ssh -i $KEY -o BatchMode=yes -o ConnectTimeout=8"
LOG=$BASE/drives.log
mkdir -p "$BASE/mirror/bags"
log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*" | tee -a "$LOG"; }

# 1. new recordings (and the watchdog's event log, small, so the health page is current)
if $SSH "$ROBOT" true 2>/dev/null; then
    rsync -a -e "$SSH" "$ROBOT:bags/" "$BASE/mirror/bags/" 2>>"$LOG" || log "rsync bags FAILED"
    rsync -a -e "$SSH" "$ROBOT:audit/" "$BASE/mirror/audit/" 2>>"$LOG" || true
    rsync -a -e "$SSH" "$ROBOT:watchdog/" "$BASE/mirror/watchdog/" 2>>"$LOG" || true
    echo "Rosie answered at $(date '+%Y-%m-%d %H:%M'), recordings pulled" > "$BASE/last-pull.txt"
else
    echo "Rosie did not answer at $(date '+%Y-%m-%d %H:%M') (off, or not on the Wi-Fi); showing what was pulled before" > "$BASE/last-pull.txt"
fi

# 2. analysis
source /opt/ros/jazzy/setup.bash
source "$HOME/ros2_ws/install/setup.bash"
export ROS_DOMAIN_ID=${ANALYSIS_DOMAIN:-79}          # its own domain: not a participant in her graph
for bag in "$BASE"/mirror/bags/drive-*; do
    [ -d "$bag" ] || continue
    case "$bag" in *-extra) continue ;; esac
    [ -f "$bag/analysis/summary.md" ] && continue
    [ -f "$bag/metadata.yaml" ] || continue           # still recording, or half copied
    mcap=$(ls "$bag"/*.mcap 2>/dev/null | head -1)
    [ -n "$mcap" ] || continue
    name=$(basename "$bag")
    out="$bag/analysis"
    mkdir -p "$out"
    log "$name: analysing"
    timeout 900 nice -n 10 ros2 run jetnano_bringup drive_report "$bag" > "$out/report.txt" 2>&1 \
        || log "$name: drive_report FAILED"
    if timeout 600 nice -n 10 "$PY" "$TOOLS/extract_heading.py" "$mcap" "$out/heading.npz" > "$out/heading.txt" 2>&1; then
        timeout 300 "$PY" "$TOOLS/heading_drift.py" "$out/heading.npz" >> "$out/heading.txt" 2>&1 || true
    fi
    timeout 600 nice -n 10 "$PY" "$TOOLS/lidar_odom_gaps.py" "$mcap" > "$out/lidar_gaps.txt" 2>&1 || true
    {
        echo "# $name"
        echo
        echo "## Report (drive_report)"
        cat "$out/report.txt"
        echo
        echo "## Heading drift (the last lines of heading_drift)"
        tail -n 12 "$out/heading.txt" 2>/dev/null
        echo
        echo "## Lidar odometry gaps"
        head -n 30 "$out/lidar_gaps.txt" 2>/dev/null
    } > "$out/summary.md"
    log "$name: done - $(grep -m1 -oE '^guard: [^,]*' "$out/report.txt" 2>/dev/null)"
done

# 3. the health page, so it shows the drives and events just pulled (the nightly backup
#    writes it too, with the fresh journal)
python3 "$BASE/rosie-health.py" "$BASE" > /dev/null 2>>"$LOG" || log "health page FAILED"

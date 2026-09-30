#!/usr/bin/env bash
# Rosie's nightly backup, run on H2-Host (always on) by rosie-backup.timer as user steve.
#
#   1. mirror: rsync of what she makes and what is not in git - maps, recordings, audit
#      and watchdog logs, sounds, voice prints, calibration notes, the Isaac workspace's
#      launch copies - into ~/rosie-backup/mirror/ (incremental: only what changed)
#   2. repos: bare mirrors of the three GitHub repositories, updated (needs no robot)
#   3. Sundays: the full redacted archive (robot-environment scripts/backup_robot_state.sh,
#      run on the robot, then fetched), kept for four weeks
#
# If she is off, 1 and 3 are skipped quietly and the log says so; the timer tries again
# the next night. Nothing here touches the robot's own files. Secrets: the archive step
# redacts keys itself, and NetworkManager's Wi-Fi files are never copied.
#
#   bash rosie-backup.sh            # run it now; log in ~/rosie-backup/log.txt
set -u
ROBOT=${ROBOT:-jeston@192.168.1.7}
KEY=${KEY:-$HOME/.ssh/id_ed25519_rosie}
BASE=${BASE:-$HOME/rosie-backup}
SSH="ssh -i $KEY -o BatchMode=yes -o ConnectTimeout=8"
LOG=$BASE/log.txt
mkdir -p "$BASE/mirror" "$BASE/repos" "$BASE/archives"
log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*" | tee -a "$LOG"; }

# 2. the repositories, first: needs only GitHub
for repo in jetnano_robot ros2_gpu_robot robot-environment; do
    if [ -d "$BASE/repos/$repo.git" ]; then
        (cd "$BASE/repos/$repo.git" && git remote update --prune >/dev/null 2>&1) \
            && log "repo $repo: mirror updated" || log "repo $repo: update FAILED"
    else
        git clone -q --mirror "https://github.com/stevej52/$repo.git" "$BASE/repos/$repo.git" \
            && log "repo $repo: mirror cloned" || log "repo $repo: clone FAILED"
    fi
done

# is she up?
if ! $SSH "$ROBOT" true 2>/dev/null; then
    log "robot not reachable: mirror and archive skipped (next try tomorrow night)"
    exit 0
fi

# 1. the mirror
for d in maps bags audit watchdog sounds voice/voiceprints calibration nav_logs tools maps3d respeaker \
         workspaces/isaac_ros-dev/cuvslam_nvblox_d435.launch.py workspaces/isaac_ros-dev/nvblox_base.yaml \
         workspaces/isaac_ros-dev/firmware .ros/where_am_i.env; do
    if $SSH "$ROBOT" "[ -e '$d' ]" 2>/dev/null; then
        mkdir -p "$BASE/mirror/$(dirname "$d")"
        # --exclude=analysis: the drive analysis lives in the mirror (rosie-drives writes
        # bags/<drive>/analysis/ here, the robot has no such folder), so --delete must not
        # take it away again - which it did on the first real run, 2026-09-30
        rsync -a --delete --exclude=analysis -e "$SSH" "$ROBOT:$d" "$BASE/mirror/$(dirname "$d")/" 2>>"$LOG" \
            && log "mirror $d: ok" || log "mirror $d: rsync FAILED"
    fi
done
# the robot's launch settings (ROBOT_ARGS), without its secrets
$SSH "$ROBOT" "sudo -n grep -vE 'KEY|TOKEN|SECRET|PASS' /etc/default/jetnano-robot" > "$BASE/mirror/jetnano-robot.default" 2>/dev/null \
    && log "mirror /etc/default/jetnano-robot (redacted): ok"
# her log for the day, for the health check: warnings and the lines that tell the story
mkdir -p "$BASE/mirror/journal"
$SSH "$ROBOT" "journalctl --since -24h --no-hostname -o short -p warning 2>/dev/null; \
    journalctl --since -24h --no-hostname -o short 2>/dev/null | grep -E 'battery level|powering off|CTRL-EVENT-DISCONNECTED|Started jetnano-robot|Starting jetnano-robot|active urbs|Check failed|process has died|running hot|jetnano-robot-stop:'" \
    | sort -u > "$BASE/mirror/journal/$(date +%F).txt" 2>/dev/null && log "journal: $(wc -l < "$BASE/mirror/journal/$(date +%F).txt") lines"
du -sh "$BASE/mirror" 2>/dev/null | awk '{print "mirror size", $1}' | tee -a "$LOG"

# 3. Sundays: the full archive
if [ "$(date +%u)" = 7 ] || [ "${FULL:-}" = 1 ]; then
    out="rosie-robot-state-$(date +%Y%m%d).tar.zst"
    if $SSH "$ROBOT" "cd ~/robot-environment && SKIP_BAGS='drive-*' bash scripts/backup_robot_state.sh /tmp/$out" >>"$LOG" 2>&1 \
        && rsync -a -e "$SSH" "$ROBOT:/tmp/$out" "$BASE/archives/" 2>>"$LOG"; then
        $SSH "$ROBOT" "rm -f /tmp/$out"
        log "archive $out: $(du -h "$BASE/archives/$out" | cut -f1)"
        find "$BASE/archives" -name 'rosie-robot-state-*.tar.zst' -mtime +28 -delete
    else
        log "archive: FAILED (see above)"
    fi
fi
# the daily health check, from the mirror (runs even when she was off: it says so)
python3 "$BASE/rosie-health.py" "$BASE" > /dev/null 2>>"$LOG" && log "health: $BASE/health/latest.md" || log "health: FAILED"
log "done"

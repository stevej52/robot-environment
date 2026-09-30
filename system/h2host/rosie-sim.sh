#!/usr/bin/env bash
# Rosie's nightly test drive in the simulator, on H2-Host (Steve, 2026-09-30: the host as
# her test bench). rosie-sim.timer runs this at 02:30:
#
#   1. bring the workspace to GitHub's main and build it (the code she will get next)
#   2. start the whole stack in Gazebo, headless, with Nav2 (jetnano_gazebo full_stack.launch.py,
#      ROS domain 77 - the real robot is 7)
#   3. drive the standard route with the same tools a floor drive uses: four legs with
#      nav_goal --rescue round the east half of the 12 x 10 m testbed (the ramps are on the
#      west), then nav_park back to the start
#   4. write sim/<date>/summary.md - every leg's result line, the park's result - and
#      a one-line verdict in ~/rosie-backup/sim/latest.txt; the launch log stays beside it
#
# Everything has a timeout; the launch is stopped at the end whatever happened. A failed
# leg is not an error of this script: it is the finding.
#
#   ~/rosie-backup/rosie-sim.sh              run it now (about 5 minutes)
set +u
BASE=${BASE:-$HOME/rosie-backup}
WS=$HOME/ros2_ws
export ROS_DOMAIN_ID=${SIM_DOMAIN:-77}
DAY=$(date +%F)
OUT=$BASE/sim/$DAY
mkdir -p "$OUT"
LOG=$BASE/sim.log
log() { echo "$(date '+%Y-%m-%d %H:%M:%S') $*" | tee -a "$LOG"; }

# 1. the code
for repo in jetnano_robot ros2_gpu_robot ros2_pca9685; do
    [ -d "$WS/src/$repo" ] && (cd "$WS/src/$repo" && git pull -q --ff-only 2>>"$LOG") || log "$repo: pull failed"
done
source /opt/ros/jazzy/setup.bash
cd "$WS" || exit 1
log "building $(cd src/jetnano_robot && git log --oneline -1)"
if ! nice -n 10 colcon build --packages-up-to jetnano_gazebo jetnano_navigation jetnano_bringup jetnano_teleop > "$OUT/build.log" 2>&1; then
    log "BUILD FAILED: see $OUT/build.log"
    echo "$DAY build failed" > "$BASE/sim/latest.txt"
    exit 0
fi
source "$WS/install/setup.bash"

# 2. the stack
setsid ros2 launch jetnano_gazebo full_stack.launch.py headless:=true navigation:=true > "$OUT/launch.log" 2>&1 &
LAUNCH=$!
stop_stack() {
    kill -INT -- -"$LAUNCH" 2>/dev/null
    for _ in $(seq 1 30); do kill -0 "$LAUNCH" 2>/dev/null || break; sleep 1; done
    kill -KILL -- -"$LAUNCH" 2>/dev/null
    pkill -KILL -f "^gz sim" 2>/dev/null
}
trap stop_stack EXIT
up=0
for _ in $(seq 1 60); do
    sleep 5
    timeout 8 ros2 action list 2>/dev/null | grep -q navigate_to_pose && { up=1; break; }
    kill -0 "$LAUNCH" 2>/dev/null || break
done
if [ "$up" != 1 ]; then
    log "Nav2 did not come up in the simulator: see $OUT/launch.log"
    echo "$DAY stack did not start" > "$BASE/sim/latest.txt"
    exit 0
fi
sleep 20                                        # SLAM's first map, the costmaps

# 3. the route
{
    echo "# Simulator drive, $DAY ($(cd "$WS/src/jetnano_robot" && git log --oneline -1))"
    echo
} > "$OUT/summary.md"
ok=0; n=0
while read -r name g; do
    n=$((n+1))
    timeout 300 ros2 run jetnano_navigation nav_goal $g 120 --rescue > "$OUT/leg$n.log" 2>&1
    line=$(grep -m1 -E "^result" "$OUT/leg$n.log" || tail -n 1 "$OUT/leg$n.log")
    echo "- leg $n $name ($g): $line" >> "$OUT/summary.md"
    grep -q "^result SUCCEEDED" "$OUT/leg$n.log" && ok=$((ok+1))
done <<'LEGS'
east 3.0 0.0 0
south-east 3.0 -3.0 -90
south 0.0 -3.0 180
back 0.0 -1.0 90
LEGS
timeout 400 ros2 run jetnano_navigation nav_park > "$OUT/park.log" 2>&1
park=$(grep -E "^parked|^the last leg|result SUCCEEDED after" "$OUT/park.log" | tail -n 2 | tr '\n' ' ')
echo "- park: $park" >> "$OUT/summary.md"
grep -q "^parked" "$OUT/park.log" && parked=yes || parked=no
verdict="$DAY: legs $ok/$n, parked $parked"
echo "$verdict" > "$BASE/sim/latest.txt"
{ echo; echo "**$verdict**"; } >> "$OUT/summary.md"
log "$verdict"

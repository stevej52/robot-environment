#!/usr/bin/env bash
# Is Rosie's install what the repositories say it is? (the review of 2026-10-03: "verify
# effective units, drop-ins, installed binaries, and deployed revisions")
#
#     verify_install.sh            on Rosie; prints one line per check, OK or BAD, exit 1 on any BAD
#
# Checks: the units and their drop-ins are installed and enabled as the repo has them, the
# service environment really carries the UDP-only profile, the installed binaries carry the
# strings their sources must have, the workspace checkouts are at their origin heads, and the
# build is not older than its sources.
set +u
BAD=0
ok()  { echo "  OK   $*"; }
bad() { echo "  BAD  $*"; BAD=1; }
WS=$HOME/ros2_ws
ENV=$HOME/robot-environment

echo "== units"
for u in jetson-clocks isaac-vo jetnano-robot jetnano-nav2 wifi-watchdog; do
    if [ -f /etc/systemd/system/$u.service ]; then
        src=$WS/src/jetnano_robot/jetnano_bringup/systemd/$u.service
        [ -f "$src" ] && ! cmp -s "$src" /etc/systemd/system/$u.service && bad "$u.service differs from the repo" || ok "$u.service installed"
        [ "$(systemctl is-enabled $u 2>/dev/null)" = enabled ] && ok "$u enabled" || bad "$u not enabled"
    else
        bad "$u.service missing from /etc/systemd/system"
    fi
done
[ -f /etc/systemd/system/jetnano-voice.service ] && ok "jetnano-voice.service installed" || bad "jetnano-voice.service missing"
for u in jetnano-robot jetnano-voice jetnano-localize jetnano-slam; do
    for d in "$ENV"/system/$u.service.d/*.conf; do
        [ -f "$d" ] || continue
        inst=/etc/systemd/system/$u.service.d/$(basename "$d")
        [ -f "$inst" ] && cmp -s "$d" "$inst" && ok "$u drop-in $(basename "$d")" || bad "$u drop-in $(basename "$d") missing or differs"
    done
done
systemctl show -p Environment jetnano-robot | grep -q FASTRTPS_DEFAULT_PROFILES_FILE=/etc/jetnano/fastdds_udp_only.xml \
    && ok "jetnano-robot runs UDP-only" || bad "jetnano-robot has no FASTRTPS_DEFAULT_PROFILES_FILE"
cmp -s "$ENV"/system/fastdds_udp_only.xml /etc/jetnano/fastdds_udp_only.xml && ok "/etc/jetnano/fastdds_udp_only.xml" || bad "/etc/jetnano/fastdds_udp_only.xml missing or differs"
grep -q FASTRTPS_DEFAULT_PROFILES_FILE "$HOME/.bashrc" && ok "~/.bashrc exports the profile" || bad "~/.bashrc does not export the profile"

echo "== installed binaries carry their sources' strings"
B=$WS/install/jetnano_watchdog/lib/jetnano_watchdog
check_str() { strings "$1" 2>/dev/null | grep -q "$2" && ok "$(basename "$1"): $2" || bad "$(basename "$1") lacks '$2' (rebuild jetnano_watchdog)"; }
check_str $B/grid_to_points planner_wall_margin_m
check_str $B/grid_to_points planner_camera_value
check_str $B/safety_monitor navigate_through_poses
for f in $WS/src/jetnano_robot/jetnano_watchdog/src/*.cpp; do
    [ "$f" -nt "$B/$(basename "${f%.cpp}")" ] && bad "$(basename "$f") newer than its binary" || true
done
# python packages install as symlinks: the import path must resolve into the sources
for pkg in jetnano_bringup jetnano_navigation jetnano_teleop ros2_pca9685; do
    p=$(cd "$WS" && . /opt/ros/jazzy/setup.bash && . install/setup.bash && python3 -c "import $pkg, os; print(os.path.realpath(os.path.dirname($pkg.__file__)))" 2>/dev/null)
    case "$p" in */src/*|*/build/*) ok "$pkg imports from $p" ;; *) bad "$pkg imports from '$p' (not a symlink install: colcon build --symlink-install)" ;; esac
done

echo "== checkouts at their origin heads"
for r in "$WS/src/jetnano_robot" "$WS/src/ros2_pca9685" "$WS/src/ros2_gpu_robot" "$ENV"; do
    [ -d "$r/.git" ] || { bad "$r is not a checkout"; continue; }
    (cd "$r" && git fetch -q origin 2>/dev/null; L=$(git rev-parse HEAD); R=$(git rev-parse @{u} 2>/dev/null); D=$(git status --porcelain | wc -l)
     [ "$L" = "$R" ] && ok "$(basename "$r") at origin ${L:0:7}" || bad "$(basename "$r") HEAD ${L:0:7} != origin ${R:0:7}"
     [ "$D" = 0 ] || bad "$(basename "$r") has $D uncommitted change(s)")
done
echo "== container"
docker exec isaac_vo grep -q visual_preset /workspaces/isaac_ros-dev/cuvslam_nvblox_d435.launch.py 2>/dev/null && ok "container camera launch has the preset" || bad "container camera launch lacks the preset (install_isaac_ros_46.sh copies it)"
[ "$BAD" = 0 ] && echo "ALL OK" || { echo "SOMETHING IS OFF"; exit 1; }

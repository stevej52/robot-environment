#!/usr/bin/env bash
# The robot's two system settings that no other install script writes:
#
#   bash scripts/install_system_settings.sh            (on the Jetson)
#
#   /etc/docker/daemon.json      nvidia as Docker's default runtime, so the
#                                isaac_vo container gets the GPU however it is
#                                started (it refused to start at boot under
#                                runc, 2026-09-24)
#   /etc/systemd/logind.conf.d/robot-power-button.conf
#                                the case's power button shuts down even though
#                                no one is logged in to answer the dialog
#
# RemoveIPC=no (logind) is written by install_ros2_jazzy.sh; the services by
# install_isaac_ros_46.sh --units. Password-free sudo for the robot's user is
# a choice this repository does not make for you - see REBUILD.md.
#
# Changes take effect at the next boot (restarting logind or Docker by hand
# ends desktop sessions and running containers).
set -euo pipefail
HERE=$(cd "$(dirname "$0")/.." && pwd)

if [ -f /etc/docker/daemon.json ] && ! grep -q '"default-runtime": "nvidia"' /etc/docker/daemon.json; then
    echo "/etc/docker/daemon.json exists with other settings: merge $HERE/system/docker-daemon.json by hand"
else
    sudo install -D -m 644 "$HERE/system/docker-daemon.json" /etc/docker/daemon.json
    echo "Docker: nvidia is the default runtime (after a reboot or: sudo systemctl restart docker)"
fi
sudo install -D -m 644 "$HERE/system/logind-robot-power-button.conf" /etc/systemd/logind.conf.d/robot-power-button.conf
echo "logind: power button shuts down (after a reboot)"

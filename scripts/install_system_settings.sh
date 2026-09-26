#!/usr/bin/env bash
# The robot's system settings that no other install script writes:
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
#   /etc/firmware/nvidia/ga10b   a real copy of the GPU firmware, and
#   /etc/apt/apt.conf.d/99-rosie-etc-firmware  that refreshes it after every
#                                package change. JetPack 7.2's kernel command
#                                line looks in /etc/firmware first, which the
#                                installer never creates; the fallback through
#                                the /lib symlink failed with ELOOP on 2 of 31
#                                boots and the GPU never started (2026-09-23 and
#                                -26; NVIDIA-AI-IOT/jetson-ai-lab issue #427)
#   /etc/nvidia-container-toolkit/nvidia-cdi-refresh.env
#                                the boot-time GPU description (CDI spec) is
#                                always generated in Jetson (csv) mode; auto
#                                sometimes chose nvml and wrote none
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
sudo mkdir -p /etc/firmware/nvidia
sudo cp -a /usr/lib/firmware/nvidia/ga10b /etc/firmware/nvidia/
sudo install -D -m 644 "$HERE/system/apt-99-rosie-etc-firmware" /etc/apt/apt.conf.d/99-rosie-etc-firmware
echo "GPU firmware: real copy in /etc/firmware, refreshed after every apt run (used from the next boot)"
sudo install -D -m 644 "$HERE/system/nvidia-cdi-refresh.env" /etc/nvidia-container-toolkit/nvidia-cdi-refresh.env
echo "CDI spec: always generated in csv (Jetson) mode (from the next boot)"

#!/usr/bin/env bash
# Copyright 2026 stevej52
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# Set up NVIDIA Isaac ROS 4.6 on the Jetson, in a container, for the robot's
# GPU visual odometry (cuVSLAM). Jetson only: the host PC has no NVIDIA GPU and
# runs the CPU odometry instead (robot.launch.py vo:=rtabmap).
#
# This is the one place the robot's "binaries only" rule is bent, and it is
# bent inside NVIDIA's own container: Isaac ROS pins a RealSense driver built
# from source with the RSUSB backend, and the image builds it. Nothing on the
# host's ROS 2 Jazzy install changes. Isaac ROS 4.6 is the last release for
# Jazzy (5.0 moved to ROS 2 Lyrical), so everything is pinned to release-4.6.
# Background and numbers: ros2_gpu_robot/cuvslam_d435/README.md.
#
# Run it as your normal user on the Jetson (it calls sudo where needed).
# Re-running is safe; each step checks before it acts.
#
# Usage: scripts/install_isaac_ros_46.sh [options]
#   --build        build the container image (about 1.5 h on the Orin, 19 GB)
#   --container    create the isaac_vo container from the image and install
#                  cuVSLAM into it (commits image isaac_vo:4.6)
#   --units        install and enable the systemd units from jetnano_robot
#                  (isaac-vo.service, jetnano-robot.service)
#   --all          all of the above, in order
#   --dry-run      print what would be done, change nothing
#   -h, --help     this text
#
# With no option it does the cheap part only: apt repository, isaac-ros-cli,
# docker group, workspace, launch files. Then run --build, --container, --units.

set -euo pipefail

ISAAC_RELEASE=release-4.6
ISAAC_KEY_URL=https://isaac.download.nvidia.com/isaac-ros/repos.key
ISAAC_KEYRING=/usr/share/keyrings/nvidia-isaac-ros.gpg
ISAAC_LIST=/etc/apt/sources.list.d/nvidia-isaac-ros-4.6.list
ISAAC_WS=${ISAAC_ROS_WS:-$HOME/workspaces/isaac_ros-dev/}
GPU_ROBOT_DIR=${GPU_ROBOT_DIR:-$HOME/ros2_ws/src/ros2_gpu_robot}
JETNANO_ROBOT_DIR=${JETNANO_ROBOT_DIR:-$HOME/ros2_ws/src/jetnano_robot}
CONTAINER=isaac_vo
IMAGE=isaac_vo:4.6
BUILT_IMAGE=cached_isaac_run_dev_image_local:latest
# The camera's JPEG stream and the browser feed (cuvslam_d435/README.md, "Watching the camera")
VIDEO_PKGS="ros-jazzy-compressed-image-transport ros-jazzy-compressed-depth-image-transport ros-jazzy-web-video-server"

DO_BUILD=0; DO_CONTAINER=0; DO_UNITS=0; DRY_RUN=0

usage() { sed -n '/^# Usage:/,/^$/p' "$0" | sed 's/^# \{0,1\}//'; }

for arg in "$@"; do
    case "$arg" in
        --build) DO_BUILD=1 ;;
        --container) DO_CONTAINER=1 ;;
        --units) DO_UNITS=1 ;;
        --all) DO_BUILD=1; DO_CONTAINER=1; DO_UNITS=1 ;;
        --dry-run) DRY_RUN=1 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "unknown option: $arg" >&2; usage; exit 2 ;;
    esac
done

say() { echo "==> $*"; }
run() { if [ "$DRY_RUN" -eq 1 ]; then echo "    (dry run) $*"; else "$@"; fi; }

# ---- 0. This must be the Jetson, with JetPack 7.2 ---------------------------
[ "$(uname -m)" = "aarch64" ] || { echo "this is $(uname -m), not a Jetson; the GPU odometry is Jetson only" >&2; exit 1; }
grep -q '^# R39' /etc/nv_tegra_release 2>/dev/null || { echo "Jetson Linux R39 (JetPack 7.2) expected; see docs/environment.md section 5" >&2; exit 1; }
dpkg -s nvidia-jetpack >/dev/null 2>&1 || { echo "nvidia-jetpack is not installed: sudo apt-get install -y nvidia-jetpack" >&2; exit 1; }
command -v docker >/dev/null || { echo "docker not found; it comes with nvidia-jetpack (nvidia-container)" >&2; exit 1; }

# ---- 1. Isaac ROS 4.6 apt repository and the CLI ----------------------------
if [ -f "$ISAAC_LIST" ] && grep -q "$ISAAC_RELEASE" "$ISAAC_LIST"; then
    say "apt source for Isaac ROS $ISAAC_RELEASE already present"
else
    say "adding the Isaac ROS $ISAAC_RELEASE apt source"
    run sh -c "curl -fsSL $ISAAC_KEY_URL | sudo gpg --dearmor --yes -o $ISAAC_KEYRING"
    run sh -c "echo 'deb [signed-by=$ISAAC_KEYRING] https://isaac.download.nvidia.com/isaac-ros/$ISAAC_RELEASE noble-jetpack main' | sudo tee $ISAAC_LIST >/dev/null"
    run sudo apt-get update -qq
fi
if dpkg -s isaac-ros-cli >/dev/null 2>&1; then
    say "isaac-ros-cli already installed ($(dpkg-query -W -f='${Version}' isaac-ros-cli))"
else
    say "installing isaac-ros-cli"
    run sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq isaac-ros-cli
fi

# ---- 2. docker group, workspace, launch files -------------------------------
if id -nG "$USER" | grep -qw docker; then
    say "$USER is in the docker group"
else
    say "adding $USER to the docker group (log out and in again afterwards)"
    run sudo usermod -aG docker "$USER"
fi
grep -q 'ISAAC_ROS_WS' ~/.bashrc || run sh -c "echo 'export ISAAC_ROS_WS=\${HOME}/workspaces/isaac_ros-dev/' >> ~/.bashrc"
run mkdir -p "$ISAAC_WS/src"
if [ -d "$GPU_ROBOT_DIR/cuvslam_d435" ]; then
    say "copying the launch files, nvblox parameters and DDS profile into $ISAAC_WS"
    run cp "$GPU_ROBOT_DIR/cuvslam_d435/cuvslam_d435_stereo.launch.py" \
           "$GPU_ROBOT_DIR/cuvslam_d435/cuvslam_nvblox_d435.launch.py" \
           "$GPU_ROBOT_DIR/cuvslam_d435/nvblox_base.yaml" \
           "$GPU_ROBOT_DIR/cuvslam_d435/fastdds_udp_only.xml" "$ISAAC_WS/"
    run mkdir -p ~/.config/isaac-ros-cli
    run cp "$GPU_ROBOT_DIR/cuvslam_d435/isaac-ros-cli-config.yaml" ~/.config/isaac-ros-cli/config.yaml
else
    echo "warning: $GPU_ROBOT_DIR/cuvslam_d435 not found; clone ros2_gpu_robot into ~/ros2_ws/src first" >&2
fi
if [ "$(isaac-ros status 2>/dev/null | awk '/^mode:/{print $2}')" = "docker" ]; then
    say "isaac-ros CLI already in docker mode"
else
    say "isaac-ros init docker"
    run sudo isaac-ros init docker --yes
fi

# ---- 3. The image (long) ----------------------------------------------------
if [ "$DO_BUILD" -eq 1 ]; then
    if docker image inspect "$BUILT_IMAGE" >/dev/null 2>&1; then
        say "image $BUILT_IMAGE already built"
    else
        say "building the Isaac ROS image with the RealSense layer (about 1.5 h, 19 GB)"
        run env ISAAC_ROS_WS="$ISAAC_WS" isaac-ros activate --build-local --build-only
    fi
fi

# ---- 4. The container, with cuVSLAM installed and committed -----------------
if [ "$DO_CONTAINER" -eq 1 ]; then
    if ! docker image inspect "$IMAGE" >/dev/null 2>&1; then
        docker image inspect "$BUILT_IMAGE" >/dev/null 2>&1 || { echo "no image; run with --build first" >&2; exit 1; }
        say "creating $CONTAINER from $BUILT_IMAGE and installing cuVSLAM into it"
        run docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
        run docker run -d --restart no --privileged --network host --ipc host --runtime nvidia \
            -e ROS_DOMAIN_ID="${ROS_DOMAIN_ID:-7}" -e ISAAC_ROS_WS=/workspaces/isaac_ros-dev \
            -e NVIDIA_VISIBLE_DEVICES=all -e NVIDIA_DRIVER_CAPABILITIES=all \
            -e HOST_USER_UID="$(id -u)" -e HOST_USER_GID="$(id -g)" -e USER="$USER" -e TERM=xterm \
            -v "$ISAAC_WS:/workspaces/isaac_ros-dev" -v /dev/bus/usb:/dev/bus/usb -v /dev/input:/dev/input \
            --workdir /workspaces/isaac_ros-dev --entrypoint /usr/local/bin/scripts/workspace-entrypoint.sh \
            --name "$CONTAINER" "$BUILT_IMAGE" sleep infinity
        # cuVSLAM, and nvblox's node + messages only: the ros-jazzy-isaac-ros-nvblox
        # meta-package pulls the people-segmentation DNN stack (Triton, gigabytes).
        run docker exec -u root "$CONTAINER" bash -c "apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq ros-jazzy-isaac-ros-visual-slam ros-jazzy-nvblox-ros ros-jazzy-nvblox-msgs $VIDEO_PKGS"
        run docker commit "$CONTAINER" "$IMAGE"
        run docker rm -f "$CONTAINER"
    fi
    # NVIDIA's realsense_splitter (routes projector-on/off frames to nvblox/cuVSLAM)
    # is not shipped as a deb: build it from the release-4.6 checkout, inside the
    # container, into the mounted workspace. nvblox_base.yaml comes from the same repo.
    if [ ! -f "$ISAAC_WS/install/realsense_splitter/lib/librealsense_splitter_component.so" ]; then
        say "building realsense_splitter inside the container"
        [ -d "$ISAAC_WS/src/isaac_ros_nvblox" ] || run git clone -q --depth 1 -b release-4.6 https://github.com/NVIDIA-ISAAC-ROS/isaac_ros_nvblox.git "$ISAAC_WS/src/isaac_ros_nvblox"
        run rm -f "$ISAAC_WS/src/isaac_ros_nvblox/nvblox_examples/realsense_splitter/COLCON_IGNORE"
        run docker run --rm --privileged --runtime nvidia -v "$ISAAC_WS:/workspaces/isaac_ros-dev" --workdir /workspaces/isaac_ros-dev --entrypoint bash "$IMAGE" -c 'source /opt/ros/jazzy/setup.bash && colcon build --symlink-install --packages-select realsense_splitter --cmake-args -DCMAKE_BUILD_TYPE=Release'
    fi
    # --runtime nvidia, not --gpus all: with the toolkit in its Jetson ("csv")
    # mode, --gpus invokes the runtime hook directly and the container refuses
    # to start ("invoking the NVIDIA Container Runtime Hook directly ... is
    # not supported"). It bit on 2026-09-24; a container created with --gpus
    # keeps runc as its runtime and must be recreated.
    if docker ps -a --format '{{.Names}}' | grep -qx "$CONTAINER"; then
        if [ "$(docker inspect "$CONTAINER" --format '{{.HostConfig.Runtime}}')" != "nvidia" ]; then
            say "container $CONTAINER was created without --runtime nvidia; recreating it from $IMAGE"
            run docker rm -f "$CONTAINER" >/dev/null
        else
            say "container $CONTAINER exists"
        fi
    fi
    if docker ps -a --format '{{.Names}}' | grep -qx "$CONTAINER"; then
        :
    else
        say "creating $CONTAINER from $IMAGE (systemd's isaac-vo.service starts it; --restart no on purpose)"
        run docker run -d --restart no --privileged --network host --ipc host --runtime nvidia \
            -e ROS_DOMAIN_ID="${ROS_DOMAIN_ID:-7}" -e ISAAC_ROS_WS=/workspaces/isaac_ros-dev \
            -e NVIDIA_VISIBLE_DEVICES=all -e NVIDIA_DRIVER_CAPABILITIES=all \
            -e HOST_USER_UID="$(id -u)" -e HOST_USER_GID="$(id -g)" -e USER="$USER" -e TERM=xterm \
            -v "$ISAAC_WS:/workspaces/isaac_ros-dev" -v /dev/bus/usb:/dev/bus/usb -v /dev/input:/dev/input \
            --workdir /workspaces/isaac_ros-dev --entrypoint /usr/local/bin/scripts/workspace-entrypoint.sh \
            --name "$CONTAINER" "$IMAGE" sleep infinity
    fi
    # The video feed's packages were added after the image was first committed
    # (2026-09-23): a container from an older image gets them here, and the
    # image is re-committed so a recreated container keeps them. They live in
    # the container because on the Jetson host apt would replace JetPack's
    # OpenCV and remove nvidia-jetpack to install them.
    if docker exec "$CONTAINER" dpkg-query -W $VIDEO_PKGS >/dev/null 2>&1; then
        say "video feed packages already in $CONTAINER"
    else
        say "adding the video feed packages to $CONTAINER and re-committing $IMAGE"
        docker ps --format '{{.Names}}' | grep -qx "$CONTAINER" || run docker start "$CONTAINER"
        run docker exec -u root "$CONTAINER" bash -c "apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq $VIDEO_PKGS"
        run docker commit --pause=false "$CONTAINER" "$IMAGE"
    fi
fi

# ---- 5. systemd: container at boot, robot at boot ----------------------------
if [ "$DO_UNITS" -eq 1 ]; then
    UNITS="$JETNANO_ROBOT_DIR/jetnano_bringup/systemd"
    [ -d "$UNITS" ] || { echo "$UNITS not found; clone jetnano_robot into ~/ros2_ws/src first" >&2; exit 1; }
    say "installing jetson-clocks, isaac-vo, jetnano-robot, jetnano-slam and wifi-watchdog services"
    run sudo cp "$UNITS"/jetson-clocks.service "$UNITS"/isaac-vo.service "$UNITS"/jetnano-robot.service "$UNITS"/jetnano-slam.service "$UNITS"/wifi-watchdog.service /etc/systemd/system/
    run sudo systemctl daemon-reload
    run sudo systemctl enable jetson-clocks.service isaac-vo.service jetnano-robot.service jetnano-slam.service wifi-watchdog.service
fi

say "done. Check: isaac-ros status; docker ps; systemctl status isaac-vo jetnano-robot"

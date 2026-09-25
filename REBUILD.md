# Rebuilding Rosie from scratch

Rosie is a 1/10-scale four-wheel-steering crawler with an NVIDIA Jetson Orin
Nano Super on board. She drives from a web page, maps the house, keeps a
watchdog on her own sensors, and talks: she hears through a USB microphone,
answers through a USB speaker, thinks with a language model on a PC upstairs
and hands the hard questions to Claude. This page puts her back together in
order. Each step points at the document with the detail.

## The repositories

| Repository | What it holds |
|---|---|
| [robot-environment](https://github.com/stevej52/robot-environment) | this guide, the install scripts, the upstairs PC's brain, backups |
| [jetnano_robot](https://github.com/stevej52/jetnano_robot) | the robot itself: launch files, drivers, voice, brain, watchdog, web page, maps, URDF |
| [ros2_gpu_robot](https://github.com/stevej52/ros2_gpu_robot) | GPU visual odometry (cuVSLAM) and 3D mapping (nvblox) in the Isaac ROS container |
| [ros2_pca9685](https://github.com/stevej52/ros2_pca9685) | the PCA9685 PWM driver for the ESC and the steering servos |

## The machines

| Machine | Role | Address |
|---|---|---|
| Jetson Orin Nano Super, `jetson`, user `jeston` | the robot | 192.168.1.7 (fixed) |
| Ubuntu 24.04 PC, `H2-Host`, user `steve` | RViz, the simulator, a keyboard for the robot | 192.168.1.238 |
| Windows PC upstairs, `JEDIPC` (AMD RX 9060 XT 16 GB) | her local language model | 192.168.1.137 |
| Windows laptop | development, the D: backup drive | 192.168.1.49 |

Everything runs ROS 2 Jazzy on Ubuntu 24.04 from binary packages, with
`ROS_DOMAIN_ID=7`. The simulator uses domain 77 so it never talks to the
real robot.

## The parts

- **Chassis**: DANCHEE RidgeRock 1/10 4WD crawler with four-wheel steering,
  Hobbywing 1040 crawler ESC, Castle Creations BEC for the servos, 3S LiPo
  (Deans plug), a 12 V rail straight to the Orin's barrel jack.
- **PWM**: Adafruit PCA9685 at I²C address 0x40 on the Orin's bus 7:
  channel 0 ESC, 1 front steering, 2 rear steering.
- **Sensors**: Intel RealSense D435 (USB 3), RPLidar A1M8 (USB, CP2102
  adapter, mounted facing backwards), Bosch BNO055 IMU on I²C.
- **Audio**: a USB speaker (ALSA card `UACDemoV10`) and a small USB
  microphone (card `Device`) on a short extension, on foam, away from the
  lidar motor.
- **Network**: a TP-Link access point downstairs; the robot is locked to its
  5 GHz radio.
- **Planned, with software ready**: INA219 battery monitor (address 0x41,
  voltage only), four VL53L0X cliff sensors behind a TCA9548A mux (0x70), a
  pan-tilt IMX477 camera, two relays for lights, a CR2032 for the RTC.

Wiring, measured positions and what is still a guess: jetnano_robot
`README.md` (the I²C section) and `docs/bench-calibration-2026-09-21.md`.

## 1. The Jetson

1. Flash **JetPack 7.2.1** (Ubuntu 24.04), user `jeston`, hostname `jetson`:
   [docs/environment.md](docs/environment.md) section 5. Read the note on
   the capsule firmware update in that section first: a 30-second prompt
   during the first boot decides whether the setup screen appears at all.
2. Power mode **MAXN_SUPER**. Fixed address 192.168.1.7 and the Wi-Fi locked
   to the access point's 5 GHz BSSID: section 8.
3. **Password-free sudo** for the robot's user, if you want it. The robot
   was built with it (`/etc/sudoers.d/90-nopasswd-sudo`:
   `%sudo ALL=(ALL:ALL) NOPASSWD:ALL`) because two of her features call
   sudo on their own: the watchdog resets the lidar's USB port, and "Rosie,
   start mapping" starts a service. A narrower rule allowing only
   `systemctl start|stop jetnano-slam` and writes to
   `/sys/bus/usb/devices/*/authorized` is the safer choice.

## 2. ROS 2 and the workspace (the Jetson and the host PC)

```
git clone https://github.com/stevej52/robot-environment.git ~/robot-environment
bash ~/robot-environment/scripts/install_ros2_jazzy.sh --domain-id 7 --workspace
cd ~/ros2_ws/src
git clone https://github.com/stevej52/jetnano_robot.git
git clone https://github.com/stevej52/ros2_pca9685.git
git clone https://github.com/stevej52/ros2_gpu_robot.git
cd ~/ros2_ws && rosdep install --from-paths src --ignore-src -y && colcon build
```

The install script also stops logind from deleting the shared memory ROS 2
uses when you log out (RemoveIPC=no). Then the device rule, the groups and
the rest of the robot's own setup: jetnano_robot `README.md`, "Installing".
`scripts/check_environment.sh` on both machines should print the same
fingerprint.

## 3. GPU odometry and the robot's services (Jetson)

```
bash ~/robot-environment/scripts/install_isaac_ros_46.sh --all
bash ~/robot-environment/scripts/install_system_settings.sh
```

The first builds the Isaac ROS 4.6 container image `isaac_vo:4.6` (a few
hours, from NVIDIA's servers), creates the container with the NVIDIA runtime
and installs the services: `jetson-clocks`, `isaac-vo`, `jetnano-robot`,
`jetnano-slam` and `wifi-watchdog`. Mapping is installed but **not** started
at boot: she maps when told to (below). The second makes NVIDIA Docker's
default runtime and lets the case button shut her down. Detail and numbers:
docs/environment.md section 9, ros2_gpu_robot `cuvslam_d435/README.md`.

The robot's own settings go in `/etc/default/jetnano-robot` (root-only):

```
ROBOT_ARGS="nvblox:=true location:=Ventura,California"
```

Add `use_cliff:=true` once the cliff sensors are fitted. The Claude key goes
in the same file (step 6).

## 4. Her voice (Jetson)

```
bash ~/robot-environment/scripts/install_voice.sh
source ~/ros2_ws/install/setup.bash && ros2 run jetnano_bringup make_voice ~/sounds
```

The first makes `~/venv-voice` (sherpa-onnx for hearing and speech, the
Anthropic SDK for her brain) and downloads the models to `~/voice/models`:
a voice-activity detector, the Moonshine speech-to-text model and the Piper
voice. The second writes her robot sounds to `~/sounds`. The cliff sensors
use a second venv, `~/venv-sensors`: jetnano_robot `README.md`, I²C section.

## 5. Her local brain (the PC upstairs)

[scripts/jedipc_brain.md](scripts/jedipc_brain.md): llama.cpp's Vulkan
server on the Radeon with Qwen 2.5 14B, started at logon, reachable on port
8090. Any PC with a 12 GB or bigger graphics card will do; change
`local_url` in jetnano_bringup `brain.py` if it lives elsewhere.

## 6. The Claude key

Make a key at console.anthropic.com (a workspace key, not an organisation
one; set a monthly limit there too). On any Linux machine that can reach
the robot:

```
bash ~/robot-environment/scripts/add-rosie-key.sh
```

It asks for the key at a hidden prompt and writes it into
`/etc/default/jetnano-robot` on the robot, then restarts her. The key is
never shown, never logged and never in a repository or a backup.

## 7. Calibration to redo on new hardware

- **IMU**: BNO055 offsets, `jetnano_bringup/config/bno055.yaml`.
- **Camera pitch and roll**: plane fit, ros2_gpu_robot `tools/camera_pitch.py`,
  into the URDF's `camera_rpy`.
- **Lidar**: mounted backwards, `lidar_rpy 0 0 pi` in the URDF.
- **ESC and steering**: neutral 1375 us, `ros2_pca9685` config `rc_car.yaml`.
- **Microphone**: her clap threshold and listening gain are parameters of
  the `ears` and `listen` nodes; measure the room with
  `ros2 topic echo /sound/level`.

The numbers used on the first build: jetnano_robot
`docs/bench-calibration-2026-09-21.md`.

## 8. Checking she is whole

```
sudo systemctl start jetnano-robot
ros2 topic echo --once /watchdog/status
```

The watchdog's status should say `"ok": true` with no problems about 90
seconds after start. Then:

- the driving page: http://192.168.1.7:8081/
- "Rosie, how are you?" - a line or two about how she really is, then
  "Want a full status report?"
- put her at the parking spot and say "Rosie, start mapping"; before picking
  her up, "Rosie, stop mapping" (she saves the map). The map's origin is the
  parking spot, so always start mapping there.

Everything she understands: jetnano_robot `docs/talking-to-rosie.md`.

## 9. Backups

GitHub holds all the code and configuration. What exists only on the robot
- the house map, drive recordings, her sounds and voice models, the
watchdog's history, the system settings - is gathered by

```
bash ~/robot-environment/scripts/backup_robot_state.sh /tmp/rosie-robot-state.tar.zst
```

with the Claude key and the Wi-Fi password left out, plus an inventory of
every installed package, venv and container image.

The first full backup is on the laptop's D: drive,
`D:\Rosie-backup-2026-09-25\`:

| Folder | What | To restore |
|---|---|---|
| `git` | full mirrors of the four repositories, every branch and commit | `git clone D:\Rosie-backup-2026-09-25\git\jetnano_robot.git` |
| `robot` | the robot-state archive above, and its checksum | `zstd -dc <archive> \| tar -xf -`, then copy `home/*` back to `/home/jeston/` and `etc/*` to their places |
| `h2-host` | the host PC's browser tests and key-install files | unpack into `~` |
| `old-robot-code` | the old Jetson Nano robot's recovered source | reference only |
| `claude-memory` | the build notes kept while Rosie was made | reference |

Not in any backup, on purpose: the Claude key and the Wi-Fi password (make
new ones), and the 24 GB Isaac ROS container image (rebuild it with step 3;
`docker save` exports it at about 1 MB/s).

## When something is wrong

- **She does not answer.** Is she muted? `ros2 param get /sounds mute`, or
  say "Rosie, you can talk now". Only "Rosie, be quiet" with her name mutes
  her.
- **A sensor dropped out.** The watchdog restarts it; the driving page shows
  what it is working on, and `~/watchdog/events.jsonl` keeps the history.
- **Nothing on the network sees the robot's topics.** docs/environment.md
  section 7.

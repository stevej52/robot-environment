# robot-environment

One environment for the whole robot: **Ubuntu 24.04 + ROS 2 Jazzy**, installed
from binary packages, identical on every machine — the host PC, the spare PC,
and the NVIDIA Jetson Orin Nano Super.

This repository holds the *machine setup*. The robot's actual driver code lives
in [`ros2_pca9685`](https://github.com/stevej52/ros2_pca9685), which the install
script clones into your workspace for you.

## Contents

| Path | What it does |
|---|---|
| [`docs/environment.md`](docs/environment.md) | The guide: which versions, why, USB sticks, installing each machine, flashing the Jetson, wiring the PCA9685, troubleshooting |
| [`scripts/install_ros2_jazzy.sh`](scripts/install_ros2_jazzy.sh) | Installs ROS 2 Jazzy on Ubuntu 24.04, sets `ROS_DOMAIN_ID`, sets up the `i2c` group, optionally builds `~/ros2_ws` |
| [`scripts/check_environment.sh`](scripts/check_environment.sh) | Prints a one-line fingerprint of a machine, to compare two of them |

## Quick start

On every machine — PC, spare PC and Jetson alike:

```bash
sudo apt install -y git
git clone https://github.com/stevej52/robot-environment.git ~/robot-environment
~/robot-environment/scripts/install_ros2_jazzy.sh --domain-id 7 --workspace
```

Use the **same `--domain-id` everywhere**; it is what separates this robot from
other ROS 2 traffic on the network. Add `--base` for a machine that will never
have a screen, and `--dry-run` to see what it would do without changing
anything. Re-running it is safe.

Then compare the machines:

```bash
~/robot-environment/scripts/check_environment.sh
```

Read [`docs/environment.md`](docs/environment.md) before flashing a Jetson.
Section 5.2 step 2 in particular — the firmware update prompt there defaults to
*skipping*, and skipping it leaves a kit you cannot log into.

## Why this is its own repository

These files were originally committed onto a branch of the `ros2_pca9685`
driver repository. They do not belong there: installing an operating system and
a ROS distribution across three machines is not part of a PCA9685 driver, and
keeping them together meant the driver repo contained a script whose job was to
clone the driver repo. Splitting them also lets the setup and the driver be
versioned independently.

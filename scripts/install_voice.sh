#!/usr/bin/env bash
# Rosie's speech: sherpa-onnx (voice activity detection + speech-to-text, all
# on the robot's CPU) in its own venv, models in ~/voice/models.
#
#   bash install_voice.sh            # ~200 MB of downloads, a few minutes
#
# Used by jetnano_bringup `listen` (robot.launch.py use_listen:=true, the
# default, which only starts it when this venv exists).
set -euo pipefail

VENV="${VENV:-$HOME/venv-voice}"
MODELS="${MODELS:-$HOME/voice/models}"
REL=https://github.com/k2-fsa/sherpa-onnx/releases/download/asr-models

[ -x "$VENV/bin/python3" ] || python3 -m venv --system-site-packages "$VENV"
"$VENV/bin/pip" install -q --upgrade sherpa-onnx

mkdir -p "$MODELS"
cd "$MODELS"
[ -f silero_vad.onnx ] || curl -sSLO "$REL/silero_vad.onnx"
for m in sherpa-onnx-moonshine-tiny-en-int8 sherpa-onnx-whisper-tiny.en; do
    [ -d "$m" ] || curl -sSL "$REL/$m.tar.bz2" | tar xj
done

"$VENV/bin/python3" -c "import sherpa_onnx; print('sherpa-onnx', sherpa_onnx.__version__)"
du -sh "$MODELS"/*

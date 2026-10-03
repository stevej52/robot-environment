#!/usr/bin/env bash
# Puts Rosie's Anthropic API key on the robot and restarts her.
#
#   bash ~/Desktop/add-rosie-key.sh
#
# The key is read at a hidden prompt, sent over SSH to the robot, written to
# /etc/default/jetnano-robot (root-only, chmod 600), and never shown or saved
# anywhere else. Running it again replaces the old key.
set -euo pipefail
ROBOT=jeston@192.168.1.7

echo "Paste Rosie's API key (it will not show on screen), then press Enter:"
read -rs KEY
echo
KEY=$(printf '%s' "$KEY" | tr -d '[:space:]')
case "$KEY" in
    sk-ant-*) ;;
    *) echo "That does not look like an Anthropic key (it should start with sk-ant-). Nothing was changed."; exit 1 ;;
esac

echo "Connecting to Rosie. If it asks for a password, it is the jeston password."
printf 'ANTHROPIC_API_KEY=%s\n' "$KEY" | ssh -o StrictHostKeyChecking=accept-new "$ROBOT" '
    set -e
    f=/etc/default/jetnano-robot
    sudo sh -c "umask 077; grep -v \"^ANTHROPIC_API_KEY=\" $f > $f.new || true; cat >> $f.new; chmod 600 $f.new; mv $f.new $f"
    echo "Saved. Her settings file now reads:"
    sudo sed "s/=sk-ant-.*/=sk-ant-(hidden)/" $f
    echo "Restarting Rosie, about a minute..."
    sudo systemctl restart jetnano-robot
    echo "Done. Tell Claude it is in."
'
unset KEY

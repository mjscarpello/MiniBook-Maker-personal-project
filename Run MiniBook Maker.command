#!/bin/zsh
APP="$HOME/Applications/MiniBook Maker 2.app"
if [[ -d "$APP" ]]; then
  open "$APP"
else
  echo "MiniBook Maker 2 is not installed yet. Run Build MiniBook Maker.command first."
  read
fi

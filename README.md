# DingSound (WoW Midnight)

DingSound plays a custom audio file whenever your character levels up.

## Features

- Listens for `PLAYER_LEVEL_UP`.
- Plays the currently selected file (if enabled).
- Uses a short playback buffer to avoid overlapping sounds when multiple level-ups happen quickly.
- Adds an options panel in **Game Menu → Options → AddOns → DingSound**:
  - Enable/disable toggle.
  - Sound picker dropdown.

## Adding your own sounds

1. Put your files in:
   "\\Interface/AddOns/DingSound/Sounds/"
2. Open "\DingSound.lua"
3. Add each file name to the "SOUND_FILES" table. Example:

local SOUND_FILES = {
    "levelup.mp3",
    "fanfare.ogg",
}


If the table is empty, the addon defaults to doing nothing on level-up.

## Why not auto-scan the folder?

WoW addons cannot enumerate arbitrary files from disk at runtime, so the game cannot automatically discover files in the folder. The supported pattern is to maintain an explicit file list in addon code.

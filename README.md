## DingSound
DingSound plays custom audio files whenever your character levels up or earns an achievement.

### Features
- Listens for `PLAYER_LEVEL_UP` and `ACHIEVEMENT_EARNED`.
- Plays the currently selected file (if enabled) for each feature independently.
- Uses a short playback buffer to avoid overlapping sounds when events happen quickly.
- When a feature is enabled, WoW's default sound for that feature is automatically muted.
- Adds options panels in **Game Menu → Options → AddOns → DingSound**:
  - **DingSound** panel with addon overview and usage notes.
  - **Main Options** subpanel for enabling/disabling level-up and achievement features.
  - **Custom Sounds** subpanel for sound pickers, preview buttons, and duckout sliders.
  - Footer with addon version and author tag on every panel.

### Adding your own sounds
1. Put your files in:
   `Interface/AddOns/DingSound/Sounds/`
2. Open `DingSound_SoundList.lua`
3. Add each file name to the `DingSoundSoundList` table. Example:

```lua
DingSoundSoundList = {
    "levelup.mp3",
    "fanfare.ogg",
}
```

If the table is empty, the addon defaults to doing nothing on level-up.

### Can this use a plain TXT file?
Not directly. WoW addons run in a restricted Lua environment and cannot read arbitrary text files from disk at runtime.

Using a small dedicated Lua list file (`DingSound_SoundList.lua`) is the closest safe alternative: users only edit file names in one simple place and do not need to touch addon logic.

### Why not auto-scan the folder?
WoW addons cannot enumerate arbitrary files from disk at runtime, so the game cannot automatically discover files in the folder. The supported pattern is to maintain an explicit file list in addon data.

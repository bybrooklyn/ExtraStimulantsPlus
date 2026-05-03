# ExtraStimulantsPlus

`VERSION`: `v0.0.1`

ExtraStimulantsPlus is a drop-in mod layer for Sensory Overload focused on three things:

- better performance, especially on weaker PCs and Android devices
- a native in-game custom map workflow
- simple mod installation that is easy to undo

## License

**Read `LICENSE` before redistributing this mod.**

**The mod code in this package is shipped with the included GPLv3 license text.**

**This package does not grant any right to redistribute the original game's copyrighted assets.**

Share only the loose mod files in this package, not the base game.

## Installation

### PC

Copy these loose files and folders next to the game's executable:

- `override.cfg`
- `VERSION`
- `LICENSE`
- `scripts/`
- `scenes/`
- `addons/`

That is enough for Godot to pick up the mod.

### Uninstall / Revert

Delete the same loose files and folders listed above.

The original packed game data is left untouched, so uninstalling the mod is just removing the loose override files.

### Android

Use the included install scripts from the workspace root if you want to patch an APK:

- `install.sh`
- `install.bat`

Those scripts inject the same loose override files into the exported Android asset layout.

## Features

- built-in mod loader that mounts `.pck` packs from `user://mods/`
- top-right version badge on the main menu
- custom maps menu entry on the main menu
- in-game level editor with dropdown selection for Themes and Songs
- professional editor tools: Multi-select, Group Dragging, Undo/Redo (Ctrl+Z/Y)
- rhythmic workflow: BPM beat markers and Ring Snapping
- level prefabs: Copy/Paste groups of obstacles (Ctrl+C/V)
- in-game custom map browser with a Details Panel (Theme/Song/Obstacle count)
- support for external music files (.ogg, .mp3, .wav) in `user://custom_music/`
- "Play Test" button and Auto-Backup in the Level Editor
- ultrawide display support (21:9, 32:9) with corrected FOV and responsive UI
- shareable `.somap` map format with import/export support
- built-in mod loader with `mod.json` metadata and strict dependency checking

## Custom Map Format

ExtraStimulantsPlus uses `.somap` as the default share format.

- create or edit maps in the level editor
- export them as `user://custom_levels/<name>.somap`
- share the `.somap` file directly
- other players can drop the file into their own `user://custom_levels/` folder and play it from the `CUSTOM MAPS` menu

Legacy `.json` scripted sequences can still be imported into the editor.

## Mod Settings

The mod adds its own settings popup inside the normal settings screen for:

- showing or hiding the version badge
- showing or hiding the loaded-mod count
- preferring `.somap` when exporting maps
- forcing the level editor menu entry to stay visible

## Notes

- PC installation is meant to be drag-and-drop and reversible.
- Android installation is still more involved because APKs must be rebuilt and resigned.
- This package intentionally excludes the original game's assets.

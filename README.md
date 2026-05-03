# ExtraStimulantsPlus v0.0.1

A mod for Sensory Overload that also acts as a mod loader for the community.

---

## Planned Enhancements (Roadmap)

### Rhythmic Tunnel Reactivity
Connecting the AudioVisualizer to core shaders and deformation loops. The environment will breathe and pulse to the beat of your custom music automatically.

### In-Game Mod Manager
A dedicated UI tab to manage installed mods, view metadata, toggle mods on/off, and resolve dependencies without restarting the game.

### Ghost Replay System
Record your best runs and play against a translucent ghost of yourself. Perfect for mastering high-speed custom maps.

### Gameplay Mutators
A suite of modifiers to change the game's feel:
- Mirror Mode: Flips the tunnel and movement.
- Chaos Mode: Randomizes obstacle rotations on the fly.
- Turbo: Static speed multiplier for the ultimate challenge.

### Developer Console
A ~ console for advanced users to tweak shader parameters, reload mods, and debug level scripts in real-time.

---

## QUICK START: How to install (PC)

This mod uses a permanent bootstrap method to enable mod loading and optimizations without requiring custom launchers or command-line arguments.

1.  Find your game folder (where SensoryOverload.exe is).
2.  Run the installer from this folder:
    - **Linux/macOS:** `./install.sh /path/to/game/folder`
    - **Windows:** `install.bat "C:\Path\To\Game\Folder"`
3.  Launch the game normally (via Steam or the .exe).

**How it works:**
The installer injects a tiny bootstrap loader into your game's main .pck file. This loader automatically mounts any mods found in the new /mods folder and enables all "Turbo" optimizations. A backup of your original .pck is created as .pck.bak.

---

## Features

### Level Editor
- **Modern UX:** Multi-select (Shift+Click), Group Dragging, and full Undo/Redo (Ctrl+Z/Y).
- **Tooling:** Copy/Paste prefabs (Ctrl+C/V), Delete, and Nudge items.
- **Rhythmic Sync:** Set BPM to see visual beat markers on the timeline.
- **Precision:** Ring Snapping (snap to 5, 10, or 20 rings).
- **Testing:** One-click "Play Test" button and Auto-Backup safety.

### Custom Maps & Sharing
- **Custom Map Browser:** Explore your maps with a details panel (Themes, Songs, Stats).
- **External Music:** Drop .mp3, .ogg, or .wav into user://custom_music/.
- **Easy Sharing:** Uses the .somap format for single-file map sharing.

### Performance & Display
- **Ultrawide Support:** Automatic FOV correction for 21:9 and 32:9 monitors.
- **Responsive UI:** Menus that scale and anchor correctly on any screen size.
- **Optimization:** Rewritten deformation loops for lower CPU usage and zero memory churn.

### Mod Management
- **Metadata Support:** Mods now show Author, Version, and Description via mod.json.
- **Dependency Check:** Ensures required mods are loaded to prevent crashes.

---

## License & Legal

- **Software:** The mod code is licensed under **GPLv3** (see LICENSE).
- **Assets:** This package contains **NO** original game assets. You must own Sensory Overload to use this mod.
- **Redistribution:** You may share this mod freely, but do **not** include the base game's .pck or .exe files.

---

## Android Installation

Use the included install.sh (Linux/Mac) or install.bat (Windows) in the root directory. You will need apktool and apksigner installed.

---

> **Note on Deprecation:** The level editor features of this mod are intended to fill the gap until the official Sensory Overload level editor is released. Once the official editor is available, these specific features may be deprecated or refactored to ensure compatibility and focus on other modding enhancements.

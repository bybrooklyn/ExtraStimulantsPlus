# ExtraStimulantsPlus v0.0.2

The definitive modding ecosystem for *Sensory Overload*.

## 1. Zero-Configuration Install (Recommended)

1. **Download**: Get the latest `esp.exe` (Windows) or `espbin` (Linux) from [GitHub Releases](https://github.com/bybrooklyn/extrastimulants_plus/releases).
2. **Run**: Double-click the executable to open the **ESP Orchestrator GUI**.
3. **Setup**: Click the **"ONE-CLICK SETUP"** button.
   - *The tool will auto-detect your Steam install, patch the game, and download the latest framework automatically.*
4. **Play**: Click **"LAUNCH GAME"**.

---

## 2. Architecture
- **GUI Orchestrator**: A standalone Rust app that manages the environment and provides a live log console.
- **Strict Loader**: Enforces a 4-phase mod lifecycle; any failure crashes the game safely to prevent corruption.
- **Native Settings**: Mod settings appear seamlessly in the game's official menus.
- **Custom Levels**: Support for shared `.somap` level packs.

---

## 3. Automation (CI/CD)
The project is fully automated via **GitHub Actions**. Every tag push (`v0.0.2`, etc.) automatically:
- Compiles the Rust tool for Windows and Linux.
- Packs the framework core.
- Publishes a new Release with all binaries attached.

---

## 3. Modder Guide: Settings API
The framework provides a global `ESP` singleton to easily add configuration to the game's native settings menu.

```gdscript
func esp_init(api: Node, meta: Dictionary) -> bool:
    # Register a toggle setting
    api.register_setting("my_mod", "enable_turbo", TYPE_BOOL, true)
    return true

func esp_ready(api: Node, meta: Dictionary) -> void:
    var is_turbo = api.get_setting("my_mod", "enable_turbo")
    if is_turbo:
        print("Turbo is active!")
```

---

## 4. Advanced Roadmap

### I. True Native UI Polish
Upgrade the Settings UI generator to use the game's official `.tres` styleboxes and sound effects, making mod menus indistinguishable from native game tabs.

### II. .somap Deep Loader
Implement a comprehensive audio bridge for custom `.somap` levels, dynamically unzipping and loading `.ogg`/`.wav` music and parsing JSON metadata into native engine resources.

### III. The ESP Update Hub
Activate full GitHub API integration in the Rust CLI to support `esp update` (framework refresh) and `esp add <url>` (instant community mod installation).

### IV. Surgical Regex Patching
R&D into a runtime "Surgical Patcher" that modifies game scripts in memory via Regex. This allows multiple mods to modify the same file without conflicts or `take_over_path()` overwrites.

---

## 5. License & Legal
- Code: MIT.
- This repo contains no original game assets.
- Do not redistribute the base game's `.pck`, `.exe`, or app bundle.

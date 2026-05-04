# ESP Installer Rust

Native replacement for the old `pck_patcher.py` path.

```bash
cargo build --release
./target/release/esp-installer install /path/to/Game.pck --repo /path/to/ExtraStimulantsPlus
./target/release/esp-installer status /path/to/Game.pck
./target/release/esp-installer uninstall /path/to/Game.pck
```

What it injects:

- `res://esp_shim/ESPShim.gd`
- `res://esp_bootstrap/ESPBootstrap.gd` compatibility path
- merged `res://override.cfg` with only the `ESPShim` autoload added

It does **not** inject the full mod. The actual core goes beside the game as:

```text
mods/ExtraStimulantsPlus.zip
```

or:

```text
mods/ExtraStimulantsPlus.pck
```

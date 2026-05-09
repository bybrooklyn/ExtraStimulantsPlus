# esp-tool

The native ESP orchestrator. CLI + GUI built in Rust.

```bash
cargo build --release

# Interactive GUI — auto-detect, install, update, mod manager, launch
./target/release/esp

# CLI subcommands
./target/release/esp install [/path/to/Game.pck]              # patch shim into PCK; auto-detects via Steam if omitted
./target/release/esp uninstall [/path/to/Game.pck] [--purge]  # restore PCK; --purge also removes mods/levels/modloader
./target/release/esp launch [--no-mods]                       # write load plan + start game
./target/release/esp pack <output.zip>                        # zip current dir into a core pack
./target/release/esp create [<id>] [--template <name>] [--here] [--no-prompt] [--repository <url>]
```

What `install` injects into the PCK:

- `res://esp_shim/ESPShim.gd`
- `res://esp_bootstrap/ESPBootstrap.gd`
- merged `res://override.cfg` with only the `ESPShim` autoload added

It does **not** inject the full mod. The actual core goes beside the game as:

```text
mods/ExtraStimulantsPlus.zip
```

The orchestrator pulls that zip dynamically from the latest GitHub Release —
asset name `ExtraStimulantsPlus.zip` plus a sibling `.sha256` for verification.
The `UPDATE FRAMEWORK` GUI button and `esp install` both use this path; no
`FRAMEWORK_URL` constant is hardcoded.

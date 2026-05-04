# Build and Install

## Build the external core ZIP

From the repo root:

```bash
python3 pck_patcher.py dummy.pck --pack-mod . --mod-output ExtraStimulantsPlus.zip
```

The Python path is now legacy. It still exists because it is useful for quick packing while the native installer matures.

The produced core ZIP should be placed here:

```text
<Game folder>/mods/ExtraStimulantsPlus.zip
```

Godot can load either `.zip` or `.pck` resource packs through the shim.

## Install the shim with Rust installer

```bash
cd tools/esp-installer-rs
cargo build --release
./target/release/esp-installer install /path/to/Game.pck --repo /path/to/ExtraStimulantsPlus
```

## Check install status

```bash
./target/release/esp-installer status /path/to/Game.pck
```

## Uninstall

```bash
./target/release/esp-installer uninstall /path/to/Game.pck
```

The installer restores:

```text
Game.pck.esp-backup
```

## Legacy Python install

```bash
python3 pck_patcher.py /path/to/Game.pck
```

This now injects the same tiny shim files instead of trying to shove the whole mod into the game.

# Build and Install

## Build the external core ZIP

From the repo root, after building the orchestrator at least once:

```bash
./tools/esp-tool/target/release/esp pack ExtraStimulantsPlus.zip
```

The produced core ZIP should be placed here:

```text
<Game folder>/mods/ExtraStimulantsPlus.zip
```

Godot can load either `.zip` or `.pck` resource packs through the shim.

For tagged releases the GitHub Actions workflow (`.github/workflows/build.yml`)
publishes `ExtraStimulantsPlus.zip` and a sibling `.sha256` to the release
itself; `esp install` and `esp` (GUI: `UPDATE FRAMEWORK` button) pull those
automatically via the GitHub releases API.

## Build the orchestrator

```bash
cd tools/esp-tool
cargo build --release
```

This produces `tools/esp-tool/target/release/esp` (or `esp.exe` on Windows).

## Install the shim

```bash
./target/release/esp install /path/to/Game.pck
```

The path is optional — `esp install` auto-detects the Sensory Overload PCK via
Steam if you omit it. The first install also creates `modloader/`, `mods/`,
`levels/`, and `campaigns/` directories alongside the PCK and writes
`Game.pck.esp-backup` so the original can be restored.

## Launch the game with mods

```bash
./target/release/esp launch
```

Use `--no-mods` to launch without the load plan.

## Uninstall

```bash
./target/release/esp uninstall /path/to/Game.pck
```

By default this restores the PCK from `Game.pck.esp-backup` but **keeps** your
installed mods, custom levels, and saved settings. Pass `--purge` to also
remove `modloader/`, `mods/`, `levels/`, and `campaigns/`:

```bash
./target/release/esp uninstall /path/to/Game.pck --purge
```

The GUI's UNINSTALL button surfaces the same flag as a checkbox in the
confirmation dialog.

## GUI mode

Run `esp` with no arguments to open the orchestrator GUI:

```bash
./target/release/esp
```

The GUI handles auto-detect, install, framework update, mod toggling, and
launch. CLI subcommands above are useful for scripting; the GUI is the
recommended path for interactive use.

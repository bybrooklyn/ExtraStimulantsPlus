set shell := ["bash", "-lc"]

# Default task list for development and build workflows.
default:
    @just --list

# Show all available recipes.
list:
    @just --list

# Run the Godot project in the editor or game from the repo root.
dev:
    @godot --path .

# Run the Godot project in a headless mode useful for quick smoke checks.
# Override the executable if needed: `just run --godot=/path/to/godot`
run godot="godot":
    @{{godot}} --path .

# Build the Rust orchestrator/installer GUI.
build-tool:
    @cargo build --release --manifest-path tools/esp-tool/Cargo.toml

# Run the Rust orchestrator/installer GUI from the repo root.
# Override the executable path if needed: `just tool --bin=./tools/esp-tool/target/release/esp`
tool bin="./tools/esp-tool/target/release/esp":
    @{{bin}}

# Pack the framework core into a zip artifact from the repo root.
pack output="ExtraStimulantsPlus.zip":
    @cargo run --release --manifest-path tools/esp-tool/Cargo.toml -- pack {{output}}

# Build both the Rust tool and the core pack artifact.
build: build-tool pack

# Cross-compile the Rust tool for Windows and Linux from macOS using cargo-zigbuild.
# Outputs land under tools/esp-tool/target/<target>/release/.
cross: cross-windows cross-linux

# Cross-compile the Rust tool for 64-bit Windows.
cross-windows:
    @cargo zigbuild --release --target x86_64-pc-windows-gnu --manifest-path tools/esp-tool/Cargo.toml

# Cross-compile the Rust tool for 64-bit Linux.
cross-linux:
    @cargo zigbuild --release --target x86_64-unknown-linux-gnu --manifest-path tools/esp-tool/Cargo.toml

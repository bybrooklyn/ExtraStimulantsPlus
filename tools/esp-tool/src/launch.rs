use std::io;
use std::path::PathBuf;
use std::process::Command;

use crate::config::Config;
use crate::error::io_err;
use crate::steam::SteamScanner;

pub fn launch_game(config: &Config, no_mods: bool) -> io::Result<()> {
    if cfg!(target_os = "macos") {
        return Err(io_err(
            "Sensory Overload has no native macOS build. \
             Install on a Windows machine or on Linux with Proton.",
        ));
    }

    let pck_path = config
        .pck_path
        .as_ref()
        .ok_or_else(|| io_err("Not installed"))?;
    let game_dir = pck_path
        .parent()
        .ok_or_else(|| io_err("PCK has no parent dir"))?;

    let candidates: Vec<PathBuf> = if cfg!(windows) {
        vec![game_dir.join("SensoryOverload.exe")]
    } else {
        // Native Linux build (if it ever exists), then fall back to Steam +
        // Proton via app-id discovery below.
        vec![
            game_dir.join("SensoryOverload.x86_64"),
            game_dir.join("SensoryOverload"),
        ]
    };

    if let Some(bin) = candidates.iter().find(|p| p.exists()) {
        let mut cmd = Command::new(bin);
        cmd.current_dir(game_dir);
        if no_mods {
            cmd.arg("--no-esp-mods");
        }
        cmd.spawn()?.wait()?;
        return Ok(());
    }

    // Linux fallback: no native binary present (the install is the Windows
    // pck running through Proton). Hand off to Steam so it picks the right
    // Proton version and sets up the prefix. We can't pass --no-esp-mods this
    // way; mod toggling has to happen via the load plan / mod manager before
    // launch.
    if cfg!(target_os = "linux") {
        if let Some(appid) = SteamScanner::new().find_game_appid() {
            return launch_via_steam(&appid);
        }
    }

    Err(io_err(&format!(
        "Game binary not found in {}. \
         If running through Proton, make sure Steam is open and Sensory Overload \
         is installed via that Steam library.",
        game_dir.display()
    )))
}

#[cfg(target_os = "linux")]
fn launch_via_steam(appid: &str) -> io::Result<()> {
    // Prefer `steam -applaunch <appid>` (works when steam is in PATH).
    if Command::new("steam")
        .args(["-applaunch", appid])
        .spawn()
        .is_ok()
    {
        return Ok(());
    }
    // Fall back to xdg-open with the steam:// handler — most desktops
    // register this when Steam is installed via the package manager.
    let uri = format!("steam://rungameid/{}", appid);
    Command::new("xdg-open").arg(&uri).spawn().map_err(|e| {
        io_err(&format!(
            "Could not invoke `steam` or `xdg-open` to start Steam app {}: {}",
            appid, e
        ))
    })?;
    Ok(())
}

#[cfg(not(target_os = "linux"))]
fn launch_via_steam(_appid: &str) -> io::Result<()> {
    Err(io_err("Steam launch fallback is Linux-only"))
}

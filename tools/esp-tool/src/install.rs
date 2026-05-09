use std::fs;
use std::io::{self, Read, Write};
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};

use sha2::{Digest, Sha256};

use crate::config::Config;
use crate::error::io_err;
use crate::github;
use crate::pck::{merge_override_cfg, GodotPck};
use crate::steam::SteamScanner;

const SHIM_GD: &[u8] = include_bytes!("../../../esp_shim/ESPShim.gd");
const BOOTSTRAP_GD: &[u8] = include_bytes!("../../../esp_bootstrap/ESPBootstrap.gd");
const OVERRIDE_CFG: &[u8] = include_bytes!("../../../esp_bootstrap/override.cfg");

const FRAMEWORK_ASSET_NAME: &str = "ExtraStimulantsPlus.zip";
const FRAMEWORK_SHA_ASSET_NAME: &str = "ExtraStimulantsPlus.zip.sha256";
/// Hard cap on the streaming download size. Real framework zips are a few MB;
/// 256 MB is two orders of magnitude over the worst plausible case. Without
/// this cap, a server that omits Content-Length could stream forever and fill
/// the disk before failing.
const MAX_FRAMEWORK_SIZE: u64 = 256 * 1024 * 1024;

pub fn install_shim(pck_path: &Path) -> io::Result<()> {
    let backup = PathBuf::from(format!("{}.esp-backup", pck_path.display()));
    if !backup.exists() {
        fs::copy(pck_path, &backup)?;
    }
    let mut pck = GodotPck::load(pck_path)?;
    pck.add_file("res://esp_shim/ESPShim.gd", SHIM_GD.to_vec(), 0);
    pck.add_file(
        "res://esp_bootstrap/ESPBootstrap.gd",
        BOOTSTRAP_GD.to_vec(),
        0,
    );
    let override_str = std::str::from_utf8(OVERRIDE_CFG)
        .map_err(|e| io_err(&format!("embedded override.cfg is not utf8: {}", e)))?;
    let merged = merge_override_cfg(
        pck.files
            .get("res://override.cfg")
            .map(|f| f.data.as_slice()),
        override_str,
    );
    pck.add_file("res://override.cfg", merged.into_bytes(), 0);
    pck.save(pck_path)?;
    if let Some(game_dir) = pck_path.parent() {
        fs::create_dir_all(game_dir.join("modloader"))?;
        fs::create_dir_all(game_dir.join("mods"))?;
        fs::create_dir_all(game_dir.join("levels"))?;
        fs::create_dir_all(game_dir.join("campaigns"))?;
    }
    Ok(())
}

pub fn is_esp_installed(pck_path: &Path) -> bool {
    let backup = PathBuf::from(format!("{}.esp-backup", pck_path.display()));
    if backup.exists() {
        return true;
    }
    if let Ok(pck) = GodotPck::load(pck_path) {
        return pck.has_file("res://esp_shim/ESPShim.gd");
    }
    false
}

pub fn uninstall_shim(
    pck_path: &Path,
    purge_user_data: bool,
    log: &dyn Fn(&str),
) -> io::Result<()> {
    if !is_esp_installed(pck_path) {
        return Err(io_err(&format!(
            "ESP doesn't appear to be installed at {}",
            pck_path.display()
        )));
    }

    let backup = PathBuf::from(format!("{}.esp-backup", pck_path.display()));
    if backup.exists() {
        log("Restoring PCK from backup...");
        // copy + remove is cross-filesystem safe; fs::rename can fail across mounts.
        fs::copy(&backup, pck_path)?;
        if let Err(e) = fs::remove_file(&backup) {
            log(&format!(
                "PCK restored, but failed to remove backup {}: {}",
                backup.display(),
                e
            ));
        }
    } else {
        log("Backup missing; stripping injected files from PCK in place...");
        let mut pck = GodotPck::load(pck_path)?;
        let removed_shim = pck.remove_file("res://esp_shim/ESPShim.gd");
        let removed_bootstrap = pck.remove_file("res://esp_bootstrap/ESPBootstrap.gd");
        let removed_override = pck.remove_file("res://override.cfg");
        if !removed_shim && !removed_bootstrap && !removed_override {
            log("No injected files found inside PCK; nothing to strip.");
        }
        pck.save(pck_path)?;
        log("Note: original override.cfg (if any) was discarded along with the ESP autoload entry. Verify the game still launches as expected.");
    }

    if let Some(game_dir) = pck_path.parent() {
        if purge_user_data {
            for sub in ["modloader", "mods", "levels", "campaigns"] {
                let dir = game_dir.join(sub);
                if dir.exists() {
                    match fs::remove_dir_all(&dir) {
                        Ok(_) => log(&format!("Removed {}", dir.display())),
                        Err(e) => log(&format!("Could not remove {}: {}", dir.display(), e)),
                    }
                }
            }
        } else {
            log("User data preserved (mods/, levels/, modloader/, campaigns/). Pass --purge to remove.");
        }
    }

    log("Uninstall complete.");
    Ok(())
}

/// Removes a partial file on drop unless `disarm()` is called. Used to clean up
/// half-downloaded zips when an error or panic occurs mid-stream.
struct PartialFileGuard {
    path: Option<PathBuf>,
}

impl PartialFileGuard {
    fn new(path: PathBuf) -> Self {
        Self { path: Some(path) }
    }
    fn disarm(mut self) {
        self.path = None;
    }
}

impl Drop for PartialFileGuard {
    fn drop(&mut self) {
        if let Some(p) = self.path.take() {
            let _ = fs::remove_file(p);
        }
    }
}

pub fn fetch_framework(config: &Config, log: &dyn Fn(&str)) -> io::Result<()> {
    let game_dir = config
        .game_path
        .as_ref()
        .ok_or_else(|| io_err("Game path unknown"))?;
    let target = game_dir.join("modloader/ExtraStimulantsPlus.zip");
    let partial = target.with_extension("zip.partial");
    if let Some(parent) = target.parent() {
        fs::create_dir_all(parent)?;
    }

    // Look up the latest release via the GitHub API. The asset name +
    // sibling `.sha256` are the convention this tool establishes; the CI
    // workflow on `v*` tags is responsible for producing both.
    log("Querying latest release...");
    let release = github::fetch_latest_release(github::REPO_OWNER, github::REPO_NAME)?;
    log(&format!("Latest release: {}", release.tag_name));

    let zip_asset = github::find_asset(&release, FRAMEWORK_ASSET_NAME).ok_or_else(|| {
        io_err(&format!(
            "Latest release {} has no '{}' asset",
            release.tag_name, FRAMEWORK_ASSET_NAME
        ))
    })?;
    let sha_asset = github::find_asset(&release, FRAMEWORK_SHA_ASSET_NAME).ok_or_else(|| {
        io_err(&format!(
            "Latest release {} has no '{}' asset",
            release.tag_name, FRAMEWORK_SHA_ASSET_NAME
        ))
    })?;

    let expected_sha = github::parse_sha256_file(&github::fetch_text(&sha_asset.browser_download_url)?)?;

    log("Downloading...");
    let mut response = reqwest::blocking::Client::builder()
        .timeout(std::time::Duration::from_secs(120))
        .build()
        .map_err(|e| io_err(&format!("HTTP client init failed: {}", e)))?
        .get(&zip_asset.browser_download_url)
        .header("User-Agent", format!("esp-tool/{}", env!("CARGO_PKG_VERSION")))
        .send()
        .map_err(|e| io_err(&e.to_string()))?;
    if !response.status().is_success() {
        return Err(io_err(&format!(
            "Framework download failed: HTTP {}",
            response.status()
        )));
    }
    // If the server reports a content length, refuse to start the download
    // when we know it won't fit. Avoids leaving a half-written zip on a full disk.
    if let Some(content_len) = response.content_length() {
        let parent = target.parent().unwrap_or(game_dir);
        if let Ok(available) = fs2::available_space(parent) {
            if available < content_len.saturating_add(1024 * 1024) {
                return Err(io_err(&format!(
                    "Not enough disk space at {}: need {} bytes, have {}",
                    parent.display(),
                    content_len,
                    available
                )));
            }
        }
    }
    let guard = PartialFileGuard::new(partial.clone());
    let mut hasher = Sha256::new();
    {
        let mut file = fs::File::create(&partial)?;
        let mut buf = [0u8; 64 * 1024];
        let mut total: u64 = 0;
        loop {
            let read = response.read(&mut buf)?;
            if read == 0 {
                break;
            }
            total = total.saturating_add(read as u64);
            if total > MAX_FRAMEWORK_SIZE {
                return Err(io_err(&format!(
                    "Framework download exceeded {} byte cap; aborting",
                    MAX_FRAMEWORK_SIZE
                )));
            }
            hasher.update(&buf[..read]);
            file.write_all(&buf[..read])?;
        }
        file.sync_all()?;
    }
    let computed = hex_lower(&hasher.finalize());
    if computed != expected_sha {
        return Err(io_err(&format!(
            "Framework hash mismatch for release {}: expected {}, got {}",
            release.tag_name, expected_sha, computed
        )));
    }
    // Atomic-ish swap: rename within the same dir; on Windows this falls back to remove+rename.
    if target.exists() {
        let _ = fs::remove_file(&target);
    }
    fs::rename(&partial, &target)?;
    guard.disarm();
    log("Done.");
    Ok(())
}

pub fn run_setup(config: &mut Config, logs: Arc<Mutex<String>>) -> io::Result<()> {
    let add_log = |msg: &str| {
        if let Ok(mut l) = logs.lock() {
            l.push_str(&format!(">> {}\n", msg));
        }
    };
    add_log("Starting auto-setup...");
    let pck = if let Some(p) = &config.pck_path {
        p.clone()
    } else {
        SteamScanner::new()
            .find_game_pck()
            .ok_or_else(|| io_err("Game not found"))?
    };
    config.pck_path = Some(pck.clone());
    if let Some(p) = pck.parent() {
        config.game_path = Some(p.to_path_buf());
    }
    let _ = config.save();
    add_log("Patching shim...");
    install_shim(&pck)?;
    add_log("Fetching framework...");
    fetch_framework(config, &add_log)?;
    add_log("Setup Complete!");
    Ok(())
}

fn hex_lower(bytes: &[u8]) -> String {
    bytes.iter().map(|b| format!("{:02x}", b)).collect()
}

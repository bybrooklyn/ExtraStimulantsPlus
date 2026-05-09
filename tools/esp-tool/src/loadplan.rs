use std::fs;
use std::io::{self, Read, Write};
use std::path::Path;

use serde::{Deserialize, Serialize};

use crate::config::Config;
use crate::error::io_err;
use crate::VERSION;

pub const LOAD_PLAN_FILE: &str = "modloader/load_plan.json";

#[derive(Serialize, Deserialize)]
pub struct LoadPlan {
    pub framework_version: String,
    pub mods: Vec<ModEntry>,
    pub levels: Vec<LevelEntry>,
    pub campaigns: Vec<CampaignEntry>,
    pub generated_at: String,
}

#[derive(Serialize, Deserialize)]
pub struct ModEntry {
    pub id: String,
    pub name: String,
    pub version: String,
    pub path: String,
    pub kind: String,
    #[serde(default, skip_serializing_if = "String::is_empty")]
    pub homepage: String,
    #[serde(default, skip_serializing_if = "String::is_empty")]
    pub repository: String,
}

#[derive(Serialize, Deserialize)]
pub struct LevelEntry {
    pub name: String,
    pub path: String,
    pub format: String,
}

#[derive(Serialize, Deserialize)]
pub struct CampaignEntry {
    pub name: String,
    pub path: String,
    pub format: String,
}

#[derive(Deserialize)]
pub struct ModJson {
    pub id: String,
    pub name: String,
    pub version: String,
    #[serde(default)]
    pub homepage: String,
    #[serde(default)]
    pub repository: serde_json::Value,
}

impl ModJson {
    /// Returns the repository URL whether the manifest stored a bare string
    /// or an `{"url": "..."}` dict (npm convention). Returns "" otherwise.
    pub fn repository_url(&self) -> String {
        match &self.repository {
            serde_json::Value::String(s) => s.trim().to_string(),
            serde_json::Value::Object(obj) => obj
                .get("url")
                .and_then(|v| v.as_str())
                .map(|s| s.trim().to_string())
                .unwrap_or_default(),
            _ => String::new(),
        }
    }
}

pub fn generate_load_plan(config: &Config) -> io::Result<()> {
    let game_dir = config
        .game_path
        .as_ref()
        .ok_or_else(|| io_err("Game path unknown"))?;

    let mods = scan_mods(&game_dir.join("mods"));
    let levels = scan_levels(&game_dir.join("levels"));
    let campaigns = scan_campaigns(&game_dir.join("campaigns"));
    let framework_version =
        read_framework_version(&game_dir.join("modloader/ExtraStimulantsPlus.zip"))
            .unwrap_or_else(|| VERSION.to_string());

    let plan = LoadPlan {
        framework_version,
        mods,
        levels,
        campaigns,
        generated_at: chrono::Utc::now().to_rfc3339(),
    };
    let plan_path = game_dir.join(LOAD_PLAN_FILE);
    if let Some(parent) = plan_path.parent() {
        fs::create_dir_all(parent)?;
    }
    let body = serde_json::to_string_pretty(&plan)
        .map_err(|e| io_err(&format!("load_plan serialize failed: {}", e)))?;
    // Use explicit write+sync_all instead of fs::write so the bytes are durable
    // before the game opens the file. Without sync_all, a launch racing the
    // write could observe a truncated load plan on a crash or hard reboot.
    let mut file = fs::File::create(&plan_path)?;
    file.write_all(body.as_bytes())?;
    file.sync_all()?;
    Ok(())
}

pub fn scan_mods(mods_dir: &Path) -> Vec<ModEntry> {
    let mut out = Vec::new();
    let entries = match fs::read_dir(mods_dir) {
        Ok(e) => e,
        Err(_) => return out,
    };
    for entry in entries.flatten() {
        let path = entry.path();
        if path.is_dir() {
            if let Ok(meta_str) = fs::read_to_string(path.join("mod.json")) {
                if let Ok(meta) = serde_json::from_str::<ModJson>(&meta_str) {
                    let repository = meta.repository_url();
                    out.push(ModEntry {
                        id: meta.id,
                        name: meta.name,
                        version: meta.version,
                        path: path.to_string_lossy().into_owned(),
                        kind: "folder".into(),
                        homepage: meta.homepage,
                        repository,
                    });
                }
            }
        } else if path.is_file() {
            let ext = path
                .extension()
                .and_then(|s| s.to_str())
                .map(|s| s.to_ascii_lowercase())
                .unwrap_or_default();
            if ext == "zip" || ext == "pck" {
                if let Some(meta) = read_mod_json_from_zip(&path) {
                    let repository = meta.repository_url();
                    out.push(ModEntry {
                        id: meta.id,
                        name: meta.name,
                        version: meta.version,
                        path: path.to_string_lossy().into_owned(),
                        kind: ext,
                        homepage: meta.homepage,
                        repository,
                    });
                }
            }
        }
    }
    out
}

pub fn scan_levels(levels_dir: &Path) -> Vec<LevelEntry> {
    let mut out = Vec::new();
    let entries = match fs::read_dir(levels_dir) {
        Ok(e) => e,
        Err(_) => return out,
    };
    for entry in entries.flatten() {
        let path = entry.path();
        if !path.is_file() {
            continue;
        }
        let ext = path
            .extension()
            .and_then(|s| s.to_str())
            .map(|s| s.to_ascii_lowercase())
            .unwrap_or_default();
        if ext != "solv" && ext != "json" && ext != "somap" {
            continue;
        }
        let name = path
            .file_stem()
            .and_then(|s| s.to_str())
            .unwrap_or("")
            .to_string();
        out.push(LevelEntry {
            name,
            path: path.to_string_lossy().into_owned(),
            format: ext,
        });
    }
    out
}

pub fn scan_campaigns(campaigns_dir: &Path) -> Vec<CampaignEntry> {
    let mut out = Vec::new();
    let entries = match fs::read_dir(campaigns_dir) {
        Ok(e) => e,
        Err(_) => return out,
    };
    for entry in entries.flatten() {
        let path = entry.path();
        if !path.is_file() {
            continue;
        }
        let ext = path
            .extension()
            .and_then(|s| s.to_str())
            .map(|s| s.to_ascii_lowercase())
            .unwrap_or_default();
        if ext != "somapbundle" {
            continue;
        }
        let name = path
            .file_stem()
            .and_then(|s| s.to_str())
            .unwrap_or("")
            .to_string();
        out.push(CampaignEntry {
            name,
            path: path.to_string_lossy().into_owned(),
            format: ext,
        });
    }
    out
}

/// Hard cap on per-mod zip entry count; mirrors pck.rs::MAX_PCK_FILES.
/// Defends against zip-bomb metadata DoS where a tiny file declares millions
/// of entries, stalling GUI scans.
const MAX_MOD_ZIP_ENTRIES: usize = 10_000;

pub fn read_mod_json_from_zip(zip_path: &Path) -> Option<ModJson> {
    let file = fs::File::open(zip_path).ok()?;
    let mut archive = zip::ZipArchive::new(file).ok()?;
    if archive.len() > MAX_MOD_ZIP_ENTRIES {
        return None;
    }
    let mut nested: Option<String> = None;
    for i in 0..archive.len() {
        let name = archive.by_index(i).ok()?.name().to_string();
        if name == "mod.json" {
            let mut entry = archive.by_index(i).ok()?;
            let mut s = String::new();
            entry.read_to_string(&mut s).ok()?;
            return serde_json::from_str(&s).ok();
        }
        if nested.is_none() && name.ends_with("/mod.json") {
            nested = Some(name);
        }
    }
    if let Some(n) = nested {
        let mut entry = archive.by_name(&n).ok()?;
        let mut s = String::new();
        entry.read_to_string(&mut s).ok()?;
        return serde_json::from_str(&s).ok();
    }
    None
}

pub fn read_framework_version(zip_path: &Path) -> Option<String> {
    read_mod_json_from_zip(zip_path).map(|m| m.version)
}

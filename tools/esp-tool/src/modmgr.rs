use std::collections::HashMap;
use std::fs;
use std::io;
use std::path::{Path, PathBuf};
use std::time::SystemTime;

use eframe::egui;
use serde::{Deserialize, Serialize};

use crate::error::io_err;
use crate::loadplan::{scan_mods, ModEntry};
use crate::modhash;

// ---------------------------------------------------------------------------
// User-profile state file (godot-mod-loader compatible schema).
// ---------------------------------------------------------------------------

const USER_PROFILE_FILE: &str = "modloader/user_profile.json";
const MOD_STATUSES_FILE: &str = "modloader/mod_statuses.json";

#[derive(Serialize, Deserialize, Clone)]
pub struct UserProfile {
    pub name: String,
    pub mod_list: HashMap<String, UserProfileMod>,
}

#[derive(Serialize, Deserialize, Clone, Default)]
pub struct UserProfileMod {
    pub enabled: bool,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub current_config: Option<String>,
}

impl Default for UserProfile {
    fn default() -> Self {
        Self {
            name: "default".into(),
            mod_list: HashMap::new(),
        }
    }
}

pub fn profile_path(game_dir: &Path) -> PathBuf {
    game_dir.join(USER_PROFILE_FILE)
}

pub fn load_profile(game_dir: &Path) -> UserProfile {
    let path = profile_path(game_dir);
    fs::read_to_string(&path)
        .ok()
        .and_then(|s| serde_json::from_str(&s).ok())
        .unwrap_or_default()
}

pub fn save_profile(game_dir: &Path, profile: &UserProfile) -> io::Result<()> {
    let path = profile_path(game_dir);
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)?;
    }
    let body = serde_json::to_string_pretty(profile)
        .map_err(|e| io_err(&format!("user_profile serialize failed: {}", e)))?;
    fs::write(&path, body)
}

pub fn set_mod_enabled(game_dir: &Path, mod_id: &str, enabled: bool) -> io::Result<()> {
    let mut profile = load_profile(game_dir);
    let entry = profile.mod_list.entry(mod_id.to_string()).or_default();
    entry.enabled = enabled;
    save_profile(game_dir, &profile)
}

pub fn is_mod_enabled(profile: &UserProfile, mod_id: &str) -> bool {
    profile
        .mod_list
        .get(mod_id)
        .map(|m| m.enabled)
        .unwrap_or(true)
}

// ---------------------------------------------------------------------------
// Mod-list view and panel.
// ---------------------------------------------------------------------------

pub struct ModsView {
    pub entries: Vec<ModViewItem>,
    pub last_mods_mtime: Option<SystemTime>,
    pub last_status_mtime: Option<SystemTime>,
    pub install_message: String,
}

pub struct ModViewItem {
    pub id: String,
    pub name: String,
    pub version: String,
    pub kind: String,
    pub path: String,
    pub enabled: bool,
    pub status: String,
    pub reason: String,
    pub verification_status: String,
    pub compat_warning: String,
    pub expected_sha256: String,
    pub computed_sha256: String,
    pub homepage: String,
    pub repository: String,
}

impl Default for ModsView {
    fn default() -> Self {
        Self {
            entries: Vec::new(),
            last_mods_mtime: None,
            last_status_mtime: None,
            install_message: String::new(),
        }
    }
}

pub fn refresh(game_dir: &Path) -> ModsView {
    let entries = build_entries(game_dir);
    ModsView {
        entries,
        last_mods_mtime: dir_mtime(&game_dir.join("mods")),
        last_status_mtime: file_mtime(&game_dir.join(MOD_STATUSES_FILE)),
        install_message: String::new(),
    }
}

pub fn refresh_if_stale(game_dir: &Path, view: &mut ModsView) {
    let mods_mtime = dir_mtime(&game_dir.join("mods"));
    let status_mtime = file_mtime(&game_dir.join(MOD_STATUSES_FILE));
    if mods_mtime != view.last_mods_mtime || status_mtime != view.last_status_mtime {
        view.entries = build_entries(game_dir);
        view.last_mods_mtime = mods_mtime;
        view.last_status_mtime = status_mtime;
    }
}

fn build_entries(game_dir: &Path) -> Vec<ModViewItem> {
    let mods: Vec<ModEntry> = scan_mods(&game_dir.join("mods"));
    let profile = load_profile(game_dir);
    let statuses = load_statuses(game_dir);

    let mut out: Vec<ModViewItem> = mods
        .into_iter()
        .map(|m| {
            let enabled = is_mod_enabled(&profile, &m.id);
            let (status, reason) = statuses
                .get(&m.id)
                .map(|s| (s.status.clone(), s.reason.clone()))
                .unwrap_or_else(|| ("discovered".into(), String::new()));
            let verification_status = statuses
                .get(&m.id)
                .map(|s| s.verification_status.clone())
                .unwrap_or_default();
            let compat_warning = statuses
                .get(&m.id)
                .map(|s| s.compat_warning.clone())
                .unwrap_or_default();
            let expected_sha256 = statuses
                .get(&m.id)
                .map(|s| s.expected_sha256.clone())
                .unwrap_or_default();
            let computed_sha256 = statuses
                .get(&m.id)
                .map(|s| s.computed_sha256.clone())
                .unwrap_or_default();
            ModViewItem {
                id: m.id,
                name: m.name,
                version: m.version,
                kind: m.kind,
                path: m.path,
                enabled,
                status,
                reason,
                verification_status,
                compat_warning,
                expected_sha256,
                computed_sha256,
                homepage: m.homepage,
                repository: m.repository,
            }
        })
        .collect();
    out.sort_by(|a, b| a.id.cmp(&b.id));
    out
}

#[derive(Deserialize, Default)]
struct StatusRow {
    #[serde(default)]
    status: String,
    #[serde(default)]
    reason: String,
    #[serde(default)]
    verification_status: String,
    #[serde(default)]
    compat_warning: String,
    #[serde(default)]
    expected_sha256: String,
    #[serde(default)]
    computed_sha256: String,
}

fn load_statuses(game_dir: &Path) -> HashMap<String, StatusRow> {
    let path = game_dir.join(MOD_STATUSES_FILE);
    fs::read_to_string(&path)
        .ok()
        .and_then(|s| serde_json::from_str(&s).ok())
        .unwrap_or_default()
}

fn dir_mtime(p: &Path) -> Option<SystemTime> {
    fs::metadata(p).ok().and_then(|m| m.modified().ok())
}

fn file_mtime(p: &Path) -> Option<SystemTime> {
    fs::metadata(p).ok().and_then(|m| m.modified().ok())
}

pub fn draw_panel(ui: &mut egui::Ui, game_dir: &Path, view: &mut ModsView) {
    egui::CollapsingHeader::new(egui::RichText::new("Mods").strong())
        .default_open(true)
        .show(ui, |ui| {
            ui.horizontal(|ui| {
                if ui.button("Refresh").clicked() {
                    *view = refresh(game_dir);
                }
                if ui.button("Install Mod...").clicked() {
                    if let Some(picked) = rfd::FileDialog::new()
                        .add_filter("Godot mod", &["zip", "pck"])
                        .set_title("Choose a mod (.zip or .pck) to install")
                        .pick_file()
                    {
                        match install_mod_file(game_dir, &picked) {
                            Ok(name) => {
                                view.install_message = format!("Installed {}", name);
                                *view = refresh(game_dir);
                                view.install_message = format!("Installed {}", name);
                            }
                            Err(e) => view.install_message = format!("Install failed: {}", e),
                        }
                    }
                }
                ui.label(
                    egui::RichText::new("changes apply on next launch")
                        .italics()
                        .weak(),
                );
            });
            if !view.install_message.is_empty() {
                ui.label(&view.install_message);
            }

            ui.add_space(4.0);

            if view.entries.is_empty() {
                ui.label(
                    egui::RichText::new("(no mods discovered in mods/)")
                        .italics()
                        .weak(),
                );
                return;
            }

            for entry in view.entries.iter_mut() {
                ui.horizontal(|ui| {
                    let mut checked = entry.enabled;
                    if ui.checkbox(&mut checked, "").changed() {
                        if let Err(e) = set_mod_enabled(game_dir, &entry.id, checked) {
                            view.install_message = format!("Toggle failed: {}", e);
                        } else {
                            entry.enabled = checked;
                        }
                    }
                    ui.label(egui::RichText::new(&entry.name).strong());
                    ui.label(egui::RichText::new(&entry.version).weak());
                    ui.label(status_chip(&entry.status));
                    if !entry.verification_status.is_empty() {
                        ui.label(verification_chip(&entry.verification_status));
                    }
                });
                if !entry.reason.is_empty() {
                    ui.label(egui::RichText::new(format!("    └─ {}", entry.reason)).weak());
                }
                if !entry.compat_warning.is_empty() {
                    ui.label(
                        egui::RichText::new(format!("    └─ {}", entry.compat_warning))
                            .color(egui::Color32::from_rgb(220, 190, 90))
                            .weak(),
                    );
                }
                ui.collapsing(format!("details — {}", entry.id), |ui| {
                    ui.label(format!("id:      {}", entry.id));
                    ui.label(format!("kind:    {}", entry.kind));
                    ui.label(format!("path:    {}", entry.path));
                    if !entry.homepage.is_empty() {
                        ui.horizontal(|ui| {
                            ui.label("homepage:");
                            ui.hyperlink(&entry.homepage);
                        });
                    }
                    if !entry.repository.is_empty() {
                        ui.horizontal(|ui| {
                            ui.label("repository:");
                            ui.hyperlink(&entry.repository);
                        });
                    }
                    if !entry.expected_sha256.is_empty() {
                        ui.label(format!("expected sha256: {}", entry.expected_sha256));
                    }
                    if !entry.computed_sha256.is_empty() {
                        ui.label(format!("computed sha256: {}", entry.computed_sha256));
                    }
                });
            }
        });
}

fn status_chip(status: &str) -> egui::RichText {
    let color = match status {
        "loaded" => egui::Color32::from_rgb(80, 200, 120),
        "failed" | "errored" => egui::Color32::from_rgb(220, 90, 90),
        "disabled" => egui::Color32::from_rgb(160, 160, 160),
        "discovered" | "validating" | "preloaded" | "preloading" | "initialized"
        | "initializing" | "readying" => egui::Color32::from_rgb(200, 180, 90),
        _ => egui::Color32::from_rgb(180, 180, 180),
    };
    egui::RichText::new(status).color(color).monospace()
}

fn verification_chip(status: &str) -> egui::RichText {
    let color = match status {
        "verified" => egui::Color32::from_rgb(0, 255, 255),
        "hash_mismatch" | "invalid_hash" | "missing_hash" | "missing_hash_index"
        | "unverifiable" | "unreadable" => egui::Color32::from_rgb(220, 90, 90),
        _ => egui::Color32::from_rgb(180, 180, 180),
    };
    egui::RichText::new(status).color(color).monospace()
}

fn install_mod_file(game_dir: &Path, src: &Path) -> io::Result<String> {
    let mods_dir = game_dir.join("mods");
    fs::create_dir_all(&mods_dir)?;
    let name = src
        .file_name()
        .ok_or_else(|| io_err("Picked path has no file name"))?
        .to_string_lossy()
        .into_owned();
    let dest = mods_dir.join(&name);
    fs::copy(src, &dest)?;
    if let Err(e) = modhash::record_installed_mod(game_dir, &dest) {
        let _ = fs::remove_file(&dest);
        return Err(e);
    }
    Ok(name)
}

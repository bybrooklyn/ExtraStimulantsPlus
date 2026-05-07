use std::collections::BTreeMap;
use std::env;
use std::fs;
use std::io::{self, Read, Seek, Write};
use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::{Arc, Mutex};
use std::thread;

use eframe::egui;
use serde::{Deserialize, Serialize};
use zip::write::SimpleFileOptions;
use walkdir::WalkDir;

const VERSION: &str = "0.0.2";
const CONFIG_FILE: &str = ".esp-config.json";
const LOAD_PLAN_FILE: &str = "modloader/load_plan.json";
const FRAMEWORK_URL: &str = "https://github.com/bybrooklyn/extrastimulantsplus/releases/latest/download/ExtraStimulantsPlus.zip";

// Embedded bootstrap files
const SHIM_GD: &[u8] = include_bytes!("../../../esp_shim/ESPShim.gd");
const BOOTSTRAP_GD: &[u8] = include_bytes!("../../../esp_bootstrap/ESPBootstrap.gd");
const OVERRIDE_CFG: &[u8] = include_bytes!("../../../esp_bootstrap/override.cfg");

#[derive(Serialize, Deserialize, Default, Clone)]
struct Config {
    game_path: Option<PathBuf>,
    pck_path: Option<PathBuf>,
}

impl Config {
    fn load() -> Self {
        fs::read_to_string(CONFIG_FILE)
            .ok()
            .and_then(|s| serde_json::from_str(&s).ok())
            .unwrap_or_default()
    }
    fn save(&self) -> io::Result<()> {
        let data = serde_json::to_string_pretty(self).unwrap();
        fs::write(CONFIG_FILE, data)
    }
}

#[derive(Serialize, Deserialize)]
struct LoadPlan {
    framework_version: String,
    mods: Vec<ModEntry>,
    levels: Vec<LevelEntry>,
    generated_at: String,
}

#[derive(Serialize, Deserialize)]
struct ModEntry { id: String, name: String, version: String, path: String, kind: String }

#[derive(Serialize, Deserialize)]
struct LevelEntry { name: String, path: String, format: String }

#[derive(Deserialize)]
struct ModJson { id: String, name: String, version: String }

struct EspApp {
    config: Config,
    logs: Arc<Mutex<String>>,
    status: String,
    install_running: bool,
}

impl EspApp {
    fn new(cc: &eframe::CreationContext<'_>) -> Self {
        let mut visuals = egui::Visuals::dark();
        visuals.window_rounding = 8.0.into();
        visuals.widgets.active.bg_fill = egui::Color32::from_rgb(0, 200, 255);
        cc.egui_ctx.set_visuals(visuals);

        Self {
            config: Config::load(),
            logs: Arc::new(Mutex::new(String::new())),
            status: "Ready".to_string(),
            install_running: false,
        }
    }
}

impl eframe::App for EspApp {
    fn update(&mut self, ctx: &egui::Context, _frame: &mut eframe::Frame) {
        egui::CentralPanel::default().show(ctx, |ui| {
            ui.vertical_centered(|ui| {
                ui.heading(egui::RichText::new("ESP Orchestrator").size(32.0).strong().color(egui::Color32::from_rgb(0, 255, 255)));
                ui.label(format!("Framework Version: {}", VERSION));
            });

            ui.add_space(20.0);

            ui.group(|ui| {
                ui.set_width(ui.available_width());
                ui.label(egui::RichText::new("Game Installation").strong());
                if let Some(path) = &self.config.pck_path {
                    ui.label(format!("Path: {}", path.display()));
                } else {
                    ui.label("Status: Not Detected");
                }

                if ui.button("Auto-Detect via Steam").clicked() {
                    if let Some(pck) = SteamScanner::new().find_game_pck() {
                        self.config.pck_path = Some(pck.clone());
                        if let Some(p) = pck.parent() { self.config.game_path = Some(p.to_path_buf()); }
                        let _ = self.config.save();
                        self.status = "Game detected!".to_string();
                    } else {
                        self.status = "Steam path not found.".to_string();
                    }
                }
            });

            ui.add_space(10.0);

            ui.horizontal(|ui| {
                if ui.add_enabled(!self.install_running, egui::Button::new("ONE-CLICK SETUP").min_size([120.0, 40.0].into())).clicked() {
                    self.install_running = true;
                    let logs = Arc::clone(&self.logs);
                    let mut cfg = self.config.clone();
                    thread::spawn(move || {
                        let _ = run_setup(&mut cfg, logs);
                    });
                }

                if ui.add_enabled(self.config.pck_path.is_some(), egui::Button::new("LAUNCH GAME").min_size([120.0, 40.0].into())).clicked() {
                    let cfg = self.config.clone();
                    thread::spawn(move || {
                        let _ = generate_load_plan(&cfg);
                        let _ = launch_game(&cfg, false);
                    });
                }
            });

            ui.add_space(10.0);

            ui.label("Logs:");
            egui::ScrollArea::vertical().stick_to_bottom(true).show(ui, |ui| {
                let logs = self.logs.lock().unwrap();
                ui.add(egui::TextEdit::multiline(&mut logs.as_str())
                    .font(egui::TextStyle::Monospace)
                    .desired_width(f32::INFINITY)
                    .desired_rows(15)
                    .lock_focus(true));
            });

            ui.with_layout(egui::Layout::bottom_up(egui::Align::LEFT), |ui| {
                ui.label(format!("Status: {}", self.status));
            });
        });
        ctx.request_repaint();
    }
}

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() > 1 {
        let mut config = Config::load();
        if let Err(err) = run_cli(&mut config, args) {
            eprintln!("error: {}", err);
            std::process::exit(1);
        }
    } else {
        let options = eframe::NativeOptions {
            viewport: egui::ViewportBuilder::default().with_inner_size([600.0, 500.0]),
            ..Default::default()
        };
        let _ = eframe::run_native("ESP Orchestrator", options, Box::new(|cc| Box::new(EspApp::new(cc))));
    }
}

fn run_cli(config: &mut Config, mut args: Vec<String>) -> io::Result<()> {
    let command = args.remove(1);
    match command.as_str() {
        "install" => {
            let pck = if args.len() > 1 { PathBuf::from(&args[1]) } else { SteamScanner::new().find_game_pck().ok_or_else(|| io_err("Not found"))? };
            install_shim(&pck)
        }
        "launch" => {
            let no_mods = args.contains(&"--no-mods".to_string());
            let _ = generate_load_plan(config);
            launch_game(config, no_mods)
        }
        "pack" => {
            let output = args.get(1).ok_or_else(|| io_err("Missing output path"))?;
            pack_core(Path::new("."), Path::new(output))
        }
        _ => Err(io_err("Unknown command")),
    }
}

fn run_setup(config: &mut Config, logs: Arc<Mutex<String>>) -> io::Result<()> {
    let add_log = |msg: &str| { if let Ok(mut l) = logs.lock() { l.push_str(&format!(">> {}\n", msg)); } };
    add_log("Starting auto-setup...");
    let pck = if let Some(p) = &config.pck_path { p.clone() } else { SteamScanner::new().find_game_pck().ok_or_else(|| io_err("Game not found"))? };
    config.pck_path = Some(pck.clone());
    if let Some(p) = pck.parent() { config.game_path = Some(p.to_path_buf()); }
    let _ = config.save();
    add_log("Patching shim...");
    install_shim(&pck)?;
    add_log("Fetching framework...");
    fetch_framework(config, &add_log)?;
    add_log("Setup Complete!");
    Ok(())
}

fn install_shim(pck_path: &Path) -> io::Result<()> {
    let backup = PathBuf::from(format!("{}.esp-backup", pck_path.display()));
    if !backup.exists() { fs::copy(pck_path, &backup)?; }
    let mut pck = GodotPck::load(pck_path)?;
    pck.add_file("res://esp_shim/ESPShim.gd", SHIM_GD.to_vec(), 0);
    pck.add_file("res://esp_bootstrap/ESPBootstrap.gd", BOOTSTRAP_GD.to_vec(), 0);
    let merged = merge_override_cfg(pck.files.get("res://override.cfg").map(|f| f.data.as_slice()), std::str::from_utf8(OVERRIDE_CFG).unwrap());
    pck.add_file("res://override.cfg", merged.into_bytes(), 0);
    pck.save(pck_path)?;
    if let Some(game_dir) = pck_path.parent() {
        fs::create_dir_all(game_dir.join("modloader"))?;
        fs::create_dir_all(game_dir.join("mods"))?;
        fs::create_dir_all(game_dir.join("levels"))?;
    }
    Ok(())
}

fn fetch_framework(config: &Config, log: &dyn Fn(&str)) -> io::Result<()> {
    let game_dir = config.game_path.as_ref().ok_or_else(|| io_err("Game path unknown"))?;
    let target = game_dir.join("modloader/ExtraStimulantsPlus.zip");
    log("Downloading...");
    let mut response = reqwest::blocking::get(FRAMEWORK_URL).map_err(|e| io_err(&e.to_string()))?;
    if response.status().is_success() {
        let mut file = fs::File::create(target)?;
        io::copy(&mut response, &mut file)?;
        log("Done.");
    } else { log(&format!("Failed: {}", response.status())); }
    Ok(())
}

fn generate_load_plan(config: &Config) -> io::Result<()> {
    let game_dir = config.game_path.as_ref().ok_or_else(|| io_err("Game path unknown"))?;
    let mut mods = Vec::new();
    let mods_dir = game_dir.join("mods");
    if mods_dir.exists() {
        for entry in fs::read_dir(mods_dir)? {
            let entry = entry?; let path = entry.path();
            if path.is_dir() {
                if let Ok(meta_str) = fs::read_to_string(path.join("mod.json")) {
                    if let Ok(meta) = serde_json::from_str::<ModJson>(&meta_str) {
                        mods.push(ModEntry { id: meta.id, name: meta.name, version: meta.version, path: path.to_string_lossy().to_string(), kind: "folder".to_string() });
                    }
                }
            }
        }
    }
    let plan = LoadPlan { framework_version: VERSION.to_string(), mods, levels: vec![], generated_at: "".to_string() };
    fs::write(game_dir.join(LOAD_PLAN_FILE), serde_json::to_string_pretty(&plan).unwrap())
}

fn launch_game(config: &Config, no_mods: bool) -> io::Result<()> {
    let pck_path = config.pck_path.as_ref().ok_or_else(|| io_err("Not installed"))?;
    let game_dir = pck_path.parent().unwrap();
    let bin_name = if cfg!(windows) { "SensoryOverload.exe" } else { "SensoryOverload.x86_64" };
    let mut cmd = Command::new(game_dir.join(bin_name));
    cmd.current_dir(game_dir);
    if no_mods { cmd.arg("--no-esp-mods"); }
    cmd.spawn()?.wait()?;
    Ok(())
}

struct GodotPck { version: u32, major: u32, minor: u32, patch: u32, files: BTreeMap<String, PckFile> }
#[derive(Clone)] struct PckFile { size: u64, md5: [u8; 16], flags: u32, data: Vec<u8> }

impl GodotPck {
    fn load(path: &Path) -> io::Result<Self> {
        let blob = fs::read(path)?;
        let mut cursor = PckCursor { data: &blob, pos: 0 };
        if cursor.read_exact(4)? != b"GDPC" { return Err(io_err("Invalid PCK")); }
        let version = cursor.u32()?;
        let major = cursor.u32()?; let minor = cursor.u32()?; let patch = cursor.u32()?;
        cursor.skip(64)?;
        let count = cursor.u32()? as usize;
        let mut files = BTreeMap::new();
        for _ in 0..count {
            let path_len = cursor.u32()? as usize;
            let file_path = String::from_utf8_lossy(cursor.read_exact(path_len)?).replace('\0', "");
            let offset = cursor.u64()? as usize;
            let size = cursor.u64()? as usize;
            let md5 = cursor.md5()?;
            let flags = if version >= 2 { cursor.u32()? } else { 0 };
            files.insert(file_path, PckFile { size: size as u64, md5, flags, data: blob[offset..offset + size].to_vec() });
        }
        Ok(Self { version, major, minor, patch, files })
    }
    fn add_file(&mut self, path: &str, data: Vec<u8>, flags: u32) {
        let norm = if path.starts_with("res://") { path.to_string() } else { format!("res://{}", path.trim_start_matches('/')) };
        self.files.insert(norm, PckFile { size: data.len() as u64, md5: md5_bytes(&data), flags, data });
    }
    fn save(&self, path: &Path) -> io::Result<()> {
        let mut index_size = 88usize;
        for fp in self.files.keys() { index_size += 4 + fp.as_bytes().len() + 8 + 8 + 16 + 4; }
        let mut offsets = BTreeMap::new();
        let mut cur = align32(index_size as u64);
        for (fp, file) in &self.files { offsets.insert(fp.clone(), cur); cur = align32(cur + file.size); }
        let tmp = PathBuf::from(format!("{}.tmp", path.display()));
        let mut out = fs::File::create(&tmp)?;
        out.write_all(b"GDPC")?;
        write_u32(&mut out, self.version)?; write_u32(&mut out, self.major)?;
        write_u32(&mut out, self.minor)?; write_u32(&mut out, self.patch)?;
        out.write_all(&[0u8; 64])?;
        write_u32(&mut out, self.files.len() as u32)?;
        for (fp, file) in &self.files {
            let p = fp.as_bytes();
            write_u32(&mut out, p.len() as u32)?; out.write_all(p)?;
            write_u64(&mut out, offsets[fp])?; write_u64(&mut out, file.size)?;
            out.write_all(&file.md5)?; write_u32(&mut out, file.flags)?;
        }
        for (fp, file) in &self.files { pad_to(&mut out, offsets[fp])?; out.write_all(&file.data)?; }
        out.flush()?; fs::rename(tmp, path)?; Ok(())
    }
}

struct PckCursor<'a> { data: &'a [u8], pos: usize }
impl<'a> PckCursor<'a> {
    fn read_exact(&mut self, n: usize) -> io::Result<&'a [u8]> {
        let end = self.pos + n;
        if end > self.data.len() { return Err(io_err("EOF")); }
        let slice = &self.data[self.pos..end];
        self.pos = end;
        Ok(slice)
    }
    fn skip(&mut self, n: usize) -> io::Result<()> { self.read_exact(n).map(|_| ()) }
    fn u32(&mut self) -> io::Result<u32> { let b = self.read_exact(4)?; Ok(u32::from_le_bytes([b[0], b[1], b[2], b[3]])) }
    fn u64(&mut self) -> io::Result<u64> { let b = self.read_exact(8)?; Ok(u64::from_le_bytes([b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7]])) }
    fn md5(&mut self) -> io::Result<[u8; 16]> { let b = self.read_exact(16)?; let mut out = [0u8; 16]; out.copy_from_slice(b); Ok(out) }
}

fn write_u32<W: Write>(w: &mut W, n: u32) -> io::Result<()> { w.write_all(&n.to_le_bytes()) }
fn write_u64<W: Write>(w: &mut W, n: u64) -> io::Result<()> { w.write_all(&n.to_le_bytes()) }
fn align32(n: u64) -> u64 { (n + 31) & !31 }
fn pad_to<W: Write + Seek>(w: &mut W, offset: u64) -> io::Result<()> {
    let current = w.stream_position()?;
    if current < offset { w.write_all(&vec![0u8; (offset - current) as usize])?; }
    Ok(())
}

fn md5_bytes(input: &[u8]) -> [u8; 16] {
    let mut a0: u32 = 0x67452301; let mut b0: u32 = 0xefcdab89;
    let mut c0: u32 = 0x98badcfe; let mut d0: u32 = 0x10325476;
    let mut msg = input.to_vec(); let bit_len = (msg.len() as u64) * 8;
    msg.push(0x80); while msg.len() % 64 != 56 { msg.push(0); }
    msg.extend_from_slice(&bit_len.to_le_bytes());
    let s: [u32; 64] = [7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21];
    let k: [u32; 64] = [0xd76aa478, 0xe8c7b756, 0x242070db, 0xc1bdceee, 0xf57c0faf, 0x4787c62a, 0xa8304613, 0xfd469501, 0x698098d8, 0x8b44f7af, 0xffff5bb1, 0x895cd7be, 0x6b901122, 0xfd987193, 0xa679438e, 0x49b40821, 0xf61e2562, 0xc040b340, 0x265e5a51, 0xe9b6c7aa, 0xd62f105d, 0x02441453, 0xd8a1e681, 0xe7d3fbc8, 0x21e1cde6, 0xc33707d6, 0xf4d50d87, 0x455a14ed, 0xa9e3e905, 0xfcefa3f8, 0x676f02d9, 0x8d2a4c8a, 0xfffa3942, 0x8771f681, 0x6d9d6122, 0xfde5380c, 0xa4beea44, 0x4bdecfa9, 0xf6bb4b60, 0xbebfbc70, 0x289b7ec6, 0xeaa127fa, 0xd4ef3085, 0x04881d05, 0xd9d4d039, 0xe6db99e5, 0x1fa27cf8, 0xc4ac5665, 0xf4292244, 0x432aff97, 0xab9423a7, 0xfc93a039, 0x655b59c3, 0x8f0ccc92, 0xffeff47d, 0x85845dd1, 0x6fa87e4f, 0xfe2ce6e0, 0xa3014314, 0x4e0811a1, 0xf7537e82, 0xbd3af235, 0x2ad7d2bb, 0xeb86d391];
    for chunk in msg.chunks_exact(64) {
        let mut m = [0u32; 16];
        for (i, word) in m.iter_mut().enumerate() { let j = i * 4; *word = u32::from_le_bytes([chunk[j], chunk[j + 1], chunk[j + 2], chunk[j + 3]]); }
        let mut a = a0; let mut b = b0; let mut c = c0; let mut d = d0;
        for i in 0..64 {
            let (f, g) = if i < 16 { ((b & c) | ((!b) & d), i) } else if i < 32 { ((d & b) | ((!d) & c), (5 * i + 1) % 16) } else if i < 48 { (b ^ c ^ d, (3 * i + 5) % 16) } else { (c ^ (b | (!d)), (7 * i) % 16) };
            let tmp = d; d = c; c = b; b = b.wrapping_add(a.wrapping_add(f).wrapping_add(k[i]).wrapping_add(m[g]).rotate_left(s[i])); a = tmp;
        }
        a0 = a0.wrapping_add(a); b0 = b0.wrapping_add(b); c0 = c0.wrapping_add(c); d0 = d0.wrapping_add(d);
    }
    let mut out = [0u8; 16];
    out[0..4].copy_from_slice(&a0.to_le_bytes()); out[4..8].copy_from_slice(&b0.to_le_bytes()); out[8..12].copy_from_slice(&c0.to_le_bytes()); out[12..16].copy_from_slice(&d0.to_le_bytes());
    out
}

fn merge_override_cfg(existing: Option<&[u8]>, _shim: &str) -> String {
    let line = r#"ESPShim="*res://esp_shim/ESPShim.gd""#;
    let mut text = existing.map(|b| String::from_utf8_lossy(b).to_string()).unwrap_or_default();
    if text.contains("ESPShim") { return text; }
    if let Some(start) = text.find("[autoload]") {
        let pos = text[start..].find('\n').map(|n| start + n + 1).unwrap_or(text.len());
        text.insert_str(pos, &format!("{line}\n"));
    } else { text.push_str(&format!("\n\n[autoload]\n\n{line}\n")); }
    text
}

struct SteamScanner { base_paths: Vec<PathBuf> }
impl SteamScanner {
    fn new() -> Self {
        let mut base_paths = Vec::new();
        if cfg!(windows) {
            #[cfg(windows)] {
                use winreg::enums::*;
                use winreg::RegKey;
                if let Ok(steam) = RegKey::predef(HKEY_CURRENT_USER).open_subkey("Software\\Valve\\Steam") {
                    if let Ok(path) = steam.get_value::<String, _>("SteamPath") { base_paths.push(PathBuf::from(path)); }
                }
            }
        } else {
            if let Ok(home) = env::var("HOME") { base_paths.push(PathBuf::from(format!("{}/.local/share/Steam", home))); }
            base_paths.push(PathBuf::from("/usr/share/Steam"));
            if let Ok(entries) = fs::read_dir("/run/media/") { for entry in entries.flatten() { base_paths.push(entry.path()); } }
        }
        Self { base_paths }
    }
    fn find_game_pck(&self) -> Option<PathBuf> {
        for base in &self.base_paths {
            let lib = base.join("config/libraryfolders.vdf");
            if let Ok(content) = fs::read_to_string(lib) {
                for line in content.lines() {
                    if line.contains("\"path\"") {
                        let path = line.split('"').nth(3).unwrap_or("");
                        let pck = PathBuf::from(path).join("steamapps/common/Sensory Overload/SensoryOverload.pck");
                        if pck.exists() { return Some(pck); }
                    }
                }
            }
        }
        None
    }
}

fn io_err(m: &str) -> io::Error { io::Error::new(io::ErrorKind::Other, m) }

fn pack_core(src_dir: &Path, output_zip: &Path) -> io::Result<()> {
    let file = fs::File::create(output_zip)?;
    let mut zip = zip::ZipWriter::new(file);
    let options = SimpleFileOptions::default().compression_method(zip::CompressionMethod::Deflated).unix_permissions(0o755);
    for entry in WalkDir::new(src_dir) {
        let entry = entry.map_err(|e| io_err(&e.to_string()))?;
        let path = entry.path();
        let name = path.strip_prefix(src_dir).map_err(|e| io_err(&e.to_string()))?;
        if name.as_os_str().is_empty() || name.starts_with("tools") || name.starts_with(".git") { continue; }
        if path.is_file() {
            zip.start_file(name.to_string_lossy(), options)?;
            let mut f = fs::File::open(path)?;
            let mut buf = Vec::new();
            f.read_to_end(&mut buf)?;
            zip.write_all(&buf)?;
        } else { zip.add_directory(name.to_string_lossy(), options)?; }
    }
    zip.finish().map_err(|e| io_err(&e.to_string()))?;
    Ok(())
}

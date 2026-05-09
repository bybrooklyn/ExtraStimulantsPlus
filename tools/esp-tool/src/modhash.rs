use std::collections::BTreeMap;
use std::fs;
use std::io::{self, Read, Write};
use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};
use serde_json::Value;
use sha2::{Digest, Sha256};
use walkdir::{DirEntry, WalkDir};

use crate::error::io_err;
use crate::loadplan::{read_mod_json_from_zip, ModJson};
use crate::pck::GodotPck;

pub const MOD_HASH_INDEX_FILE: &str = "modloader/mod_hashes.json";

const HASH_IGNORE_FILES: &[&str] = &[".ds_store", "thumbs.db", "desktop.ini"];

#[derive(Serialize, Deserialize, Default)]
pub struct ModHashIndex {
    #[serde(default)]
    pub schema_version: u32,
    #[serde(default)]
    pub generated_by: String,
    #[serde(default)]
    pub entries: BTreeMap<String, ModHashEntry>,
}

#[derive(Serialize, Deserialize, Clone)]
pub struct ModHashEntry {
    pub id: String,
    pub name: String,
    pub version: String,
    pub path: String,
    pub file_name: String,
    pub kind: String,
    pub sha256: String,
    pub installed_at: String,
}

pub fn record_installed_mod(game_dir: &Path, installed_path: &Path) -> io::Result<ModHashEntry> {
    let meta = read_installed_metadata(installed_path)?;
    let kind = if installed_path.is_dir() {
        "folder"
    } else {
        "pack"
    };
    let file_name = installed_path
        .file_name()
        .and_then(|s| s.to_str())
        .ok_or_else(|| io_err("Installed mod path has no valid file name"))?
        .to_string();
    let sha256 = hash_installed_mod(installed_path)?;
    let entry = ModHashEntry {
        id: meta.id,
        name: meta.name,
        version: meta.version,
        path: installed_path.to_string_lossy().into_owned(),
        file_name,
        kind: kind.into(),
        sha256,
        installed_at: chrono::Utc::now().to_rfc3339(),
    };

    let mut index = load_index(game_dir);
    index.schema_version = 1;
    index.generated_by = "esp-tool".into();
    let key = hash_index_key(&entry.id, &entry.version, &entry.kind, &entry.file_name)?;
    index.entries.insert(key, entry.clone());
    save_index(game_dir, &index)?;
    Ok(entry)
}

/// Builds a structured (JSON-encoded tuple) key so a malicious mod with
/// `id: "foo|evil"` can't produce an index key that collides with another
/// mod's `id: "foo"` + `version: "evil|..."`. JSON encodes the separators
/// unambiguously and rejects non-UTF-8.
pub fn hash_index_key(id: &str, version: &str, kind: &str, file_name: &str) -> io::Result<String> {
    for (label, value) in [
        ("id", id),
        ("version", version),
        ("kind", kind),
        ("file_name", file_name),
    ] {
        if value.contains(|c: char| c.is_control()) {
            return Err(io_err(&format!(
                "mod hash key component '{}' contains control characters",
                label
            )));
        }
    }
    serde_json::to_string(&(id.trim(), version.trim(), kind.trim(), file_name.trim()))
        .map_err(|e| io_err(&format!("mod hash key serialize failed: {}", e)))
}

pub fn hash_installed_mod(path: &Path) -> io::Result<String> {
    if path.is_file() {
        return hash_file(path);
    }
    if path.is_dir() {
        return hash_folder(path);
    }
    Err(io_err(&format!(
        "Installed mod path does not exist: {}",
        path.display()
    )))
}

fn load_index(game_dir: &Path) -> ModHashIndex {
    let path = index_path(game_dir);
    let mut index = fs::read_to_string(&path)
        .ok()
        .and_then(|s| serde_json::from_str::<ModHashIndex>(&s).ok())
        .unwrap_or_default();
    if index.schema_version == 0 {
        index.schema_version = 1;
    }
    if index.generated_by.is_empty() {
        index.generated_by = "esp-tool".into();
    }
    index
}

fn save_index(game_dir: &Path, index: &ModHashIndex) -> io::Result<()> {
    let path = index_path(game_dir);
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)?;
    }
    let body = serde_json::to_string_pretty(index)
        .map_err(|e| io_err(&format!("mod hash index serialize failed: {}", e)))?;
    let mut file = fs::File::create(&path)?;
    file.write_all(body.as_bytes())?;
    file.sync_all()
}

fn index_path(game_dir: &Path) -> PathBuf {
    game_dir.join(MOD_HASH_INDEX_FILE)
}

fn read_installed_metadata(path: &Path) -> io::Result<ModJson> {
    if path.is_dir() {
        let body = fs::read_to_string(path.join("mod.json"))?;
        return serde_json::from_str(&body)
            .map_err(|e| io_err(&format!("mod.json parse failed: {}", e)));
    }

    let ext = path
        .extension()
        .and_then(|s| s.to_str())
        .map(|s| s.to_ascii_lowercase())
        .unwrap_or_default();
    if ext == "pck" {
        return read_mod_json_from_pck(path);
    }

    read_mod_json_from_zip(path)
        .ok_or_else(|| io_err("Installed mod package does not contain a readable mod.json"))
}

fn read_mod_json_from_pck(path: &Path) -> io::Result<ModJson> {
    let pck = GodotPck::load(path)?;
    if let Some(file) = pck.files.get("res://mod.json") {
        return serde_json::from_slice(&file.data)
            .map_err(|e| io_err(&format!("PCK mod.json parse failed: {}", e)));
    }
    for (name, file) in &pck.files {
        if name.ends_with("/mod.json") {
            return serde_json::from_slice(&file.data)
                .map_err(|e| io_err(&format!("PCK mod.json parse failed: {}", e)));
        }
    }
    Err(io_err("Installed PCK mod does not contain mod.json"))
}

fn hash_file(path: &Path) -> io::Result<String> {
    let mut file = fs::File::open(path)?;
    let mut hasher = Sha256::new();
    let mut buf = [0u8; 64 * 1024];
    loop {
        let read = file.read(&mut buf)?;
        if read == 0 {
            break;
        }
        hasher.update(&buf[..read]);
    }
    Ok(hex_lower(&hasher.finalize()))
}

fn hash_folder(root: &Path) -> io::Result<String> {
    let mut files = Vec::new();
    for entry in WalkDir::new(root)
        .follow_links(false)
        .into_iter()
        .filter_entry(should_descend)
    {
        let entry = entry.map_err(|e| io_err(&e.to_string()))?;
        let path = entry.path();
        if entry.file_type().is_symlink() || !entry.file_type().is_file() {
            continue;
        }
        let rel = relative_hash_path(root, path)?;
        if should_ignore_hash_path(&rel, false) {
            continue;
        }
        files.push((rel, path.to_path_buf()));
    }
    files.sort_by(|a, b| a.0.cmp(&b.0));

    let mut hasher = Sha256::new();
    let manifest_path = root.join("mod.json");
    for (rel, path) in files {
        let bytes = if path == manifest_path {
            canonical_manifest_bytes(&path)?
        } else {
            fs::read(&path)?
        };
        hash_update_string(&mut hasher, &rel);
        hash_update_string(&mut hasher, &bytes.len().to_string());
        hasher.update(bytes);
    }
    Ok(hex_lower(&hasher.finalize()))
}

fn should_descend(entry: &DirEntry) -> bool {
    let name = entry.file_name().to_string_lossy();
    if name.starts_with('.') && entry.depth() > 0 {
        return false;
    }
    let rel = entry.path().to_string_lossy().replace('\\', "/");
    !should_ignore_hash_path(&rel, entry.file_type().is_dir())
}

fn should_ignore_hash_path(rel_path: &str, is_dir: bool) -> bool {
    let clean = rel_path.replace('\\', "/").trim().to_ascii_lowercase();
    if clean.is_empty() || clean.starts_with("__macosx/") || clean == "__macosx" {
        return true;
    }
    let file_name = clean.rsplit('/').next().unwrap_or("");
    if HASH_IGNORE_FILES.contains(&file_name) {
        return true;
    }
    is_dir && clean.starts_with('.')
}

fn relative_hash_path(root: &Path, path: &Path) -> io::Result<String> {
    let rel = path
        .strip_prefix(root)
        .map_err(|e| io_err(&format!("hash path escaped root: {}", e)))?;
    let mut parts = Vec::new();
    for component in rel.components() {
        parts.push(component.as_os_str().to_string_lossy().into_owned());
    }
    Ok(parts.join("/"))
}

fn canonical_manifest_bytes(path: &Path) -> io::Result<Vec<u8>> {
    let body = fs::read_to_string(path)?;
    let mut value: Value = serde_json::from_str(&body)
        .map_err(|e| io_err(&format!("mod.json parse failed for hash: {}", e)))?;
    if let Value::Object(ref mut obj) = value {
        obj.remove("_metadata_path");
        obj.remove("package_sha256");
        obj.remove("content_sha256");
        obj.remove("sha256");
    }
    Ok(canonical_json(&value).into_bytes())
}

fn canonical_json(value: &Value) -> String {
    match value {
        Value::Null => "null".into(),
        Value::Bool(v) => {
            if *v {
                "true".into()
            } else {
                "false".into()
            }
        }
        Value::Number(v) => v.to_string(),
        Value::String(v) => serde_json::to_string(v).unwrap_or_else(|_| "\"\"".into()),
        Value::Array(items) => {
            let parts: Vec<String> = items.iter().map(canonical_json).collect();
            format!("[{}]", parts.join(","))
        }
        Value::Object(map) => {
            let mut keys: Vec<&String> = map.keys().collect();
            keys.sort();
            let parts: Vec<String> = keys
                .into_iter()
                .map(|key| {
                    let value = map.get(key).unwrap_or(&Value::Null);
                    format!(
                        "{}:{}",
                        serde_json::to_string(key).unwrap_or_else(|_| "\"\"".into()),
                        canonical_json(value)
                    )
                })
                .collect();
            format!("{{{}}}", parts.join(","))
        }
    }
}

fn hash_update_string(hasher: &mut Sha256, value: &str) {
    hasher.update(value.as_bytes());
    hasher.update([0]);
}

fn hex_lower(bytes: &[u8]) -> String {
    bytes.iter().map(|b| format!("{:02x}", b)).collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::{SystemTime, UNIX_EPOCH};
    use zip::write::SimpleFileOptions;

    fn temp_dir(name: &str) -> PathBuf {
        let nonce = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let path = std::env::temp_dir().join(format!(
            "esp-modhash-{}-{}-{}",
            std::process::id(),
            nonce,
            name
        ));
        fs::create_dir_all(&path).unwrap();
        path
    }

    #[test]
    fn records_installed_zip_hash_index_entry() {
        let game_dir = temp_dir("game");
        let mods_dir = game_dir.join("mods");
        fs::create_dir_all(&mods_dir).unwrap();
        let mod_path = mods_dir.join("example.zip");
        {
            let file = fs::File::create(&mod_path).unwrap();
            let mut zip = zip::ZipWriter::new(file);
            let options = SimpleFileOptions::default();
            zip.start_file("mod.json", options).unwrap();
            zip.write_all(br#"{"id":"example","name":"Example","version":"1.2.3"}"#)
                .unwrap();
            zip.finish().unwrap();
        }

        let entry = record_installed_mod(&game_dir, &mod_path).unwrap();
        assert_eq!(entry.id, "example");
        assert_eq!(entry.kind, "pack");
        assert_eq!(entry.sha256, hash_installed_mod(&mod_path).unwrap());

        let index_body = fs::read_to_string(game_dir.join(MOD_HASH_INDEX_FILE)).unwrap();
        let index: ModHashIndex = serde_json::from_str(&index_body).unwrap();
        let key = hash_index_key("example", "1.2.3", "pack", "example.zip").unwrap();
        assert!(index.entries.contains_key(&key));

        let _ = fs::remove_dir_all(game_dir);
    }
}

use std::env;
use std::fs;
use std::path::PathBuf;

pub struct SteamScanner {
    base_paths: Vec<PathBuf>,
}

impl SteamScanner {
    pub fn new() -> Self {
        let mut base_paths = Vec::new();
        if cfg!(windows) {
            #[cfg(windows)]
            {
                use winreg::enums::*;
                use winreg::RegKey;
                if let Ok(steam) =
                    RegKey::predef(HKEY_CURRENT_USER).open_subkey("Software\\Valve\\Steam")
                {
                    if let Ok(path) = steam.get_value::<String, _>("SteamPath") {
                        base_paths.push(PathBuf::from(path));
                    }
                }
            }
        } else if cfg!(target_os = "macos") {
            // Sensory Overload has no native macOS build. We intentionally do
            // not search Whisky/CrossOver bottles — esp-tool on Mac is for
            // mod authoring (`esp pack`, `esp create`) only. install/launch
            // surface a clear error in their respective code paths.
        } else {
            if let Ok(home) = env::var("HOME") {
                base_paths.push(PathBuf::from(format!("{}/.local/share/Steam", home)));
                base_paths.push(PathBuf::from(format!("{}/.steam/steam", home)));
                base_paths.push(PathBuf::from(format!("{}/.steam/root", home)));
            }
            base_paths.push(PathBuf::from("/usr/share/Steam"));
            if let Ok(entries) = fs::read_dir("/run/media/") {
                for entry in entries.flatten() {
                    base_paths.push(entry.path());
                }
            }
        }
        Self { base_paths }
    }

    pub fn find_game_pck(&self) -> Option<PathBuf> {
        for base in &self.base_paths {
            let lib_file = base.join("config/libraryfolders.vdf");
            if let Ok(content) = fs::read_to_string(&lib_file) {
                for library_path in vdf_library_paths(&content) {
                    let pck =
                        library_path.join("steamapps/common/Sensory Overload/SensoryOverload.pck");
                    if pck.exists() {
                        return Some(pck);
                    }
                }
            }
        }
        None
    }

    /// Searches every Steam library this scanner knows about for an
    /// appmanifest_*.acf whose `installdir` matches "Sensory Overload" and
    /// returns the appid as a string. Used on Linux to launch the game
    /// through Steam (Proton-wrapped) when no native binary exists.
    pub fn find_game_appid(&self) -> Option<String> {
        for base in &self.base_paths {
            let lib_file = base.join("config/libraryfolders.vdf");
            let Ok(content) = fs::read_to_string(&lib_file) else {
                continue;
            };
            for library_path in vdf_library_paths(&content) {
                let steamapps = library_path.join("steamapps");
                let Ok(entries) = fs::read_dir(&steamapps) else {
                    continue;
                };
                for entry in entries.flatten() {
                    let path = entry.path();
                    let name = path.file_name().and_then(|s| s.to_str()).unwrap_or("");
                    if !name.starts_with("appmanifest_") || !name.ends_with(".acf") {
                        continue;
                    }
                    let Ok(body) = fs::read_to_string(&path) else {
                        continue;
                    };
                    if let Some(appid) = appid_from_manifest(&body, "Sensory Overload") {
                        return Some(appid);
                    }
                }
            }
        }
        None
    }
}

/// Parses a Steam appmanifest_*.acf (VDF format) and returns the appid string
/// if the manifest's installdir matches `target_installdir` case-insensitively.
fn appid_from_manifest(content: &str, target_installdir: &str) -> Option<String> {
    let tokens = vdf_tokens(content);
    let mut appid: Option<String> = None;
    let mut installdir: Option<String> = None;
    let mut i = 0;
    while i + 1 < tokens.len() {
        match tokens[i].as_str() {
            "appid" => appid = Some(tokens[i + 1].clone()),
            "installdir" => installdir = Some(tokens[i + 1].clone()),
            _ => {}
        }
        i += 1;
    }
    if let (Some(id), Some(dir)) = (appid, installdir) {
        if dir.eq_ignore_ascii_case(target_installdir) {
            return Some(id);
        }
    }
    None
}

// Tokenizes a Steam VDF document into the sequence of quoted-string values.
// Used by both `vdf_library_paths` (libraryfolders.vdf) and
// `appid_from_manifest` (appmanifest_*.acf). Not a full parser — just a flat
// stream of `"value"` tokens, ignoring braces and whitespace.
fn vdf_tokens(content: &str) -> Vec<String> {
    let mut tokens: Vec<String> = Vec::new();
    let bytes = content.as_bytes();
    let mut i = 0;
    while i < bytes.len() {
        if bytes[i] == b'"' {
            i += 1;
            let mut buf = String::new();
            while i < bytes.len() && bytes[i] != b'"' {
                if bytes[i] == b'\\' && i + 1 < bytes.len() {
                    let next = bytes[i + 1];
                    match next {
                        b'\\' => buf.push('\\'),
                        b'n' => buf.push('\n'),
                        b't' => buf.push('\t'),
                        b'"' => buf.push('"'),
                        _ => {
                            // Unknown escape: preserve the literal backslash so
                            // typos don't silently mangle paths.
                            buf.push('\\');
                            buf.push(next as char);
                        }
                    }
                    i += 2;
                } else {
                    buf.push(bytes[i] as char);
                    i += 1;
                }
            }
            tokens.push(buf);
            i += 1; // consume closing quote
        } else {
            i += 1;
        }
    }
    tokens
}

// Extract every "path" value from a Steam libraryfolders.vdf — whenever a
// token "path" is followed by another quoted string, that string is a library
// root.
fn vdf_library_paths(content: &str) -> Vec<PathBuf> {
    let tokens = vdf_tokens(content);
    let mut out = Vec::new();
    let mut j = 0;
    while j + 1 < tokens.len() {
        if tokens[j] == "path" {
            out.push(PathBuf::from(&tokens[j + 1]));
            j += 2;
        } else {
            j += 1;
        }
    }
    out
}

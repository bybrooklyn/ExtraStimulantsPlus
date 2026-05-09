use std::env;
use std::fs;
use std::io;
use std::path::PathBuf;

use serde::{Deserialize, Serialize};

use crate::error::io_err;

const LEGACY_CONFIG_FILE: &str = ".esp-config.json";
const CONFIG_DIR_NAME: &str = "esp";
const CONFIG_FILE_NAME: &str = "config.json";

#[derive(Serialize, Deserialize, Default, Clone)]
pub struct Config {
    pub game_path: Option<PathBuf>,
    pub pck_path: Option<PathBuf>,
}

impl Config {
    pub fn config_path() -> PathBuf {
        let base = dirs::config_dir()
            .unwrap_or_else(|| env::current_dir().unwrap_or_else(|_| PathBuf::from(".")));
        base.join(CONFIG_DIR_NAME).join(CONFIG_FILE_NAME)
    }

    pub fn load() -> Self {
        let path = Self::config_path();
        // One-time migration: if a legacy CWD config exists and the new location doesn't, move it.
        let legacy = PathBuf::from(LEGACY_CONFIG_FILE);
        if !path.exists() && legacy.exists() {
            if let Some(parent) = path.parent() {
                let _ = fs::create_dir_all(parent);
            }
            let _ = fs::rename(&legacy, &path);
        }
        fs::read_to_string(&path)
            .ok()
            .and_then(|s| serde_json::from_str(&s).ok())
            .unwrap_or_default()
    }

    pub fn save(&self) -> io::Result<()> {
        let path = Self::config_path();
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent)?;
        }
        let data = serde_json::to_string_pretty(self)
            .map_err(|e| io_err(&format!("config serialize failed: {}", e)))?;
        fs::write(&path, data)?;
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            let _ = fs::set_permissions(&path, fs::Permissions::from_mode(0o600));
        }
        Ok(())
    }
}

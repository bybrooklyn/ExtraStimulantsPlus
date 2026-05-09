use std::env;
use std::fs;
use std::io::{Read, Seek, SeekFrom};
use std::path::PathBuf;
use std::time::{Duration, SystemTime};

// Resolves the platform-standard Godot log path for "Sensory Overload":
//   Linux:   ~/.local/share/godot/app_userdata/Sensory Overload/logs/godot.log
//   macOS:   ~/Library/Application Support/Godot/app_userdata/Sensory Overload/logs/godot.log
//   Windows: %APPDATA%/Godot/app_userdata/Sensory Overload/logs/godot.log
//
// Returns None if the home/appdata directory can't be determined.
pub fn resolve_log_path() -> Option<PathBuf> {
    let base: PathBuf = if cfg!(target_os = "macos") {
        let home = env::var("HOME").ok()?;
        PathBuf::from(home).join("Library/Application Support")
    } else if cfg!(windows) {
        // %APPDATA% (Roaming) is what Godot uses on Windows.
        let appdata = env::var("APPDATA").ok()?;
        PathBuf::from(appdata)
    } else {
        // Linux + the Steam Deck.
        let home = env::var("HOME").ok()?;
        PathBuf::from(home).join(".local/share")
    };
    Some(base.join("Godot/app_userdata/Sensory Overload/logs/godot.log"))
}

pub struct LogTailer {
    pub path: PathBuf,
    last_offset: u64,
    last_modified: Option<SystemTime>,
    next_poll_after: SystemTime,
    pub backoff: bool,
}

impl LogTailer {
    pub fn new(path: PathBuf) -> Self {
        Self {
            path,
            last_offset: 0,
            last_modified: None,
            next_poll_after: SystemTime::now(),
            backoff: false,
        }
    }

    // Restart from the current end-of-file (used when the game starts fresh).
    pub fn rewind_to_end(&mut self) {
        if let Ok(meta) = fs::metadata(&self.path) {
            self.last_offset = meta.len();
        }
    }

    // Returns new lines since the last call, plus a "is_active" hint for the
    // GUI to decide between a fast and slow poll cadence. Throttles itself: if
    // the file's mtime hasn't changed for >10s, the next call no-ops until
    // ~2s have passed (vs the GUI's ~500ms tick).
    pub fn poll(&mut self) -> Vec<String> {
        let now = SystemTime::now();
        if now < self.next_poll_after {
            return Vec::new();
        }

        let meta = match fs::metadata(&self.path) {
            Ok(m) => m,
            Err(_) => {
                self.backoff = true;
                self.next_poll_after = now + Duration::from_secs(2);
                return Vec::new();
            }
        };

        let modified = meta.modified().ok();
        let stale = match (modified, self.last_modified) {
            (Some(now_m), Some(prev_m)) => {
                now_m == prev_m
                    && now
                        .duration_since(prev_m)
                        .map(|d| d > Duration::from_secs(10))
                        .unwrap_or(false)
            }
            _ => false,
        };
        self.backoff = stale;
        self.next_poll_after = now
            + if stale {
                Duration::from_secs(2)
            } else {
                Duration::from_millis(500)
            };

        let len = meta.len();
        if len < self.last_offset {
            // File rotated/truncated. Restart from the new beginning.
            self.last_offset = 0;
        }
        if len == self.last_offset {
            self.last_modified = modified;
            return Vec::new();
        }

        let mut file = match fs::File::open(&self.path) {
            Ok(f) => f,
            Err(_) => return Vec::new(),
        };
        if file.seek(SeekFrom::Start(self.last_offset)).is_err() {
            return Vec::new();
        }
        let mut buf = String::new();
        let read = file.read_to_string(&mut buf).unwrap_or(0);
        self.last_offset += read as u64;
        self.last_modified = modified;

        buf.lines().map(|s| s.to_string()).collect()
    }
}

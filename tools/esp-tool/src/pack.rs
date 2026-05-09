use std::fs;
use std::io::{self, Read, Write};
use std::path::{Component, Path};

use walkdir::WalkDir;
use zip::write::SimpleFileOptions;

use crate::error::io_err;

pub fn pack_core(src_dir: &Path, output_zip: &Path) -> io::Result<()> {
    let file = fs::File::create(output_zip)?;
    let mut zip = zip::ZipWriter::new(file);
    let options = SimpleFileOptions::default()
        .compression_method(zip::CompressionMethod::Deflated)
        .unix_permissions(0o755);
    for entry in WalkDir::new(src_dir) {
        let entry = entry.map_err(|e| io_err(&e.to_string()))?;
        let path = entry.path();
        let name = path
            .strip_prefix(src_dir)
            .map_err(|e| io_err(&e.to_string()))?;
        if name.as_os_str().is_empty() || name.starts_with("tools") || name.starts_with(".git") {
            continue;
        }
        if entry.file_type().is_symlink() {
            continue;
        }
        let archive_name = archive_name(name)?;
        if path.is_file() {
            zip.start_file(&archive_name, options)?;
            let mut f = fs::File::open(path)?;
            let mut buf = Vec::new();
            f.read_to_end(&mut buf)?;
            zip.write_all(&buf)?;
        } else if path.is_dir() {
            zip.add_directory(&archive_name, options)?;
        }
    }
    zip.finish().map_err(|e| io_err(&e.to_string()))?;
    Ok(())
}

fn archive_name(path: &Path) -> io::Result<String> {
    let mut parts = Vec::new();
    for component in path.components() {
        match component {
            Component::Normal(part) => {
                let part = part
                    .to_str()
                    .ok_or_else(|| io_err("Archive entry path is not valid UTF-8"))?;
                if part.contains('\\') {
                    return Err(io_err("Archive entry path contains a backslash"));
                }
                parts.push(part.to_string());
            }
            Component::CurDir => {}
            Component::ParentDir | Component::RootDir | Component::Prefix(_) => {
                return Err(io_err("Archive entry path escapes the source directory"));
            }
        }
    }
    if parts.is_empty() {
        return Err(io_err("Archive entry path is empty"));
    }
    Ok(parts.join("/"))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn archive_name_uses_forward_slashes() {
        assert_eq!(
            archive_name(Path::new("mods/example/main.gd")).unwrap(),
            "mods/example/main.gd"
        );
    }

    #[test]
    fn archive_name_rejects_parent_traversal() {
        assert!(archive_name(Path::new("../outside.gd")).is_err());
    }

    #[test]
    fn archive_name_rejects_absolute_paths() {
        assert!(archive_name(Path::new("/tmp/outside.gd")).is_err());
    }
}

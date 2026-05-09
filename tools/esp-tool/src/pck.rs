use std::collections::BTreeMap;
use std::fs;
use std::io::{self, Seek, Write};
use std::path::{Path, PathBuf};

use crate::error::io_err;

const MAX_PCK_FILES: usize = 100_000;
const MAX_PCK_PATH_LEN: usize = 4096;

#[derive(Debug)]
pub struct GodotPck {
    pub version: u32,
    pub major: u32,
    pub minor: u32,
    pub patch: u32,
    pub files: BTreeMap<String, PckFile>,
}

#[derive(Clone, Debug)]
pub struct PckFile {
    pub size: u64,
    pub md5: [u8; 16],
    pub flags: u32,
    pub data: Vec<u8>,
}

impl GodotPck {
    pub fn load(path: &Path) -> io::Result<Self> {
        let blob = fs::read(path)?;
        let mut cursor = PckCursor {
            data: &blob,
            pos: 0,
        };
        if cursor.read_exact(4)? != b"GDPC" {
            return Err(io_err("Invalid PCK"));
        }
        let version = cursor.u32()?;
        let major = cursor.u32()?;
        let minor = cursor.u32()?;
        let patch = cursor.u32()?;
        cursor.skip(64)?;
        let count = usize::try_from(cursor.u32()?)
            .map_err(|_| io_err("PCK file count does not fit this platform"))?;
        if count > MAX_PCK_FILES {
            return Err(io_err(&format!(
                "PCK file count {} exceeds limit {}",
                count, MAX_PCK_FILES
            )));
        }
        let mut files = BTreeMap::new();
        for _ in 0..count {
            let path_len = usize::try_from(cursor.u32()?)
                .map_err(|_| io_err("PCK path length does not fit this platform"))?;
            if path_len > MAX_PCK_PATH_LEN {
                return Err(io_err(&format!(
                    "PCK path length {} exceeds limit {}",
                    path_len, MAX_PCK_PATH_LEN
                )));
            }
            let raw = cursor.read_exact(path_len)?;
            // Strip Godot's zero padding before validating UTF-8. PCK paths are
            // UTF-8 by spec; surface invalid sequences instead of silently
            // mangling them with from_utf8_lossy.
            let trimmed: Vec<u8> = raw.iter().copied().filter(|b| *b != 0).collect();
            let file_path = String::from_utf8(trimmed)
                .map_err(|e| io_err(&format!("PCK contains non-UTF-8 path entry: {}", e)))?;
            let offset = usize::try_from(cursor.u64()?)
                .map_err(|_| io_err("PCK file offset does not fit this platform"))?;
            let size = usize::try_from(cursor.u64()?)
                .map_err(|_| io_err("PCK file size does not fit this platform"))?;
            let md5 = cursor.md5()?;
            let flags = if version >= 2 { cursor.u32()? } else { 0 };
            let end = offset
                .checked_add(size)
                .ok_or_else(|| io_err("PCK file offset + size overflow"))?;
            if end > blob.len() {
                return Err(io_err(&format!(
                    "PCK file '{}' points outside archive: offset {}, size {}, archive {}",
                    file_path,
                    offset,
                    size,
                    blob.len()
                )));
            }
            files.insert(
                file_path,
                PckFile {
                    size: size as u64,
                    md5,
                    flags,
                    data: blob[offset..end].to_vec(),
                },
            );
        }
        Ok(Self {
            version,
            major,
            minor,
            patch,
            files,
        })
    }

    pub fn add_file(&mut self, path: &str, data: Vec<u8>, flags: u32) {
        let norm = normalize(path);
        self.files.insert(
            norm,
            PckFile {
                size: data.len() as u64,
                md5: md5_bytes(&data),
                flags,
                data,
            },
        );
    }

    pub fn remove_file(&mut self, path: &str) -> bool {
        self.files.remove(&normalize(path)).is_some()
    }

    pub fn has_file(&self, path: &str) -> bool {
        self.files.contains_key(&normalize(path))
    }

    pub fn save(&self, path: &Path) -> io::Result<()> {
        let mut index_size = 88usize;
        for fp in self.files.keys() {
            index_size += 4 + fp.as_bytes().len() + 8 + 8 + 16 + 4;
        }
        let mut offsets = BTreeMap::new();
        let mut cur = align32(index_size as u64);
        for (fp, file) in &self.files {
            offsets.insert(fp.clone(), cur);
            cur = align32(cur + file.size);
        }
        let tmp = PathBuf::from(format!("{}.tmp", path.display()));
        let mut out = fs::File::create(&tmp)?;
        out.write_all(b"GDPC")?;
        write_u32(&mut out, self.version)?;
        write_u32(&mut out, self.major)?;
        write_u32(&mut out, self.minor)?;
        write_u32(&mut out, self.patch)?;
        out.write_all(&[0u8; 64])?;
        write_u32(&mut out, self.files.len() as u32)?;
        for (fp, file) in &self.files {
            let p = fp.as_bytes();
            write_u32(&mut out, p.len() as u32)?;
            out.write_all(p)?;
            write_u64(&mut out, offsets[fp])?;
            write_u64(&mut out, file.size)?;
            out.write_all(&file.md5)?;
            write_u32(&mut out, file.flags)?;
        }
        for (fp, file) in &self.files {
            pad_to(&mut out, offsets[fp])?;
            out.write_all(&file.data)?;
        }
        out.flush()?;
        fs::rename(tmp, path)?;
        Ok(())
    }
}

fn normalize(path: &str) -> String {
    if path.starts_with("res://") {
        path.to_string()
    } else {
        format!("res://{}", path.trim_start_matches('/'))
    }
}

struct PckCursor<'a> {
    data: &'a [u8],
    pos: usize,
}
impl<'a> PckCursor<'a> {
    fn read_exact(&mut self, n: usize) -> io::Result<&'a [u8]> {
        let end = self
            .pos
            .checked_add(n)
            .ok_or_else(|| io_err("PCK cursor overflow"))?;
        if end > self.data.len() {
            return Err(io_err("EOF"));
        }
        let slice = &self.data[self.pos..end];
        self.pos = end;
        Ok(slice)
    }
    fn skip(&mut self, n: usize) -> io::Result<()> {
        self.read_exact(n).map(|_| ())
    }
    fn u32(&mut self) -> io::Result<u32> {
        let b = self.read_exact(4)?;
        Ok(u32::from_le_bytes([b[0], b[1], b[2], b[3]]))
    }
    fn u64(&mut self) -> io::Result<u64> {
        let b = self.read_exact(8)?;
        Ok(u64::from_le_bytes([
            b[0], b[1], b[2], b[3], b[4], b[5], b[6], b[7],
        ]))
    }
    fn md5(&mut self) -> io::Result<[u8; 16]> {
        let b = self.read_exact(16)?;
        let mut out = [0u8; 16];
        out.copy_from_slice(b);
        Ok(out)
    }
}

fn write_u32<W: Write>(w: &mut W, n: u32) -> io::Result<()> {
    w.write_all(&n.to_le_bytes())
}
fn write_u64<W: Write>(w: &mut W, n: u64) -> io::Result<()> {
    w.write_all(&n.to_le_bytes())
}
fn align32(n: u64) -> u64 {
    (n + 31) & !31
}
fn pad_to<W: Write + Seek>(w: &mut W, offset: u64) -> io::Result<()> {
    let current = w.stream_position()?;
    if current < offset {
        w.write_all(&vec![0u8; (offset - current) as usize])?;
    }
    Ok(())
}

fn md5_bytes(input: &[u8]) -> [u8; 16] {
    md5::compute(input).0
}

pub fn merge_override_cfg(existing: Option<&[u8]>, _shim: &str) -> String {
    let line = r#"ESPShim="*res://esp_shim/ESPShim.gd""#;
    let mut text = existing
        .map(|b| String::from_utf8_lossy(b).to_string())
        .unwrap_or_default();
    if text.contains("ESPShim") {
        return text;
    }
    if let Some(start) = text.find("[autoload]") {
        let pos = text[start..]
            .find('\n')
            .map(|n| start + n + 1)
            .unwrap_or(text.len());
        text.insert_str(pos, &format!("{line}\n"));
    } else {
        text.push_str(&format!("\n\n[autoload]\n\n{line}\n"));
    }
    text
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::time::{SystemTime, UNIX_EPOCH};

    fn load_blob(blob: Vec<u8>, name: &str) -> io::Result<GodotPck> {
        let nonce = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_nanos();
        let path = std::env::temp_dir().join(format!(
            "esp-pck-{}-{}-{}.pck",
            std::process::id(),
            nonce,
            name
        ));
        fs::write(&path, blob).unwrap();
        let result = GodotPck::load(&path);
        let _ = fs::remove_file(&path);
        result
    }

    fn header(count: u32) -> Vec<u8> {
        let mut blob = Vec::new();
        blob.extend_from_slice(b"GDPC");
        blob.extend_from_slice(&2u32.to_le_bytes());
        blob.extend_from_slice(&4u32.to_le_bytes());
        blob.extend_from_slice(&3u32.to_le_bytes());
        blob.extend_from_slice(&0u32.to_le_bytes());
        blob.extend_from_slice(&[0u8; 64]);
        blob.extend_from_slice(&count.to_le_bytes());
        blob
    }

    fn add_entry(blob: &mut Vec<u8>, path: &str, offset: u64, size: u64) {
        blob.extend_from_slice(&(path.len() as u32).to_le_bytes());
        blob.extend_from_slice(path.as_bytes());
        blob.extend_from_slice(&offset.to_le_bytes());
        blob.extend_from_slice(&size.to_le_bytes());
        blob.extend_from_slice(&[0u8; 16]);
        blob.extend_from_slice(&0u32.to_le_bytes());
    }

    #[test]
    fn rejects_huge_file_count() {
        let err = load_blob(header((MAX_PCK_FILES as u32) + 1), "huge-count").unwrap_err();
        assert!(err.to_string().contains("file count"));
    }

    #[test]
    fn rejects_huge_path_length_before_allocation() {
        let mut blob = header(1);
        blob.extend_from_slice(&((MAX_PCK_PATH_LEN as u32) + 1).to_le_bytes());
        let err = load_blob(blob, "huge-path").unwrap_err();
        assert!(err.to_string().contains("path length"));
    }

    #[test]
    fn rejects_file_slice_outside_archive() {
        let mut blob = header(1);
        add_entry(&mut blob, "res://bad.gd", 999_999, 10);
        let err = load_blob(blob, "outside").unwrap_err();
        assert!(err.to_string().contains("outside archive"));
    }

    #[test]
    fn rejects_offset_size_overflow() {
        let mut blob = header(1);
        add_entry(&mut blob, "res://bad.gd", u64::MAX, 1);
        let err = load_blob(blob, "overflow").unwrap_err();
        assert!(
            err.to_string().contains("offset + size overflow")
                || err.to_string().contains("does not fit this platform")
        );
    }
}

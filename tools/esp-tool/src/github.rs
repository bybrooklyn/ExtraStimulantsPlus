use std::io;
use std::time::Duration;

use serde::Deserialize;

use crate::error::io_err;

pub const REPO_OWNER: &str = "bybrooklyn";
pub const REPO_NAME: &str = "extrastimulantsplus";

const API_TIMEOUT_SECS: u64 = 20;

#[derive(Deserialize, Debug, Clone)]
pub struct Release {
    pub tag_name: String,
    #[serde(default)]
    pub assets: Vec<Asset>,
}

#[derive(Deserialize, Debug, Clone)]
pub struct Asset {
    pub name: String,
    pub browser_download_url: String,
}

fn user_agent() -> String {
    format!("esp-tool/{}", env!("CARGO_PKG_VERSION"))
}

/// Fetches the most recent non-prerelease release for the given repo.
/// Returns a typed io::Error on any failure path so callers don't need
/// to know about reqwest types.
pub fn fetch_latest_release(owner: &str, repo: &str) -> io::Result<Release> {
    let url = format!(
        "https://api.github.com/repos/{}/{}/releases/latest",
        owner, repo
    );
    let client = reqwest::blocking::Client::builder()
        .timeout(Duration::from_secs(API_TIMEOUT_SECS))
        .build()
        .map_err(|e| io_err(&format!("HTTP client init failed: {}", e)))?;

    let resp = client
        .get(&url)
        .header("User-Agent", user_agent())
        .header("Accept", "application/vnd.github+json")
        .send()
        .map_err(|e| io_err(&format!("GitHub releases API request failed: {}", e)))?;

    let status = resp.status();
    if status == reqwest::StatusCode::NOT_FOUND {
        return Err(io_err(&format!(
            "No releases published at github.com/{}/{}/releases yet",
            owner, repo
        )));
    }
    if !status.is_success() {
        let body = resp.text().unwrap_or_default();
        let snippet = body.chars().take(200).collect::<String>();
        return Err(io_err(&format!(
            "GitHub releases API returned {}: {}",
            status, snippet
        )));
    }

    resp.json::<Release>()
        .map_err(|e| io_err(&format!("GitHub releases API gave malformed JSON: {}", e)))
}

/// Case-insensitive exact-name match against a release's assets.
pub fn find_asset<'a>(release: &'a Release, name: &str) -> Option<&'a Asset> {
    let lower = name.to_ascii_lowercase();
    release
        .assets
        .iter()
        .find(|a| a.name.to_ascii_lowercase() == lower)
}

/// Downloads a small text asset (like a `.sha256` file) and returns its body.
pub fn fetch_text(url: &str) -> io::Result<String> {
    let client = reqwest::blocking::Client::builder()
        .timeout(Duration::from_secs(API_TIMEOUT_SECS))
        .build()
        .map_err(|e| io_err(&format!("HTTP client init failed: {}", e)))?;
    let resp = client
        .get(url)
        .header("User-Agent", user_agent())
        .send()
        .map_err(|e| io_err(&format!("Asset fetch failed ({}): {}", url, e)))?;
    if !resp.status().is_success() {
        return Err(io_err(&format!(
            "Asset fetch returned {} for {}",
            resp.status(),
            url
        )));
    }
    resp.text()
        .map_err(|e| io_err(&format!("Asset body read failed ({}): {}", url, e)))
}

/// A `*.sha256` file usually contains either a bare 64-char hex string or
/// `<hash>  <filename>` (sha256sum format). Strip whitespace and trailing
/// filename, lowercase the hex, validate length+chars.
pub fn parse_sha256_file(body: &str) -> io::Result<String> {
    let token = body
        .split_whitespace()
        .next()
        .ok_or_else(|| io_err("sha256 asset is empty"))?
        .to_ascii_lowercase();
    if token.len() != 64 || !token.chars().all(|c| c.is_ascii_hexdigit()) {
        return Err(io_err(&format!(
            "sha256 asset body did not contain a 64-char hex string (got {} chars)",
            token.len()
        )));
    }
    Ok(token)
}

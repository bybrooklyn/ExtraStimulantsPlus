use std::collections::HashMap;
use std::fs;
use std::io;
use std::path::{Path, PathBuf};

use dialoguer::{Input, MultiSelect, Select};

use crate::error::io_err;

// Templates — embedded at compile time via include_str!. Each template is a
// slice of (relative_path, content) pairs. Placeholder substitution: any
// occurrence of {{name}}, {{id}}, {{author}}, {{author_url}}, {{description}}
// in the file content is replaced with the user's input.
type TemplateFile = (&'static str, &'static str);
type Template = &'static [TemplateFile];

const T_MINIMAL: Template = &[
    (
        "mod.json",
        include_str!("scaffold/templates/minimal/mod.json"),
    ),
    (
        "main.gd",
        include_str!("scaffold/templates/minimal/main.gd"),
    ),
    (
        "README.md",
        include_str!("scaffold/templates/minimal/README.md"),
    ),
];

const T_EVENTS: Template = &[
    (
        "mod.json",
        include_str!("scaffold/templates/events/mod.json"),
    ),
    ("main.gd", include_str!("scaffold/templates/events/main.gd")),
    (
        "README.md",
        include_str!("scaffold/templates/events/README.md"),
    ),
];

const T_SETTINGS: Template = &[
    (
        "mod.json",
        include_str!("scaffold/templates/settings/mod.json"),
    ),
    (
        "main.gd",
        include_str!("scaffold/templates/settings/main.gd"),
    ),
    (
        "README.md",
        include_str!("scaffold/templates/settings/README.md"),
    ),
];

const T_FEATURE: Template = &[
    (
        "mod.json",
        include_str!("scaffold/templates/feature/mod.json"),
    ),
    (
        "main.gd",
        include_str!("scaffold/templates/feature/main.gd"),
    ),
    (
        "scripts/core/example_feature.gd",
        include_str!("scaffold/templates/feature/scripts/core/example_feature.gd"),
    ),
    (
        "README.md",
        include_str!("scaffold/templates/feature/README.md"),
    ),
];

const T_UI: Template = &[
    ("mod.json", include_str!("scaffold/templates/ui/mod.json")),
    ("main.gd", include_str!("scaffold/templates/ui/main.gd")),
    ("README.md", include_str!("scaffold/templates/ui/README.md")),
];

const T_CAMPAIGN: Template = &[
    (
        "mod.json",
        include_str!("scaffold/templates/campaign/mod.json"),
    ),
    (
        "main.gd",
        include_str!("scaffold/templates/campaign/main.gd"),
    ),
    (
        "levels/example.json",
        include_str!("scaffold/templates/campaign/levels/example.json"),
    ),
    (
        "README.md",
        include_str!("scaffold/templates/campaign/README.md"),
    ),
];

pub const TEMPLATE_NAMES: &[&str] = &["minimal", "events", "settings", "feature", "ui", "campaign"];

// Mirrors KNOWN_PERMISSIONS in scripts/core/mod_loader.gd:19. Used by the
// interactive prompt's MultiSelect.
pub const PERMISSIONS: &[&str] = &[
    "asset_access",
    "filesystem",
    "hot_reload",
    "internet",
    "patching",
    "raw_api",
    "save_access",
];

pub struct CreateOptions {
    pub id: String,
    pub name: String,
    pub author: String,
    pub author_url: String,
    pub description: String,
    pub repository: String,
    pub template: String,
    pub permissions: Vec<String>,
    pub output_dir: PathBuf,
    pub here: bool,
}

pub fn run(opts: CreateOptions) -> io::Result<()> {
    let template_files = lookup_template(&opts.template)?;

    let target_dir = if opts.here {
        std::env::current_dir()?
    } else {
        opts.output_dir.clone()
    };

    if !opts.here {
        if target_dir.exists() && fs::read_dir(&target_dir)?.next().is_some() {
            return Err(io_err(&format!(
                "output directory not empty: {}",
                target_dir.display()
            )));
        }
        fs::create_dir_all(&target_dir)?;
    }

    let mut placeholders: HashMap<&str, String> = HashMap::new();
    placeholders.insert("id", opts.id.clone());
    placeholders.insert("name", opts.name.clone());
    placeholders.insert("author", opts.author.clone());
    placeholders.insert("author_url", opts.author_url.clone());
    placeholders.insert("description", opts.description.clone());
    placeholders.insert("repository", opts.repository.clone());

    let mut wrote: Vec<PathBuf> = Vec::new();
    let mut skipped: Vec<PathBuf> = Vec::new();
    for (rel_path, content) in template_files {
        let dest = target_dir.join(rel_path);
        if dest.exists() {
            // --here mode: don't overwrite existing files. Same in fresh-dir
            // mode if the user pre-populated the dir somehow.
            skipped.push(dest);
            continue;
        }
        if let Some(parent) = dest.parent() {
            fs::create_dir_all(parent)?;
        }
        let mut body = substitute(content, &placeholders);
        if rel_path == &"mod.json" && !opts.permissions.is_empty() {
            body = inject_permissions(&body, &opts.permissions)?;
        }
        fs::write(&dest, body)?;
        wrote.push(dest);
    }

    validate_generated_mod(&target_dir)?;

    println!(
        ">> Created {} ({} template) at {}",
        opts.id,
        opts.template,
        target_dir.display()
    );
    for p in &wrote {
        println!("   wrote   {}", p.display());
    }
    for p in &skipped {
        println!("   skipped {} (already exists)", p.display());
    }
    Ok(())
}

pub fn run_interactive(
    initial_id: Option<String>,
    here: bool,
    template_hint: Option<String>,
) -> io::Result<()> {
    let id_default = initial_id.clone().unwrap_or_default();
    let id: String = Input::new()
        .with_prompt("Mod id (lowercase, [a-z][a-z0-9_]*)")
        .default(id_default.clone())
        .validate_with(|input: &String| -> Result<(), &str> {
            if is_valid_id(input) {
                Ok(())
            } else {
                Err("invalid id; use [a-z][a-z0-9_]*")
            }
        })
        .interact_text()
        .map_err(|e| io_err(&e.to_string()))?;

    let name: String = Input::new()
        .with_prompt("Display name")
        .default(title_case(&id))
        .interact_text()
        .map_err(|e| io_err(&e.to_string()))?;

    let author: String = Input::new()
        .with_prompt("Author name")
        .default(whoami_default())
        .interact_text()
        .map_err(|e| io_err(&e.to_string()))?;

    let author_url: String = Input::new()
        .with_prompt("Author URL (optional)")
        .allow_empty(true)
        .default(String::new())
        .interact_text()
        .map_err(|e| io_err(&e.to_string()))?;

    let description: String = Input::new()
        .with_prompt("Short description")
        .default(format!("A mod for Sensory Overload."))
        .interact_text()
        .map_err(|e| io_err(&e.to_string()))?;

    let repository: String = Input::new()
        .with_prompt("Repository URL (optional, e.g. https://github.com/<you>/<repo>)")
        .allow_empty(true)
        .default(String::new())
        .interact_text()
        .map_err(|e| io_err(&e.to_string()))?;

    let template = if let Some(t) = template_hint {
        if !TEMPLATE_NAMES.contains(&t.as_str()) {
            return Err(io_err(&format!("unknown template: {}", t)));
        }
        t
    } else {
        let idx = Select::new()
            .with_prompt("Template")
            .items(TEMPLATE_NAMES)
            .default(0)
            .interact()
            .map_err(|e| io_err(&e.to_string()))?;
        TEMPLATE_NAMES[idx].to_string()
    };

    let perm_indices = MultiSelect::new()
        .with_prompt("Permissions to declare (Space to toggle, Enter to confirm)")
        .items(PERMISSIONS)
        .interact()
        .map_err(|e| io_err(&e.to_string()))?;
    let permissions: Vec<String> = perm_indices
        .into_iter()
        .map(|i| PERMISSIONS[i].to_string())
        .collect();

    let output_dir = if here {
        std::env::current_dir()?
    } else {
        let default_dir = format!("./{}", id);
        let dir_str: String = Input::new()
            .with_prompt("Output directory")
            .default(default_dir)
            .interact_text()
            .map_err(|e| io_err(&e.to_string()))?;
        PathBuf::from(dir_str)
    };

    run(CreateOptions {
        id,
        name,
        author,
        author_url,
        description,
        repository,
        template,
        permissions,
        output_dir,
        here,
    })
}

fn lookup_template(name: &str) -> io::Result<Template> {
    match name {
        "minimal" => Ok(T_MINIMAL),
        "events" => Ok(T_EVENTS),
        "settings" => Ok(T_SETTINGS),
        "feature" => Ok(T_FEATURE),
        "ui" => Ok(T_UI),
        "campaign" => Ok(T_CAMPAIGN),
        _ => Err(io_err(&format!(
            "unknown template '{}'; expected one of: {}",
            name,
            TEMPLATE_NAMES.join(", ")
        ))),
    }
}

fn substitute(s: &str, placeholders: &HashMap<&str, String>) -> String {
    let mut out = s.to_string();
    for (key, value) in placeholders {
        let token = format!("{{{{{}}}}}", key);
        out = out.replace(&token, value);
    }
    out
}

// Replaces the literal `"permissions": []` in mod.json with the user's
// selection. Templates always start with the empty form, so a string-level
// replace is safe and preserves formatting.
fn inject_permissions(body: &str, perms: &[String]) -> io::Result<String> {
    let quoted: Vec<String> = perms.iter().map(|p| format!("\"{}\"", p)).collect();
    let replacement = format!("\"permissions\": [{}]", quoted.join(", "));
    if !body.contains("\"permissions\": []") {
        // Template doesn't have the empty form for some reason. Don't crash.
        return Ok(body.to_string());
    }
    Ok(body.replace("\"permissions\": []", &replacement))
}

// Mirrors the required-field check in scripts/core/mod_loader.gd::_normalize_metadata.
// Catches scaffolding regressions: if a template ever drops a required field,
// we'll fail loudly here instead of letting a broken mod ship.
fn validate_generated_mod(dir: &Path) -> io::Result<()> {
    let mod_json_path = dir.join("mod.json");
    let raw = fs::read_to_string(&mod_json_path)?;
    let parsed: serde_json::Value = serde_json::from_str(&raw)
        .map_err(|e| io_err(&format!("generated mod.json failed to parse: {}", e)))?;
    for required in [
        "schema_version",
        "id",
        "name",
        "version",
        "description",
        "entrypoints",
    ] {
        if parsed.get(required).is_none() {
            return Err(io_err(&format!(
                "generated mod.json missing required field: {}",
                required
            )));
        }
    }
    let entrypoints = parsed.get("entrypoints").and_then(|v| v.as_array());
    if entrypoints.map(|a| a.is_empty()).unwrap_or(true) {
        return Err(io_err(
            "generated mod.json must declare at least one entrypoint",
        ));
    }
    // Verify each entrypoint file exists in the scaffolded directory.
    for ep in entrypoints.unwrap() {
        let rel = ep.as_str().unwrap_or_default();
        if rel.is_empty() {
            continue;
        }
        let path = dir.join(rel);
        if !path.exists() {
            return Err(io_err(&format!(
                "entrypoint '{}' missing on disk after scaffold",
                rel
            )));
        }
    }
    Ok(())
}

pub fn is_valid_id(id: &str) -> bool {
    let mut chars = id.chars();
    let Some(first) = chars.next() else {
        return false;
    };
    if !first.is_ascii_lowercase() {
        return false;
    }
    chars.all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == '_')
}

fn title_case(id: &str) -> String {
    id.split('_')
        .map(|w| {
            let mut c = w.chars();
            match c.next() {
                Some(first) => first.to_ascii_uppercase().to_string() + c.as_str(),
                None => String::new(),
            }
        })
        .collect::<Vec<_>>()
        .join(" ")
}

fn whoami_default() -> String {
    std::env::var("USER")
        .or_else(|_| std::env::var("USERNAME"))
        .unwrap_or_else(|_| "anonymous".into())
}

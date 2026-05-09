use std::io;
use std::path::{Path, PathBuf};

use crate::config::Config;
use crate::error::io_err;
use crate::install::{install_shim, uninstall_shim};
use crate::launch::launch_game;
use crate::loadplan::generate_load_plan;
use crate::pack::pack_core;
use crate::scaffold;
use crate::steam::SteamScanner;

pub fn run_cli(config: &mut Config, mut args: Vec<String>) -> io::Result<()> {
    let command = args.remove(1);
    match command.as_str() {
        "install" => {
            let pck = if args.len() > 1 {
                PathBuf::from(&args[1])
            } else {
                SteamScanner::new()
                    .find_game_pck()
                    .ok_or_else(|| io_err("Not found"))?
            };
            install_shim(&pck)
        }
        "uninstall" => {
            let purge = args.iter().any(|a| a == "--purge");
            let positional: Vec<&String> = args.iter().filter(|a| !a.starts_with("--")).collect();
            let pck = if let Some(p) = positional.get(1) {
                PathBuf::from(p.as_str())
            } else {
                config
                    .pck_path
                    .clone()
                    .or_else(|| SteamScanner::new().find_game_pck())
                    .ok_or_else(|| io_err("Not found"))?
            };
            let log = |msg: &str| println!(">> {}", msg);
            uninstall_shim(&pck, purge, &log)?;
            if config.pck_path.as_deref() == Some(&pck) {
                config.pck_path = None;
                config.game_path = None;
                let _ = config.save();
            }
            Ok(())
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
        "create" => run_create(args),
        _ => Err(io_err("Unknown command")),
    }
}

// Argument shape (positional id + flags):
//   esp create [<id>] [--template <name>] [--dir <path>] [--here] [--no-prompt] [--repository <url>]
fn run_create(args: Vec<String>) -> io::Result<()> {
    let mut positional: Vec<String> = Vec::new();
    let mut template: Option<String> = None;
    let mut dir: Option<PathBuf> = None;
    let mut here = false;
    let mut no_prompt = false;
    let mut repository: Option<String> = None;

    // args[0] is the binary path (preserved across the run_cli `args.remove(1)`).
    let mut i = 1;
    while i < args.len() {
        let arg = &args[i];
        match arg.as_str() {
            "--template" => {
                i += 1;
                template = args.get(i).cloned();
                if template.is_none() {
                    return Err(io_err("--template needs a value"));
                }
            }
            "--dir" => {
                i += 1;
                let v = args.get(i).ok_or_else(|| io_err("--dir needs a value"))?;
                dir = Some(PathBuf::from(v));
            }
            "--repository" | "--repo" => {
                i += 1;
                let v = args
                    .get(i)
                    .ok_or_else(|| io_err("--repository needs a value"))?;
                repository = Some(v.clone());
            }
            "--here" => here = true,
            "--no-prompt" => no_prompt = true,
            other if other.starts_with("--") => {
                return Err(io_err(&format!("unknown flag: {}", other)));
            }
            other => positional.push(other.to_string()),
        }
        i += 1;
    }

    let id_arg = positional.into_iter().next();

    // Special form: `esp create --here <template>` (id arg becomes template).
    let (id_arg, template) = if here && template.is_none() && id_arg.is_some() {
        let candidate = id_arg.clone().unwrap();
        if scaffold::TEMPLATE_NAMES.contains(&candidate.as_str()) {
            (None, Some(candidate))
        } else {
            (id_arg, template)
        }
    } else {
        (id_arg, template)
    };

    if no_prompt {
        let id = id_arg
            .clone()
            .ok_or_else(|| io_err("--no-prompt requires a positional id"))?;
        if !scaffold::is_valid_id(&id) {
            return Err(io_err(&format!("invalid id '{}': use [a-z][a-z0-9_]*", id)));
        }
        let template = template.unwrap_or_else(|| "minimal".to_string());
        let output_dir = dir.unwrap_or_else(|| PathBuf::from(format!("./{}", id)));
        let display_name = id
            .split('_')
            .map(|w| {
                let mut c = w.chars();
                match c.next() {
                    Some(first) => first.to_ascii_uppercase().to_string() + c.as_str(),
                    None => String::new(),
                }
            })
            .collect::<Vec<_>>()
            .join(" ");
        scaffold::run(scaffold::CreateOptions {
            id: id.clone(),
            name: display_name,
            author: std::env::var("USER")
                .or_else(|_| std::env::var("USERNAME"))
                .unwrap_or_else(|_| "anonymous".into()),
            author_url: String::new(),
            description: "A mod for Sensory Overload.".into(),
            repository: repository.clone().unwrap_or_default(),
            template,
            permissions: Vec::new(),
            output_dir,
            here,
        })
    } else if template.is_some() && id_arg.is_some() && !here {
        // One-shot template mode with id supplied: skip prompts but still allow
        // dir override and use sensible defaults.
        let id = id_arg.unwrap();
        if !scaffold::is_valid_id(&id) {
            return Err(io_err(&format!("invalid id '{}': use [a-z][a-z0-9_]*", id)));
        }
        let template = template.unwrap();
        let output_dir = dir.unwrap_or_else(|| PathBuf::from(format!("./{}", id)));
        scaffold::run(scaffold::CreateOptions {
            name: id
                .split('_')
                .map(|w| {
                    let mut c = w.chars();
                    match c.next() {
                        Some(first) => first.to_ascii_uppercase().to_string() + c.as_str(),
                        None => String::new(),
                    }
                })
                .collect::<Vec<_>>()
                .join(" "),
            id,
            author: std::env::var("USER")
                .or_else(|_| std::env::var("USERNAME"))
                .unwrap_or_else(|_| "anonymous".into()),
            author_url: String::new(),
            description: "A mod for Sensory Overload.".into(),
            repository: repository.clone().unwrap_or_default(),
            template,
            permissions: Vec::new(),
            output_dir,
            here,
        })
    } else {
        scaffold::run_interactive(id_arg, here, template)
    }
}

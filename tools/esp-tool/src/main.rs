use std::env;

use eframe::egui;

mod cli;
mod config;
mod error;
mod gamelog;
mod github;
mod gui;
mod install;
mod launch;
mod loadplan;
mod modhash;
mod modmgr;
mod pack;
mod pck;
mod scaffold;
mod steam;

pub const VERSION: &str = "0.0.2";

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() > 1 {
        let mut cfg = config::Config::load();
        if let Err(err) = cli::run_cli(&mut cfg, args) {
            eprintln!("error: {}", err);
            std::process::exit(1);
        }
    } else {
        let options = eframe::NativeOptions {
            viewport: egui::ViewportBuilder::default().with_inner_size([600.0, 500.0]),
            ..Default::default()
        };
        let _ = eframe::run_native(
            "ESP Orchestrator",
            options,
            Box::new(|cc| Box::new(gui::EspApp::new(cc))),
        );
    }
}

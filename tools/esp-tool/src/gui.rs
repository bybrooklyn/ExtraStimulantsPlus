use std::collections::VecDeque;
use std::sync::{Arc, Mutex};
use std::thread;

use eframe::egui;

use crate::config::Config;
use crate::gamelog::{self, LogTailer};
use crate::install::{fetch_framework, run_setup, uninstall_shim};
use crate::launch::launch_game;
use crate::loadplan::generate_load_plan;
use crate::modmgr;
use crate::steam::SteamScanner;
use crate::VERSION;

const GAMELOG_LINE_CAP: usize = 1500;

pub struct EspApp {
    pub config: Config,
    pub logs: Arc<Mutex<String>>,
    pub status: String,
    pub install_running: bool,
    pub mods_view: modmgr::ModsView,
    pub gamelog_tailer: Option<LogTailer>,
    pub gamelog_lines: VecDeque<String>,
    pub uninstall_dialog_open: bool,
    pub uninstall_purge: bool,
}

impl EspApp {
    pub fn new(cc: &eframe::CreationContext<'_>) -> Self {
        let mut visuals = egui::Visuals::dark();
        visuals.window_rounding = 8.0.into();
        visuals.widgets.active.bg_fill = egui::Color32::from_rgb(0, 200, 255);
        cc.egui_ctx.set_visuals(visuals);

        let config = Config::load();
        let mods_view = match config.pck_path.as_ref().and_then(|p| p.parent()) {
            Some(game_dir) => modmgr::refresh(game_dir),
            None => modmgr::ModsView::default(),
        };
        let gamelog_tailer = gamelog::resolve_log_path().map(LogTailer::new);

        Self {
            config,
            logs: Arc::new(Mutex::new(String::new())),
            status: "Ready".to_string(),
            install_running: false,
            mods_view,
            gamelog_tailer,
            gamelog_lines: VecDeque::with_capacity(GAMELOG_LINE_CAP),
            uninstall_dialog_open: false,
            uninstall_purge: false,
        }
    }
}

impl eframe::App for EspApp {
    fn update(&mut self, ctx: &egui::Context, _frame: &mut eframe::Frame) {
        egui::CentralPanel::default().show(ctx, |ui| {
            ui.vertical_centered(|ui| {
                ui.heading(
                    egui::RichText::new("ESP Orchestrator")
                        .size(32.0)
                        .strong()
                        .color(egui::Color32::from_rgb(0, 255, 255)),
                );
                ui.label(format!("Framework Version: {}", VERSION));
            });

            ui.add_space(20.0);

            ui.group(|ui| {
                ui.set_width(ui.available_width());
                ui.label(egui::RichText::new("Game Installation").strong());
                if let Some(path) = &self.config.pck_path {
                    ui.label(format!("Path: {}", path.display()));
                } else {
                    ui.label("Status: Not Detected");
                }

                if ui.button("Auto-Detect via Steam").clicked() {
                    if let Some(pck) = SteamScanner::new().find_game_pck() {
                        self.config.pck_path = Some(pck.clone());
                        if let Some(p) = pck.parent() {
                            self.config.game_path = Some(p.to_path_buf());
                        }
                        let _ = self.config.save();
                        self.status = "Game detected!".to_string();
                    } else {
                        self.status = "Steam path not found.".to_string();
                    }
                }
            });

            ui.add_space(10.0);

            ui.horizontal(|ui| {
                if ui
                    .add_enabled(
                        !self.install_running,
                        egui::Button::new("ONE-CLICK SETUP").min_size([120.0, 40.0].into()),
                    )
                    .clicked()
                {
                    self.install_running = true;
                    let logs = Arc::clone(&self.logs);
                    let mut cfg = self.config.clone();
                    thread::spawn(move || {
                        let _ = run_setup(&mut cfg, logs);
                    });
                }

                if ui
                    .add_enabled(
                        self.config.pck_path.is_some(),
                        egui::Button::new("LAUNCH GAME").min_size([120.0, 40.0].into()),
                    )
                    .clicked()
                {
                    let cfg = self.config.clone();
                    thread::spawn(move || {
                        let _ = generate_load_plan(&cfg);
                        let _ = launch_game(&cfg, false);
                    });
                }

                if ui
                    .add_enabled(
                        self.config.pck_path.is_some() && !self.install_running,
                        egui::Button::new("UNINSTALL").min_size([100.0, 40.0].into()),
                    )
                    .clicked()
                {
                    self.uninstall_dialog_open = true;
                    self.uninstall_purge = false;
                }

                if ui
                    .add_enabled(
                        self.config.pck_path.is_some(),
                        egui::Button::new("UPDATE FRAMEWORK").min_size([140.0, 40.0].into()),
                    )
                    .clicked()
                {
                    let logs = Arc::clone(&self.logs);
                    let cfg = self.config.clone();
                    thread::spawn(move || {
                        let log = move |msg: &str| {
                            if let Ok(mut l) = logs.lock() {
                                l.push_str(&format!(">> {}\n", msg));
                            }
                        };
                        if let Err(e) = fetch_framework(&cfg, &log) {
                            log(&format!("Framework update failed: {}", e));
                        }
                    });
                }
            });

            ui.add_space(10.0);

            // Mod manager panel.
            if let Some(game_dir) = self.config.pck_path.as_ref().and_then(|p| p.parent()) {
                modmgr::refresh_if_stale(game_dir, &mut self.mods_view);
                modmgr::draw_panel(ui, game_dir, &mut self.mods_view);
            }

            ui.add_space(10.0);

            // Game Log: tails Godot's user://logs/godot.log if it exists.
            // The tailer self-throttles when the file isn't being written.
            if let Some(tailer) = self.gamelog_tailer.as_mut() {
                let new_lines = tailer.poll();
                for line in new_lines {
                    self.gamelog_lines.push_back(line);
                }
                while self.gamelog_lines.len() > GAMELOG_LINE_CAP {
                    self.gamelog_lines.pop_front();
                }
            }

            egui::CollapsingHeader::new(egui::RichText::new("Game Log").strong())
                .default_open(false)
                .show(ui, |ui| {
                    ui.horizontal(|ui| {
                        if let Some(tailer) = self.gamelog_tailer.as_ref() {
                            ui.label(
                                egui::RichText::new(tailer.path.display().to_string())
                                    .monospace()
                                    .weak(),
                            );
                        } else {
                            ui.label(
                                egui::RichText::new("(no log path resolved for this OS)")
                                    .italics()
                                    .weak(),
                            );
                        }
                        if ui.button("Clear").clicked() {
                            self.gamelog_lines.clear();
                        }
                        if ui.button("Jump to live").clicked() {
                            self.gamelog_lines.clear();
                            if let Some(tailer) = self.gamelog_tailer.as_mut() {
                                tailer.rewind_to_end();
                            }
                        }
                    });
                    let mut joined: String = self
                        .gamelog_lines
                        .iter()
                        .cloned()
                        .collect::<Vec<_>>()
                        .join("\n");
                    egui::ScrollArea::vertical()
                        .stick_to_bottom(true)
                        .min_scrolled_height(180.0)
                        .show(ui, |ui| {
                            ui.add(
                                egui::TextEdit::multiline(&mut joined)
                                    .font(egui::TextStyle::Monospace)
                                    .desired_width(f32::INFINITY)
                                    .desired_rows(12)
                                    .lock_focus(true),
                            );
                        });
                });

            ui.add_space(10.0);

            ui.label("Logs:");
            egui::ScrollArea::vertical()
                .stick_to_bottom(true)
                .show(ui, |ui| {
                    let logs = self.logs.lock().unwrap_or_else(|e| e.into_inner());
                    ui.add(
                        egui::TextEdit::multiline(&mut logs.as_str())
                            .font(egui::TextStyle::Monospace)
                            .desired_width(f32::INFINITY)
                            .desired_rows(15)
                            .lock_focus(true),
                    );
                });

            ui.with_layout(egui::Layout::bottom_up(egui::Align::LEFT), |ui| {
                ui.label(format!("Status: {}", self.status));
            });
        });

        if self.uninstall_dialog_open {
            let mut close = false;
            let mut confirmed = false;
            egui::Window::new("Confirm Uninstall")
                .collapsible(false)
                .resizable(false)
                .anchor(egui::Align2::CENTER_CENTER, [0.0, 0.0])
                .show(ctx, |ui| {
                    ui.label("Restore the original game PCK and remove the ESP shim.");
                    ui.add_space(6.0);
                    ui.checkbox(
                        &mut self.uninstall_purge,
                        "Also delete user data (mods/, levels/, modloader/, campaigns/)",
                    );
                    if self.uninstall_purge {
                        ui.colored_label(
                            egui::Color32::from_rgb(255, 120, 120),
                            "This will delete all installed mods, custom levels, and saved settings.",
                        );
                    }
                    ui.add_space(8.0);
                    ui.horizontal(|ui| {
                        if ui.button("Cancel").clicked() { close = true; }
                        if ui.button("Uninstall").clicked() { confirmed = true; }
                    });
                });
            if confirmed {
                let logs = Arc::clone(&self.logs);
                let cfg = self.config.clone();
                let purge = self.uninstall_purge;
                thread::spawn(move || {
                    let log = move |msg: &str| {
                        if let Ok(mut l) = logs.lock() {
                            l.push_str(&format!(">> {}\n", msg));
                        }
                    };
                    if let Some(pck) = cfg.pck_path.as_ref() {
                        if let Err(e) = uninstall_shim(pck, purge, &log) {
                            log(&format!("Uninstall failed: {}", e));
                        }
                    }
                });
                self.config.pck_path = None;
                self.config.game_path = None;
                let _ = self.config.save();
                close = true;
            }
            if close {
                self.uninstall_dialog_open = false;
            }
        }

        ctx.request_repaint();
    }
}

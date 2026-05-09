# {{name}}

Built on the [ExtraStimulantsPlus](https://github.com/bybrooklyn/extrastimulantsplus) framework. Demonstrates **UI injection** via `api.ui`.

This mod adds a button to the main menu. The button uses ESP's idempotent injection helper (`inject_main_menu_button`), so calling it multiple times with the same `owner_id` is a no-op.

To inject a HUD overlay during gameplay (e.g. a debug panel, a stats display), use `api.ui.inject_hud_overlay(scene_or_node, MOD_ID, {"layer": 100})`. Non-persistent overlays auto-tear-down on `level_completed` and `player_died`.

To wait for a specific game node before doing something, use `api.ui.wait_for_node("PauseMenu", _my_callback, {"timeout_ms": 5000})`.

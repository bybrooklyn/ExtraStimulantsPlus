extends Node

# {{name}} — entrypoint that injects a button into the main menu.
#
# api.ui surface (see scripts/core/esp_api.gd::UINamespace):
#   inject_main_menu_button(label, callback, owner_id, options) -> Button
#   inject_hud_overlay(node_or_scene, owner_id, options)        -> CanvasLayer
#   wait_for_node(name_or_path, callback, options)              -> void
#   set_badge_visible(bool) / set_badge_color(Color)
#   get_theme_accent() -> Color
#
# All injections are namespaced by `owner_id` so two mods can both add a
# "Settings" button without colliding.

const MOD_ID := "{{id}}"

var api: Node
var meta: Dictionary

func esp_init(p_api: Node, p_meta: Dictionary) -> bool:
    api = p_api
    meta = p_meta
    api.log_info("[%s] init" % MOD_ID)
    return true

func esp_ready(_api: Node, _meta: Dictionary) -> void:
    # The MainMenu may not be in the tree yet on `esp_ready`; api.ui handles
    # that internally by deferring through wait_for_node.
    api.ui.inject_main_menu_button(
        "{{name}}",
        Callable(self, "_on_button_pressed"),
        MOD_ID,
        {"position": "after:SettingsButton"}
    )

func _on_button_pressed() -> void:
    api.log_info("[%s] menu button pressed" % MOD_ID)
    # Real mods would open a custom scene, change game state, or pop a dialog.

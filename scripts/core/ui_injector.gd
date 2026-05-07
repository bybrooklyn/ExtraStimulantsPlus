extends Node

# ESP UI Injector - Framework Owned
# Handles the top-right status badge and patching game menus.

var _active_badge: Control

const GAME_UI_NAMES := {
    "main_menu": "MainMenu",
    "settings_menu": "SettingsMenu",
    "main_menu_container": "MenuContainer",
    "settings_button": "SettingsButton"
}

func _enter_tree():
    if not get_tree().node_added.is_connected(_on_node_added):
        get_tree().node_added.connect(_on_node_added)

func _process(_delta):
    if _active_badge and _active_badge.is_inside_tree() and _active_badge.visible:
        var visualizer = get_node_or_null("/root/AudioVisualizer")
        if visualizer:
            var pulse = visualizer.get_bass_pulse()
            var s = 1.0 + (pulse * 0.1)
            _active_badge.scale = Vector2(s, s)
            _active_badge.pivot_offset = Vector2(_active_badge.size.x, 0)

const SETTINGS_UI_SCRIPT := "res://scripts/core/esp_settings_ui.gd"
var _settings_ui: Node
var _hooked_settings_menus: Array[int] = []

func _on_node_added(node: Node):
    if node.name == GAME_UI_NAMES.main_menu and node is Control:
        _active_badge = null
        _inject_framework_badge(node)
        _patch_main_menu_buttons(node)
        return

    var menu := _resolve_settings_menu(node)
    if menu:
        _hook_settings_menu(menu)

func _resolve_settings_menu(node: Node) -> Control:
    if node == null:
        return null

    if node.name == GAME_UI_NAMES.settings_menu and node is Control:
        return node

    var parent := node.get_parent()
    if parent and parent.name == GAME_UI_NAMES.settings_menu and parent is Control:
        return parent

    return null

func _hook_settings_menu(menu: Control) -> void:
    if not _settings_ui:
        var script = load(SETTINGS_UI_SCRIPT)
        if script:
            _settings_ui = script.new()
            add_child(_settings_ui)

    var menu_id := menu.get_instance_id()
    if _hooked_settings_menus.has(menu_id):
        if _settings_ui and _settings_ui.has_method("refresh_settings_ui"):
            _settings_ui.refresh_settings_ui()
        return

    _hooked_settings_menus.append(menu_id)
    
    if _settings_ui and _settings_ui.has_method("hook_settings_menu"):
        _settings_ui.hook_settings_menu(menu)

func _inject_framework_badge(menu: Control):
    var box = VBoxContainer.new()
    box.name = "ESPFrameworkBadge"
    _active_badge = box
    box.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
    box.offset_left = -500
    box.offset_top = 18
    box.offset_right = -20
    box.offset_bottom = 120
    menu.add_child(box)
    
    var mod_loader = _get_esp_mod_loader()
    var num_mods = mod_loader.loaded_mods.size() if mod_loader else 0
    var version = "v0.0.0"
    var settings = get_node_or_null("/root/ExtraStimulantsPlusSettings")
    if settings: version = settings.get_version()

    var label = Label.new()
    # Format: MODDED - VERSION - # MODS
    label.text = "MODDED - %s - %d MODS" % [version.to_upper(), num_mods]
    label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    label.add_theme_font_size_override("font_size", 22)
    label.add_theme_color_override("font_color", Color(0.1, 0.8, 1.0, 1.0)) # Cyber Blue
    label.add_theme_constant_override("outline_size", 6)
    label.add_theme_color_override("font_outline_color", Color.BLACK)
    box.add_child(label)

func _patch_main_menu_buttons(menu: Control):
    # This remains to allow the framework to inject the "CUSTOM MAPS" or other core entries
    var container = menu.find_child(GAME_UI_NAMES.main_menu_container, true, false)
    if container:
        # Check settings if we should show the editor button (framework still manages this entry)
        var settings = get_node_or_null("/root/ExtraStimulantsPlusSettings")
        if settings and settings.should_show_editor_entry():
             _inject_custom_maps_button(container)

func _inject_custom_maps_button(container: VBoxContainer):
    if container.has_node("CustomMapsButton"): return
    var btn = Button.new()
    btn.name = "CustomMapsButton"
    btn.text = "CUSTOM MAPS"
    btn.custom_minimum_size = Vector2(410, 55)
    btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
    btn.pressed.connect(func():
        var context = get_node_or_null("/root/GameContext")
        if context: context.set_mode(context.GameMode.EDITOR)
        get_tree().change_scene_to_file("res://scenes/level_editor/level_browser.tscn")
    )
    container.add_child(btn)
    var settings_btn = container.get_node_or_null(GAME_UI_NAMES.settings_button)
    if settings_btn: container.move_child(btn, settings_btn.get_index())

func _patch_settings_menu(node: Node):
    var gameplay_box = node.find_child("GameplayVBox", true, false)
    if gameplay_box and not gameplay_box.has_node("ESPSettingsRow"):
        _inject_settings_row(gameplay_box, node)

func _inject_settings_row(container: VBoxContainer, _menu: Control):
    container.add_child(HSeparator.new())
    var row = HBoxContainer.new()
    row.name = "ESPSettingsRow"
    var label = Label.new()
    label.text = "ESP Framework Active"
    label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    row.add_child(label)
    container.add_child(row)

func _get_esp_mod_loader() -> Node:
    return get_node_or_null("/root/ESPModLoader") or get_node_or_null("/root/ModLoader")

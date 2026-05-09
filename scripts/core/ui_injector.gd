extends Node

# ESP UI Injector - Framework Owned
# Handles the top-right status badge and patching game menus.

# Single shared accent for framework-branded UI. Mods can read this via
# api.ui.get_theme_accent() (see esp_api.gd's UINamespace) to match the badge.
const BADGE_ACCENT := Color(0.1, 0.8, 1.0, 1.0)
const BADGE_NODE_NAME := "ESPFrameworkBadge"

var _active_badge: Control

# Tracks every UI injection so calls are idempotent and overlays can be torn
# down on level transitions. Keyed by `owner_id` -> Array of injection records:
# {"kind": "main_menu_button"|"hud_overlay", "key": String, "node": Node, "options": Dictionary}.
var _owned_injections: Dictionary = {}
var _event_bus_connected: bool = false

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
        # If this MainMenu instance was already injected (e.g. scene re-entered),
        # rebind the cached badge ref instead of duplicating the node.
        var existing := node.get_node_or_null(BADGE_NODE_NAME)
        if existing:
            _active_badge = existing
        else:
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
    box.name = BADGE_NODE_NAME
    _active_badge = box
    # Anchor to the top-right so the badge tracks the right edge across
    # resolutions. Margins are small symmetric values; sizing comes from content.
    box.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_KEEP_SIZE)
    box.anchor_left = 1.0
    box.anchor_right = 1.0
    box.offset_left = -520
    box.offset_top = 18
    box.offset_right = -20
    box.size_flags_horizontal = Control.SIZE_SHRINK_END
    menu.add_child(box)

    var num_mods := 0
    var mod_loader = _get_esp_mod_loader()
    if mod_loader and "loaded_mods" in mod_loader:
        num_mods = mod_loader.loaded_mods.size()
    var version := _resolve_framework_version()

    var label = Label.new()
    label.text = "MODDED - %s - %d MODS" % [version.to_upper(), num_mods]
    label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    label.add_theme_color_override("font_color", _resolve_badge_color(menu))
    # Outline keeps the label readable against bright menu backgrounds.
    label.add_theme_constant_override("outline_size", 6)
    label.add_theme_color_override("font_outline_color", Color.BLACK)
    box.add_child(label)


# Pulls the accent color from the menu's theme cascade if it defines one named
# "esp_accent" or "accent"; otherwise falls back to BADGE_ACCENT. Lets games
# that customize their theme override the framework's branding.
func _resolve_badge_color(menu: Control) -> Color:
    var theme := menu.theme
    if theme:
        if theme.has_color("esp_accent", "Label"):
            return theme.get_color("esp_accent", "Label")
        if theme.has_color("accent", "Label"):
            return theme.get_color("accent", "Label")
    return BADGE_ACCENT


func _resolve_framework_version() -> String:
    var core := get_node_or_null("/root/ESPCore")
    if core and "CORE_VERSION" in core:
        return "v" + String(core.CORE_VERSION)
    var settings = get_node_or_null("/root/ExtraStimulantsPlusSettings")
    if settings and settings.has_method("get_version"):
        return String(settings.get_version())
    return "v0.0.0"

func _patch_main_menu_buttons(_menu: Control):
    # Demonstrate the public api.ui surface — the framework's own injection
    # uses the same path mods will. Owner_id "_framework" prevents collision.
    var settings = get_node_or_null("/root/ExtraStimulantsPlusSettings")
    if settings and settings.has_method("should_show_editor_entry") and settings.should_show_editor_entry():
        inject_main_menu_button(
            "CUSTOM MAPS",
            Callable(self, "_open_custom_maps_browser"),
            "_framework",
            {"position": "before:" + GAME_UI_NAMES.settings_button}
        )


func _open_custom_maps_browser() -> void:
    var context = get_node_or_null("/root/GameContext")
    if context: context.set_mode(context.GameMode.EDITOR)
    get_tree().change_scene_to_file("res://scenes/level_editor/level_browser.tscn")

func _get_esp_mod_loader() -> Node:
    return get_node_or_null("/root/ESPModLoader") or get_node_or_null("/root/ModLoader")


# ---------------------------------------------------------------------------
# Public api.ui surface — called via the UINamespace in esp_api.gd. Each
# injection is tracked by owner_id so calling twice is a no-op (returns the
# existing node) and so HUD overlays can be auto-torn-down on level end.
# ---------------------------------------------------------------------------

func inject_main_menu_button(label: String, on_click: Callable, owner_id: String, options: Dictionary = {}) -> Button:
    var key := "main_menu_button:" + label
    var existing := _find_injection(owner_id, key)
    if existing and existing is Button and is_instance_valid(existing):
        return existing as Button

    var menu := _find_main_menu()
    if menu == null:
        # Defer until MainMenu shows up. Re-fire from _on_node_added.
        wait_for_node(GAME_UI_NAMES.main_menu, func(_n):
            inject_main_menu_button(label, on_click, owner_id, options),
            {"timeout_ms": 10000})
        return null

    var container = menu.find_child(GAME_UI_NAMES.main_menu_container, true, false)
    if container == null:
        return null

    var btn := Button.new()
    btn.name = "ESP_%s_%s" % [owner_id, label.to_lower().replace(" ", "_")]
    btn.text = label
    btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
    # Match sibling buttons so it inherits the SO theme cascade rather than
    # standing out. Mods can override via options.theme.
    var sibling := _first_button_child(container)
    if sibling:
        btn.custom_minimum_size = sibling.custom_minimum_size
    if on_click.is_valid():
        btn.pressed.connect(on_click)
    container.add_child(btn)

    _apply_button_position(btn, container, options)
    _record_injection(owner_id, "main_menu_button", key, btn, options)
    return btn


func inject_hud_overlay(node_or_scene, owner_id: String, options: Dictionary = {}) -> CanvasLayer:
    var key := "hud_overlay:" + str(node_or_scene)
    var existing := _find_injection(owner_id, key)
    if existing and existing is CanvasLayer and is_instance_valid(existing):
        return existing as CanvasLayer

    var content: Node
    if node_or_scene is PackedScene:
        content = (node_or_scene as PackedScene).instantiate()
    elif node_or_scene is Node:
        content = node_or_scene
    else:
        push_warning("[ESP UI] inject_hud_overlay: expected Node or PackedScene")
        return null

    var layer := CanvasLayer.new()
    layer.layer = int(options.get("layer", 100))
    layer.name = "ESP_HUD_%s_%s" % [owner_id, str(content.name) if content.name else "overlay"]
    layer.add_child(content)
    if content is Control:
        # Default to non-blocking input so HUD overlays don't steal clicks.
        (content as Control).mouse_filter = Control.MOUSE_FILTER_IGNORE
    get_tree().root.add_child(layer)

    _record_injection(owner_id, "hud_overlay", key, layer, options)
    _ensure_event_bus_connected()
    return layer


func wait_for_node(name_or_path: String, callback: Callable, options: Dictionary = {}) -> void:
    if not callback.is_valid():
        return
    # Fast path: maybe the node is already in the tree.
    var existing := _find_first_by_name(name_or_path)
    if existing:
        callback.call(existing)
        return

    var timeout_ms := int(options.get("timeout_ms", 5000))
    var state := { "fired": false, "timer": null, "timeout_cb": null }

    var listener: Callable
    listener = func(node: Node):
        if state.fired:
            return
        if node.name == name_or_path or node.get_path().get_concatenated_names().ends_with(name_or_path):
            state.fired = true
            if get_tree().node_added.is_connected(listener):
                get_tree().node_added.disconnect(listener)
            # Disconnect the timeout so its closure can be released and the
            # spurious "timed out" warning never fires when the node arrives
            # near the deadline.
            if state.timer != null and state.timeout_cb != null \
                    and state.timer.timeout.is_connected(state.timeout_cb):
                state.timer.timeout.disconnect(state.timeout_cb)
            callback.call(node)

    get_tree().node_added.connect(listener)

    if timeout_ms > 0:
        var timeout_cb := func():
            if state.fired:
                return
            state.fired = true
            if get_tree().node_added.is_connected(listener):
                get_tree().node_added.disconnect(listener)
            push_warning("[ESP UI] wait_for_node('%s') timed out after %dms" % [name_or_path, timeout_ms])
        var timer := get_tree().create_timer(timeout_ms / 1000.0)
        state.timer = timer
        state.timeout_cb = timeout_cb
        timer.timeout.connect(timeout_cb)


func set_badge_visible(visible: bool) -> void:
    if _active_badge and is_instance_valid(_active_badge):
        _active_badge.visible = visible


func set_badge_color(c: Color) -> void:
    if _active_badge == null or not is_instance_valid(_active_badge):
        return
    for child in _active_badge.get_children():
        if child is Label:
            (child as Label).add_theme_color_override("font_color", c)


func get_theme_accent() -> Color:
    if _active_badge and is_instance_valid(_active_badge):
        var parent = _active_badge.get_parent()
        if parent is Control:
            return _resolve_badge_color(parent as Control)
    return BADGE_ACCENT


# ---------------------------------------------------------------------------
# Internal helpers for the api.ui surface.
# ---------------------------------------------------------------------------

func _find_main_menu() -> Control:
    var menu := _find_first_by_name(GAME_UI_NAMES.main_menu)
    return menu as Control if menu else null


func _find_first_by_name(node_name: String) -> Node:
    return _scan(get_tree().root, node_name)


func _scan(node: Node, target: String) -> Node:
    if node.name == target:
        return node
    for child in node.get_children():
        var found := _scan(child, target)
        if found:
            return found
    return null


func _first_button_child(container: Node) -> Button:
    for child in container.get_children():
        if child is Button:
            return child
    return null


func _apply_button_position(btn: Button, container: Node, options: Dictionary) -> void:
    var pos := String(options.get("position", "end"))
    if pos == "end" or pos.is_empty():
        return
    var anchor_name := ""
    var place_before := false
    if pos.begins_with("before:"):
        anchor_name = pos.substr("before:".length())
        place_before = true
    elif pos.begins_with("after:"):
        anchor_name = pos.substr("after:".length())
    else:
        return
    var anchor: Node = container.get_node_or_null(anchor_name)
    if anchor == null:
        return
    var anchor_idx := anchor.get_index()
    container.move_child(btn, anchor_idx if place_before else anchor_idx + 1)


func _find_injection(owner_id: String, key: String) -> Node:
    var bucket: Array = _owned_injections.get(owner_id, [])
    for record in bucket:
        if record.get("key", "") == key:
            var node = record.get("node")
            if node and is_instance_valid(node):
                return node
    return null


func _record_injection(owner_id: String, kind: String, key: String, node: Node, options: Dictionary) -> void:
    var bucket: Array = _owned_injections.get(owner_id, [])
    bucket.append({"kind": kind, "key": key, "node": node, "options": options.duplicate(true)})
    _owned_injections[owner_id] = bucket


# Connect once to the game's EventBus for HUD cleanup. We can't go through
# api.events because the injector predates `api`; using EventBus directly is
# the same approach esp_event_adapter.gd uses.
func _ensure_event_bus_connected() -> void:
    if _event_bus_connected:
        return
    var bus := get_node_or_null("/root/EventBus")
    if bus == null:
        return
    if bus.has_signal("level_completed") and not bus.is_connected("level_completed", _on_level_ended):
        bus.connect("level_completed", _on_level_ended)
    if bus.has_signal("player_died") and not bus.is_connected("player_died", _on_level_ended):
        bus.connect("player_died", _on_level_ended)
    _event_bus_connected = true


func _on_level_ended(_a = null, _b = null) -> void:
    # Tear down non-persistent HUD overlays.
    for owner_id in _owned_injections.keys():
        var bucket: Array = _owned_injections[owner_id]
        var kept: Array = []
        for record in bucket:
            if record.get("kind") != "hud_overlay":
                kept.append(record)
                continue
            var options: Dictionary = record.get("options", {})
            if bool(options.get("persistent", false)):
                kept.append(record)
                continue
            var node = record.get("node")
            if node and is_instance_valid(node):
                node.queue_free()
        _owned_injections[owner_id] = kept

extends Node

# ESP Settings UI Generator - Framework Owned
# Integrates registered mod settings into Sensory Overload's native SettingsMenu.

const MODS_TAB_BUTTON_NAME := "ModsTabButton"
const MODS_CONTAINER_NAME := "ESPModsSettingsContainer"
const MODS_TAB_LABEL := "MODS"
# Style anchor: when calling the game's `_make_section_header(text, index)` /
# `_make_pill_toggle(index)` helpers, we want the same visual style the LAST
# native tab uses. Resolved at runtime by _native_style_anchor() so we don't
# break when the game adds, removes, or reorders tabs.
const NATIVE_STYLE_FALLBACK := 3
const MODS_TAB_ACCENT := Color(1.0, 0.831, 0.122, 1.0)
const MODS_TAB_INACTIVE := Color(0.145, 0.086, 0.0, 0.6)
const ROW_HOVER_LEFT_PADDING := 42.0
const ROW_HOVER_BAR_WIDTH := 3.0
# After ~2 seconds (120 frames @ 60Hz) of waiting for the SettingsMenu's
# native internals to be ready, give up rather than poll forever.
const HOOK_RETRY_BUDGET := 120

var settings_menu: Control
var esp_tab_container: VBoxContainer

var _mods_button: Button
var _registry: Node
var _pending_refresh := false
var _mods_active := false
var _hook_retries_remaining := HOOK_RETRY_BUDGET


func hook_settings_menu(menu: Control) -> void:
    if menu == null or not is_instance_valid(menu):
        return

    settings_menu = menu
    _hook_retries_remaining = HOOK_RETRY_BUDGET
    _connect_registry()
    call_deferred("_hook_settings_menu_deferred", menu)


func refresh_settings_ui() -> void:
    if _pending_refresh:
        return
    _pending_refresh = true
    call_deferred("_refresh_settings_ui_deferred")


func _hook_settings_menu_deferred(menu: Control) -> void:
    if menu == null or not is_instance_valid(menu) or menu != settings_menu:
        return

    if not _settings_menu_has_native_internals(menu):
        _hook_retries_remaining -= 1
        if _hook_retries_remaining <= 0:
            _log_warn("SettingsMenu native internals never appeared; giving up after %d frames" % HOOK_RETRY_BUDGET)
            return
        call_deferred("_hook_settings_menu_deferred", menu)
        return

    if not _install_mods_tab():
        return

    _connect_native_tab_buttons()
    _connect_registry()
    refresh_settings_ui()


func _refresh_settings_ui_deferred() -> void:
    _pending_refresh = false
    if esp_tab_container == null or not is_instance_valid(esp_tab_container):
        return

    _populate_mod_settings()


func _install_mods_tab() -> bool:
    var tab_bar := _get_tab_bar()
    var content_vbox := _get_content_vbox()
    if tab_bar == null or content_vbox == null:
        _log_warn("SettingsMenu internals were not ready; MODS tab was not installed")
        return false

    _mods_button = tab_bar.get_node_or_null(MODS_TAB_BUTTON_NAME) as Button
    if _mods_button == null:
        _mods_button = _create_mods_tab_button()
        tab_bar.add_child(_mods_button)

    if not _mods_button.has_meta("esp_mods_tab_watcher"):
        _mods_button.set_meta("esp_mods_tab_watcher", true)
        _mods_button.pressed.connect(_on_mods_tab_pressed)

    esp_tab_container = content_vbox.get_node_or_null(MODS_CONTAINER_NAME) as VBoxContainer
    if esp_tab_container == null:
        esp_tab_container = VBoxContainer.new()
        esp_tab_container.name = MODS_CONTAINER_NAME
        esp_tab_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        esp_tab_container.add_theme_constant_override("separation", 20)
        esp_tab_container.visible = false
        content_vbox.add_child(esp_tab_container)

    if not _mods_active and esp_tab_container and is_instance_valid(esp_tab_container):
        esp_tab_container.visible = false

    var sections := _get_section_containers()
    if not sections.has(esp_tab_container):
        sections.append(esp_tab_container)

    _apply_mods_tab_state(false)
    return true


func _create_mods_tab_button() -> Button:
    var btn := Button.new()
    btn.name = MODS_TAB_BUTTON_NAME
    btn.text = MODS_TAB_LABEL
    btn.custom_minimum_size = Vector2(203, 45)
    btn.alignment = HORIZONTAL_ALIGNMENT_CENTER
    btn.focus_mode = Control.FOCUS_ALL
    btn.add_theme_font_size_override("font_size", 24)
    _style_tab_button(btn, false)
    return btn


func _connect_native_tab_buttons() -> void:
    var buttons := _get_nav_buttons()
    for i in range(buttons.size()):
        var btn := buttons[i] as Button
        if btn == null or btn == _mods_button or btn.has_meta("esp_native_tab_watcher"):
            continue
        btn.set_meta("esp_native_tab_watcher", true)
        btn.pressed.connect(_on_native_tab_pressed.bind(i))


func _on_native_tab_pressed(index: int) -> void:
    if not _mods_active:
        return

    _mods_active = false
    _apply_mods_tab_state(false)

    if settings_menu and is_instance_valid(settings_menu) and settings_menu.has_method("_select_section"):
        settings_menu.call("_select_section", index)
    else:
        var sections := _get_section_containers()
        for i in range(sections.size()):
            var container := sections[i] as Control
            if container:
                container.visible = (i == index)

    if esp_tab_container and is_instance_valid(esp_tab_container):
        esp_tab_container.visible = false


func _on_mods_tab_pressed() -> void:
    if settings_menu == null or not is_instance_valid(settings_menu):
        return

    _play_ui_click()

    var previous := int(settings_menu.get("_active_section"))
    var nav_buttons := _get_nav_buttons()
    if previous >= 0 and previous < nav_buttons.size() and settings_menu.has_method("_apply_tab_state") and not _mods_active:
        settings_menu.call("_apply_tab_state", nav_buttons[previous], previous, false)

    _mods_active = true

    for container in _get_section_containers():
        if container is Control:
            container.visible = (container == esp_tab_container)

    _apply_mods_tab_state(true)
    _reset_content_scroll()
    _show_description_text("Mod Settings", "Configure settings registered by installed ExtraStimulantsPlus mods.")
    _redraw_scroll_indicator()
    refresh_settings_ui()


func _populate_mod_settings() -> void:
    _clear_container(esp_tab_container)

    var registry := _get_registry()
    if registry == null or not registry.has_method("get_all_settings"):
        _add_empty_state("Settings registry unavailable.")
        return

    var all_settings: Dictionary = registry.get_all_settings()
    if all_settings.is_empty():
        _add_empty_state("No mod settings registered yet.")
        return

    var mod_ids := all_settings.keys()
    mod_ids.sort()

    for mod_id_value in mod_ids:
        var mod_id := String(mod_id_value)
        var settings: Dictionary = all_settings.get(mod_id, {})
        if settings.is_empty():
            continue

        _add_section_header(mod_id.to_upper())

        var keys := settings.keys()
        keys.sort()
        for key_value in keys:
            var key := String(key_value)
            var data: Dictionary = settings.get(key, {})
            _add_setting_row(mod_id, key, data)

        esp_tab_container.add_child(HSeparator.new())


func _add_empty_state(message: String) -> void:
    var label := Label.new()
    label.text = message
    label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    label.add_theme_font_size_override("font_size", 22)
    label.add_theme_color_override("font_color", Color(0.65, 0.65, 0.72, 1.0))
    esp_tab_container.add_child(label)


func _add_section_header(text: String) -> void:
    if settings_menu and is_instance_valid(settings_menu) and settings_menu.has_method("_make_section_header"):
        var header = settings_menu.call("_make_section_header", text, _native_style_anchor())
        if header is Control:
            esp_tab_container.add_child(header)
            return

    var container := VBoxContainer.new()
    container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    container.add_theme_constant_override("separation", 8)

    var label := Label.new()
    label.text = text
    label.add_theme_font_size_override("font_size", 32)
    label.add_theme_color_override("font_color", MODS_TAB_ACCENT)
    container.add_child(label)

    var rule := ColorRect.new()
    rule.custom_minimum_size = Vector2(0, 3)
    rule.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    rule.color = Color(0.27, 0.27, 0.27, 0.28)
    container.add_child(rule)

    esp_tab_container.add_child(container)


func _add_setting_row(mod_id: String, key: String, data: Dictionary) -> void:
    var row := HBoxContainer.new()
    row.add_theme_constant_override("separation", 16)
    row.size_flags_horizontal = Control.SIZE_EXPAND_FILL

    var options: Dictionary = data.get("options", {})
    var label_text := String(options.get("label", key.replace("_", " ").capitalize()))
    var description := String(options.get("description", ""))

    var label := Label.new()
    label.text = label_text
    label.add_theme_font_size_override("font_size", 22)
    label.add_theme_color_override("font_color", Color.WHITE)
    label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
    row.add_child(label)

    var control := _create_setting_control(mod_id, key, data)
    if control:
        row.add_child(control)
    else:
        var unsupported := Label.new()
        unsupported.text = "Unsupported"
        unsupported.add_theme_color_override("font_color", Color(0.65, 0.65, 0.72, 1.0))
        unsupported.size_flags_vertical = Control.SIZE_SHRINK_CENTER
        row.add_child(unsupported)

    esp_tab_container.add_child(row)
    _wire_mod_row_description(row, label_text, description)


func _create_setting_control(mod_id: String, key: String, data: Dictionary) -> Control:
    var setting_type := int(data.get("type", 0))
    var value: Variant = data.get("value", data.get("default", null))
    var options: Dictionary = data.get("options", {})

    match setting_type:
        TYPE_BOOL:
            return _create_bool_control(mod_id, key, bool(value))
        TYPE_INT:
            return _create_number_control(mod_id, key, data, true)
        TYPE_FLOAT:
            return _create_number_control(mod_id, key, data, false)
        TYPE_STRING:
            # If the schema declares a fixed `choices` array, render a real
            # dropdown instead of a free-form LineEdit. Lets mods expose
            # preset selectors (e.g. path-tracer presets) cleanly.
            var choices: Variant = options.get("choices", null)
            if choices is Array and not (choices as Array).is_empty():
                return _create_choice_control(mod_id, key, String(value), choices as Array)
            return _create_string_control(mod_id, key, String(value))
        _:
            return null


func _create_choice_control(mod_id: String, key: String, initial_value: String, choices: Array) -> OptionButton:
    var dropdown := OptionButton.new()
    dropdown.custom_minimum_size = Vector2(200, 36)
    dropdown.size_flags_horizontal = Control.SIZE_SHRINK_END
    var initial_index := 0
    for i in range(choices.size()):
        var label := String(choices[i])
        dropdown.add_item(label, i)
        if label == initial_value:
            initial_index = i
    dropdown.select(initial_index)
    dropdown.item_selected.connect(func(index: int):
        _set_registry_value(mod_id, key, String(choices[index]))
    )
    return dropdown


func _create_bool_control(mod_id: String, key: String, initial_state: bool) -> Button:
    var toggle := _create_native_toggle()
    if settings_menu and settings_menu.has_method("_set_toggle_value"):
        settings_menu.call("_set_toggle_value", toggle, initial_state)
    else:
        toggle.set_pressed_no_signal(initial_state)

    toggle.toggled.connect(func(on: bool):
        _set_registry_value(mod_id, key, on)
    )
    return toggle


func _create_number_control(mod_id: String, key: String, data: Dictionary, integer_only: bool) -> SpinBox:
    var options: Dictionary = data.get("options", {})
    var value: Variant = data.get("value", data.get("default", 0))

    var spin := SpinBox.new()
    spin.custom_minimum_size = Vector2(160, 36)
    spin.size_flags_horizontal = Control.SIZE_SHRINK_END
    spin.min_value = float(options.get("min", 0))
    spin.max_value = float(options.get("max", 100))
    spin.step = float(options.get("step", 1 if integer_only else 0.01))
    spin.value = float(value)

    spin.value_changed.connect(func(v: float):
        _set_registry_value(mod_id, key, int(round(v)) if integer_only else v)
    )
    return spin


func _create_string_control(mod_id: String, key: String, initial_value: String) -> LineEdit:
    var line_edit := LineEdit.new()
    line_edit.custom_minimum_size = Vector2(246, 36)
    line_edit.size_flags_horizontal = Control.SIZE_SHRINK_END
    line_edit.text = initial_value
    line_edit.text_submitted.connect(func(text: String):
        _set_registry_value(mod_id, key, text)
    )
    line_edit.focus_exited.connect(func():
        _set_registry_value(mod_id, key, line_edit.text)
    )
    return line_edit


func _create_native_toggle() -> Button:
    if settings_menu and is_instance_valid(settings_menu) and settings_menu.has_method("_make_pill_toggle"):
        var toggle = settings_menu.call("_make_pill_toggle", _native_style_anchor())
        if toggle is Button:
            return toggle

    var btn := Button.new()
    btn.toggle_mode = true
    btn.text = ""
    btn.custom_minimum_size = Vector2(77, 36)
    btn.focus_mode = Control.FOCUS_ALL
    return btn


func _wire_mod_row_description(row: Control, title: String, body: String) -> void:
    row.mouse_filter = Control.MOUSE_FILTER_PASS
    row.set_meta("hover_on", false)
    row.mouse_entered.connect(func():
        row.set_meta("hover_on", true)
        row.queue_redraw()
        _show_description_text(title, body)
    )
    row.mouse_exited.connect(func():
        row.set_meta("hover_on", false)
        row.queue_redraw()
    )
    row.draw.connect(_draw_row_hover.bind(row))


func _draw_row_hover(row: Control) -> void:
    if not row.get_meta("hover_on", false):
        return

    var bg_rect := Rect2(
        Vector2(-ROW_HOVER_LEFT_PADDING, 0),
        Vector2(row.size.x + ROW_HOVER_LEFT_PADDING, row.size.y)
    )
    row.draw_rect(bg_rect, Color(0, 0, 0, 0.5), true)

    var bar := Rect2(Vector2(-ROW_HOVER_LEFT_PADDING, 0), Vector2(ROW_HOVER_BAR_WIDTH, row.size.y))
    row.draw_rect(bar, MODS_TAB_ACCENT, true)


func _style_tab_button(btn: Button, active: bool) -> void:
    var bg := MODS_TAB_ACCENT if active else MODS_TAB_INACTIVE
    var fg := Color.BLACK if active else Color.WHITE
    var normal_sb := _make_tab_stylebox(bg)
    var hover_sb := _make_tab_stylebox(bg)
    if not active:
        hover_sb.border_color = MODS_TAB_ACCENT
        hover_sb.border_width_bottom = 2

    btn.add_theme_stylebox_override("normal", normal_sb)
    btn.add_theme_stylebox_override("hover", hover_sb)
    btn.add_theme_stylebox_override("pressed", normal_sb)
    btn.add_theme_stylebox_override("focus", hover_sb)
    btn.add_theme_color_override("font_color", fg)
    btn.add_theme_color_override("font_hover_color", fg)
    btn.add_theme_color_override("font_pressed_color", fg)
    btn.add_theme_color_override("font_focus_color", fg)


func _make_tab_stylebox(bg: Color) -> StyleBoxFlat:
    if settings_menu and is_instance_valid(settings_menu) and settings_menu.has_method("_make_tab_stylebox"):
        var style = settings_menu.call("_make_tab_stylebox", bg)
        if style is StyleBoxFlat:
            return style

    var sb := StyleBoxFlat.new()
    sb.bg_color = bg
    sb.content_margin_left = 16.0
    sb.content_margin_top = 8.0
    sb.content_margin_right = 16.0
    sb.content_margin_bottom = 8.0
    return sb


func _apply_mods_tab_state(active: bool) -> void:
    if _mods_button and is_instance_valid(_mods_button):
        _style_tab_button(_mods_button, active)


func _show_description_text(title: String, body: String) -> void:
    if settings_menu == null or not is_instance_valid(settings_menu):
        return

    var desc_title = settings_menu.get("_desc_title")
    var desc_body = settings_menu.get("_desc_body")
    if desc_title is Label:
        desc_title.text = title
    if desc_body is Label:
        desc_body.text = body


func _reset_content_scroll() -> void:
    var content_scroll = settings_menu.get("_content_scroll") if settings_menu else null
    if content_scroll is ScrollContainer:
        content_scroll.scroll_vertical = 0


func _redraw_scroll_indicator() -> void:
    if settings_menu == null or not is_instance_valid(settings_menu):
        return

    var previous_section := int(settings_menu.get("_active_section"))
    settings_menu.set("_active_section", _native_style_anchor())

    var indicator = settings_menu.get("_scroll_indicator")
    if indicator is Control:
        indicator.queue_redraw()

    settings_menu.set("_active_section", previous_section)


func _play_ui_click() -> void:
    var sfx := get_node_or_null("/root/UiSfxManager")
    if sfx and sfx.has_method("play_click"):
        sfx.play_click()


func _connect_registry() -> void:
    var registry := _get_registry()
    if registry == null:
        return

    _registry = registry

    var changed_cb := Callable(self, "_on_registry_setting_changed")
    if registry.has_signal("setting_changed") and not registry.is_connected("setting_changed", changed_cb):
        registry.connect("setting_changed", changed_cb)

    var registered_cb := Callable(self, "_on_registry_setting_registered")
    if registry.has_signal("setting_registered") and not registry.is_connected("setting_registered", registered_cb):
        registry.connect("setting_registered", registered_cb)


func _on_registry_setting_changed(_mod_id: String, _key: String, _value: Variant) -> void:
    refresh_settings_ui()


func _on_registry_setting_registered(_mod_id: String, _key: String, _data: Dictionary) -> void:
    refresh_settings_ui()


func _set_registry_value(mod_id: String, key: String, value: Variant) -> void:
    var registry := _get_registry()
    if registry and registry.has_method("set_value"):
        registry.set_value(mod_id, key, value)


func _get_registry() -> Node:
    if _registry and is_instance_valid(_registry):
        return _registry
    _registry = get_node_or_null("/root/ESPSettingsRegistry")
    return _registry


func _settings_menu_has_native_internals(menu: Control) -> bool:
    return _get_tab_bar(menu) != null and _get_content_vbox(menu) != null and _get_section_containers(menu).size() >= 4 and _get_nav_buttons(menu).size() >= 4


# Returns the index of the LAST native tab (i.e. excluding our injected MODS
# tab). Used as the style-anchor argument when calling the game's native
# `_make_section_header(text, index)` / `_make_pill_toggle(index)` so our UI
# matches the most-recently-styled native tab. Falls back to the historical
# value (3) if the menu structure can't be queried — the original hardcoded
# behavior.
func _native_style_anchor() -> int:
    var buttons := _get_nav_buttons()
    if buttons.is_empty():
        return NATIVE_STYLE_FALLBACK
    var last_native := buttons.size() - 1
    # If our own button is in the list, exclude it.
    if _mods_button and last_native >= 0 and buttons[last_native] == _mods_button:
        last_native -= 1
    return max(0, last_native)


func _get_tab_bar(menu: Control = null) -> HBoxContainer:
    if menu == null:
        menu = settings_menu
    if menu == null or not is_instance_valid(menu):
        return null
    var value = menu.get("_tab_bar_row")
    return value as HBoxContainer


func _get_content_vbox(menu: Control = null) -> VBoxContainer:
    if menu == null:
        menu = settings_menu
    if menu == null or not is_instance_valid(menu):
        return null
    var value = menu.get("_content_vbox")
    return value as VBoxContainer


func _get_section_containers(menu: Control = null) -> Array:
    if menu == null:
        menu = settings_menu
    if menu == null or not is_instance_valid(menu):
        return []
    var value = menu.get("_section_containers")
    if value is Array:
        return value
    return []


func _get_nav_buttons(menu: Control = null) -> Array:
    if menu == null:
        menu = settings_menu
    if menu == null or not is_instance_valid(menu):
        return []
    var value = menu.get("_nav_buttons")
    if value is Array:
        return value
    return []


func _clear_container(container: Container) -> void:
    if container == null or not is_instance_valid(container):
        return
    for child in container.get_children():
        container.remove_child(child)
        child.queue_free()


func _log_warn(message: String) -> void:
    var logger := get_node_or_null("/root/ESPLogger")
    if logger and logger.has_method("warn"):
        logger.warn(message)
    else:
        push_warning("[ESP Settings UI] " + message)

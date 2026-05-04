extends Node

# ESP Settings UI Generator - Framework Owned
# Clones native game UI components to build mod settings menus that look 100% native.

var settings_menu: Control
var esp_tab_container: VBoxContainer

func hook_settings_menu(menu: Control) -> void:
    settings_menu = menu
    
    # 1. Create a new "MODS" category in the settings tabs
    var tab_bar = settings_menu.find_child("_tab_bar_row", true, false)
    if tab_bar:
        _inject_mods_tab(tab_bar)

func _inject_mods_tab(tab_bar: HBoxContainer) -> void:
    if tab_bar.has_node("ModsTabButton"): return
    
    # We clone an existing tab button to get the style exactly right
    var source_btn = tab_bar.get_child(0)
    if not source_btn: return
    
    var btn = source_btn.duplicate()
    btn.name = "ModsTabButton"
    btn.text = "MODS"
    tab_bar.add_child(btn)
    
    # 2. Create the content container for mods
    var content_vbox = settings_menu.find_child("_content_vbox", true, false)
    if content_vbox:
        esp_tab_container = VBoxContainer.new()
        esp_tab_container.name = "ModsSettingsContainer"
        esp_tab_container.visible = false
        content_vbox.add_child(esp_tab_container)
        
        # We need to register this new section in the menu's internal arrays
        if "_section_containers" in settings_menu:
            settings_menu._section_containers.append(esp_tab_container)
            
        # Hook the button to switch to our new container
        var new_index = settings_menu._section_containers.size() - 1
        btn.pressed.connect(func(): settings_menu._active_section = new_index; _refresh_visibility())
        
        _populate_mod_settings()

func _refresh_visibility() -> void:
    # This mimics the native menu's tab switching logic
    if not settings_menu or not esp_tab_container: return
    for i in range(settings_menu._section_containers.size()):
        settings_menu._section_containers[i].visible = (i == settings_menu._active_section)

func _populate_mod_settings() -> void:
    var registry = get_node_or_null("/root/ESP/ESPSettingsRegistry")
    if not registry: return
    
    var all_settings = registry.get_all_settings()
    for mod_id in all_settings:
        var mod_label = Label.new()
        mod_label.text = mod_id.to_upper()
        mod_label.add_theme_font_size_override("font_size", 18)
        mod_label.add_theme_color_override("font_color", Color(1.0, 0.83, 0.12)) # Native Yellow
        esp_tab_container.add_child(mod_label)
        
        var settings = all_settings[mod_id]
        for key in settings:
            _add_setting_row(mod_id, key, settings[key])
        
        esp_tab_container.add_child(HSeparator.new())

func _add_setting_row(mod_id: String, key: String, data: Dictionary) -> void:
    # We use the native _make_toggle_row logic from the game's settings_menu.gd
    # but we have to replicate it here manually to ensure it's "clean"
    
    var row = HBoxContainer.new()
    row.add_theme_constant_override("separation", 16)
    row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    
    var lbl = Label.new()
    lbl.text = key.replace("_", " ").capitalize()
    lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    row.add_child(lbl)
    
    # We try to use the game's internal methods if accessible, otherwise replicate
    if data["type"] == TYPE_BOOL:
        var toggle = _create_native_toggle(data["value"])
        toggle.toggled.connect(func(on): 
            var registry = get_node_or_null("/root/ESP/ESPSettingsRegistry")
            if registry: registry.set_value(mod_id, key, on)
        )
        row.add_child(toggle)
    
    esp_tab_container.add_child(row)

func _create_native_toggle(initial_state: bool) -> Button:
    # Replicating the "PillToggle" from the game
    var btn = Button.new()
    btn.toggle_mode = true
    btn.button_pressed = initial_state
    btn.custom_minimum_size = Vector2(77, 36)
    # Styles would be copied from settings_menu.gd constants
    return btn

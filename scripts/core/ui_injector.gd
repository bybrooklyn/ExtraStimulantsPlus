extends Node

# The UiInjector handles dynamic patching of game scenes at runtime.
# This avoids the need to overwrite the game's original .gd scripts.

func _enter_tree():
    get_tree().node_added.connect(_on_node_added)

func _on_node_added(node: Node):
    # Detect Main Menu
    if node.name == "MainMenu" and node is Control:
        _patch_main_menu(node)
    
    # Detect Settings Menu
    elif node.name == "SettingsMenu" or (node.get_parent() and node.get_parent().name == "SettingsMenu"):
        _patch_settings_menu(node)

func _patch_main_menu(menu: Control):
    # Find containers
    var menu_container = menu.get_node_or_null("MenuContainer")
    if not menu_container:
        # Fallback search
        for child in menu.find_children("*", "VBoxContainer", true, false):
            if child.name == "MenuContainer":
                menu_container = child
                break

    if menu_container:
        _inject_custom_maps_button(menu_container)
    
    _inject_active_badge(menu)

func _inject_custom_maps_button(container: VBoxContainer):
    if container.has_node("CustomMapsButton"): return
    
    var btn = Button.new()
    btn.name = "CustomMapsButton"
    btn.text = "CUSTOM MAPS"
    btn.custom_minimum_size = Vector2(410, 55)
    btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
    
    # Logic for clicking
    btn.pressed.connect(func():
        if get_node_or_null("/root/UiSfxManager"): 
            get_node("/root/UiSfxManager").play_click()
        get_node("/root/GameContext").set_mode(2) # EDITOR mode
        get_tree().change_scene_to_file("res://scenes/level_editor/level_browser.tscn")
    )
    
    container.add_child(btn)
    
    # Move before Settings
    var settings_btn = container.get_node_or_null("SettingsButton")
    if settings_btn:
        container.move_child(btn, settings_btn.get_index())
        
    # Toggle visibility
    var settings = get_node_or_null("/root/ExtraStimulantsPlusSettings")
    if settings:
        btn.visible = settings.should_show_editor_entry()


func _inject_active_badge(menu: Control):
    if menu.has_node("ExtraStimulantsPlusBadge"): return
    
    var box = VBoxContainer.new()
    box.name = "ExtraStimulantsPlusBadge"
    box.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
    box.offset_left = -420
    box.offset_top = 18
    box.offset_right = -20
    box.offset_bottom = 120
    menu.add_child(box)
    
    var active_label = Label.new()
    active_label.text = "EXTRASTIMULANTSPLUS ACTIVE"
    active_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    active_label.add_theme_font_size_override("font_size", 24)
    active_label.add_theme_color_override("font_color", Color(0.1, 1.0, 0.4, 1.0))
    active_label.add_theme_constant_override("outline_size", 4)
    active_label.add_theme_color_override("font_outline_color", Color.BLACK)
    box.add_child(active_label)
    
    var settings = get_node_or_null("/root/ExtraStimulantsPlusSettings")
    if settings:
        var version_label = Label.new()
        version_label.text = "Build " + settings.get_version()
        version_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
        version_label.add_theme_font_size_override("font_size", 18)
        version_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4, 0.95))
        box.add_child(version_label)
        
        var mod_loader = get_node_or_null("/root/ModLoader")
        if mod_loader and settings.should_show_mod_status():
            var num_mods = mod_loader.loaded_mods.size()
            var status_label = Label.new()
            status_label.text = "%d mod%s loaded" % [num_mods, "" if num_mods == 1 else "s"]
            status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
            status_label.add_theme_font_size_override("font_size", 14)
            status_label.add_theme_color_override("font_color", Color(0.72, 0.72, 0.78, 0.9))
            box.add_child(status_label)

func _patch_settings_menu(node: Node):
    # This is more complex as it depends on the internal structure of the settings menu
    # We look for the gameplay VBoxContainer
    var gameplay_box = node.get("_gameplay_vbox") if "_gameplay_vbox" in node else null
    if not gameplay_box:
        gameplay_box = node.find_child("GameplayVBox", true, false)
        
    if gameplay_box and not gameplay_box.has_node("ExtraStimulantsPlusRow"):
        _inject_settings_row(gameplay_box, node)

func _inject_settings_row(container: VBoxContainer, settings_menu: Control):
    container.add_child(HSeparator.new())
    
    var title = Label.new()
    title.text = "EXTRASTIMULANTSPLUS"
    title.add_theme_font_size_override("font_size", 18)
    title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
    container.add_child(title)
    
    var row = HBoxContainer.new()
    row.name = "ExtraStimulantsPlusRow"
    
    var label = Label.new()
    label.text = "Mod settings"
    label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    label.add_theme_font_size_override("font_size", 22)
    row.add_child(label)
    
    var button = Button.new()
    button.text = "Open"
    button.custom_minimum_size = Vector2(120, 36)
    button.pressed.connect(_open_mod_settings.bind(settings_menu))
    row.add_child(button)
    
    container.add_child(row)

func _open_mod_settings(parent: Control):
    var settings = get_node_or_null("/root/ExtraStimulantsPlusSettings")
    if not settings: return
    
    if get_node_or_null("/root/UiSfxManager"):
        get_node("/root/UiSfxManager").play_click()

    var dialog = AcceptDialog.new()
    dialog.title = "ExtraStimulantsPlus Settings"
    dialog.size = Vector2i(520, 260)

    var root = VBoxContainer.new()
    root.add_theme_constant_override("separation", 12)
    dialog.add_child(root)

    var create_toggle = func(lbl, initial, cb):
        var r = HBoxContainer.new()
        var l = Label.new()
        l.text = lbl
        l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        l.add_theme_font_size_override("font_size", 18)
        r.add_child(l)
        var t = CheckButton.new()
        t.button_pressed = initial
        t.toggled.connect(cb)
        r.add_child(t)
        return r

    root.add_child(create_toggle.call("Show version badge", settings.should_show_version_badge(), func(on):
        settings.set_show_version_badge(on)
    ))
    root.add_child(create_toggle.call("Show mod count", settings.should_show_mod_status(), func(on):
        settings.set_show_mod_status(on)
    ))
    root.add_child(create_toggle.call("Prefer .somap exports", settings.prefers_somap(), func(on):
        settings.set_prefer_somap(on)
    ))
    
    parent.add_child(dialog)
    dialog.popup_centered()

extends AcceptDialog

# The ModManagerMenu provides a UI list of all loaded and blacklisted mods.
# It allows users to toggle mods on/off (requires restart).

var _list_container: VBoxContainer

func _init():
    title = "In-Game Mod Manager"
    size = Vector2i(700, 500)
    
    var root = VBoxContainer.new()
    root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    root.add_theme_constant_override("separation", 10)
    add_child(root)
    
    var info = Label.new()
    info.text = "Note: Disabling/Enabling mods requires a game restart."
    info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    info.add_theme_color_override("font_color", Color(1.0, 0.8, 0.4))
    root.add_child(info)
    
    var scroll = ScrollContainer.new()
    scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
    root.add_child(scroll)
    
    _list_container = VBoxContainer.new()
    _list_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    scroll.add_child(_list_container)

func _ready():
    refresh()

func refresh():
    for child in _list_container.get_children():
        child.queue_free()
        
    var mod_loader = get_node_or_null("/root/ModLoader")
    if not mod_loader: return
    
    # Show active mods
    for mod in mod_loader.loaded_mods:
        _add_mod_item(mod, true)
        
    # Show blacklisted mods (if any)
    # We need to scan the directory again to find mods that aren't loaded
    # For now, let's just show the active ones.

func _add_mod_item(mod: Dictionary, is_active: bool):
    var panel = PanelContainer.new()
    _list_container.add_child(panel)
    
    var hbox = HBoxContainer.new()
    hbox.add_theme_constant_override("separation", 15)
    panel.add_child(hbox)
    
    var vinfo = VBoxContainer.new()
    vinfo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    hbox.add_child(vinfo)
    
    var name_lbl = Label.new()
    name_lbl.text = mod.get("name", "Unnamed Mod") + " v" + mod.get("version", "0.0.0")
    name_lbl.add_theme_font_size_override("font_size", 20)
    name_lbl.add_theme_color_override("font_color", Color(0.1, 1.0, 0.4))
    vinfo.add_child(name_lbl)
    
    var auth_lbl = Label.new()
    auth_lbl.text = "Author: " + mod.get("author", "Unknown")
    auth_lbl.add_theme_font_size_override("font_size", 14)
    auth_lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.8))
    vinfo.add_child(auth_lbl)
    
    var desc_lbl = Label.new()
    desc_lbl.text = mod.get("description", "No description provided.")
    desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    desc_lbl.add_theme_font_size_override("font_size", 16)
    vinfo.add_child(desc_lbl)
    
    var btn_vbox = VBoxContainer.new()
    btn_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
    hbox.add_child(btn_vbox)
    
    var mod_id = mod.get("id", "unknown")
    if mod_id != "extrastimulants_plus" and mod_id != "core":
        var toggle_btn = Button.new()
        toggle_btn.text = "DISABLE" if is_active else "ENABLE"
        toggle_btn.custom_minimum_size = Vector2(100, 40)
        toggle_btn.pressed.connect(func():
            var mod_loader = get_node("/root/ModLoader")
            mod_loader.set_blacklisted(mod_id, is_active)
            refresh()
        )
        btn_vbox.add_child(toggle_btn)

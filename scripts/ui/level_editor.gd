extends Control

var _library: ObstacleDefinitionLibrary
var _sequence: Array = []
var _selected_index: int = -1
var _current_theme_name: String = "tornado"
var _current_song_path: String = "res://audio/Song-1.wav"

@onready var path_edit = %PathEdit
@onready var load_btn = %LoadBtn
@onready var save_btn = %SaveBtn
@onready var play_test_btn = Button.new()
@onready var back_btn = %BackBtn
@onready var help_btn = %HelpBtn
@onready var library_list = %LibraryList
@onready var add_btn = %AddBtn
@onready var create_obs_btn = Button.new()
@onready var timeline_container = %TimelineContainer
@onready var inspector_props = %InspectorProps
@onready var timeline_scroll = %TimelineScroll

const PIXELS_PER_RING: float = 5.0
const ENTRY_WIDTH: float = 40.0
const ENTRY_HEIGHT: float = 40.0

var _dragging_entry: Control = null
var _drag_start_x: float = 0.0

func _ready():
    _library = ObstacleDefinitionLibrary.new()
    _library.setup(10.0)
    _library.load_all()
    
    _refresh_library_list()
    
    create_obs_btn.text = "Create Custom Obstacle"
    create_obs_btn.add_theme_font_size_override("font_size", 16)
    create_obs_btn.pressed.connect(_on_create_obstacle_pressed)
    add_btn.get_parent().add_child(create_obs_btn)
    
    play_test_btn.text = " Play Test "
    play_test_btn.add_theme_font_size_override("font_size", 18)
    play_test_btn.pressed.connect(_on_play_test_pressed)
    save_btn.get_parent().add_child(play_test_btn)
    save_btn.get_parent().move_child(play_test_btn, save_btn.get_index() + 1)
        
    load_btn.pressed.connect(_on_load_pressed)
    save_btn.pressed.connect(_on_save_pressed)
    add_btn.pressed.connect(_on_add_pressed)
    back_btn.pressed.connect(_on_back_pressed)
    help_btn.pressed.connect(_on_help_pressed)
    
    timeline_container.gui_input.connect(_on_timeline_gui_input)
    
    # Default to the shareable .somap format unless the user disables it.
    path_edit.text = _get_default_level_path()

func _refresh_library_list():
    library_list.clear()
    for name in _library.get_builtin_names():
        library_list.add_item(name)
    for def in _library.get_custom_definitions():
        library_list.add_item("custom:" + def.id)

func _on_create_obstacle_pressed():
    if UiSfxManager: UiSfxManager.play_click()
    var creator = preload("res://scenes/level_editor/obstacle_creator.tscn").instantiate()
    add_child(creator)
    creator.tree_exited.connect(func():
        _library.load_all()
        _refresh_library_list()
    )

func _on_help_pressed():
    if UiSfxManager: UiSfxManager.play_click()
    var popup = AcceptDialog.new()
    popup.title = "Level Editor Guide"
    popup.dialog_text = """
    Timeline:
    - Drag blocks left/right to move them.
    - Click a block to edit properties in the Inspector.
    - Click empty space to see Global Level Settings (Theme/Song).
    
    Obstacles:
    - Select from Library and click 'Add' to place.
    - Use 'Create Custom' to draw your own shapes.
    
    Saving:
    - Export files to 'user://custom_levels/name.somap' to share them.
    - Legacy '.json' files are still supported for import.
    """
    add_child(popup)
    popup.popup_centered()

func _on_back_pressed():
    if UiSfxManager:
        UiSfxManager.play_back()
    GameContext.set_mode(GameContext.GameMode.MENU)
    get_tree().change_scene_to_file("res://scenes/main.tscn")

func _on_load_pressed():
    if UiSfxManager: UiSfxManager.play_click()
    var path = _normalize_level_path(path_edit.text, false)
    if path == "": return
    path_edit.text = path
    _sequence = ObstacleSequenceSerializer.load_from_path(path)
    var meta = ObstacleSequenceSerializer.load_metadata_from_path(path)
    _current_theme_name = meta.get("theme", "tornado")
    _current_song_path = meta.get("song", "res://audio/Song-1.wav")
    _rebuild_timeline()
    _select_entry(-1)

func _on_save_pressed():
    if UiSfxManager: UiSfxManager.play_click()
    var path = _normalize_level_path(path_edit.text, true)
    if path == "": return
    path_edit.text = path
    
    # Sort sequence by ring position before saving
    _sequence.sort_custom(func(a, b): return a.ring_position < b.ring_position)
    var meta = {
        "theme": _current_theme_name,
        "song": _current_song_path
    }
    ObstacleSequenceSerializer.save_to_path(_sequence, path, meta)
    _rebuild_timeline()

func _on_play_test_pressed():
    if UiSfxManager: UiSfxManager.play_click()
    
    # Save to temp location
    var temp_path = "user://custom_levels/_editor_test.json"
    _sequence.sort_custom(func(a, b): return a.ring_position < b.ring_position)
    var meta = {
        "theme": _current_theme_name,
        "song": _current_song_path,
        "is_test": true
    }
    ObstacleSequenceSerializer.save_to_path(_sequence, temp_path, meta)
    
    # We need to construct a dynamic LevelData/StageDef
    var level_def = CampaignLevelDef.new()
    level_def.level_name = "Editor Test"
    
    var stage = StageDef.new()
    stage.stage_name = "Testing..."
    
    # Load Theme
    var theme_res = load("res://resources/themes/" + _current_theme_name + ".tres")
    if theme_res:
        stage.theme = theme_res
        
    # Load Song
    var song_res: AudioStream = null
    if _current_song_path.begins_with("user://"):
        var loader = load("res://scripts/core/external_audio_loader.gd")
        if loader:
            song_res = loader.load_external_audio(_current_song_path)
    else:
        song_res = load(_current_song_path)
        
    if song_res:
        stage.song = song_res
    
    var substage = SubStageDef.new()
    substage.obstacle_sequence_path = temp_path
    
    stage.substages.append(substage)
    level_def.stages.append(stage)
    
    # Inject this custom level into the CampaignManager
    if CampaignManager:
        CampaignManager._cached_all_levels = [level_def]
        CampaignManager.current_level = level_def
        CampaignManager.current_stage_index = 0
    
    GameContext.set_mode(GameContext.GameMode.CAMPAIGN)
    get_tree().change_scene_to_file("res://scenes/game.tscn")

func _on_add_pressed():
    if UiSfxManager: UiSfxManager.play_click()
    var selected = library_list.get_selected_items()
    if selected.is_empty(): return
    
    var type_id = library_list.get_item_text(selected[0])
    var new_entry = ScriptedObstacleEntry.new()
    new_entry.type_id = type_id
    
    # Place at the end
    var max_ring = 0
    for e in _sequence:
        if e.ring_position > max_ring:
            max_ring = e.ring_position
    new_entry.ring_position = max_ring + 20
    
    _sequence.append(new_entry)
    _rebuild_timeline()
    _select_entry(_sequence.size() - 1)

func _rebuild_timeline():
    for c in timeline_container.get_children():
        c.queue_free()
        
    var max_x = 1000.0
    
    for i in range(_sequence.size()):
        var entry = _sequence[i]
        var btn = ColorRect.new()
        btn.color = Color(0.2, 0.6, 0.8) if i != _selected_index else Color(0.8, 0.8, 0.2)
        btn.size = Vector2(ENTRY_WIDTH, ENTRY_HEIGHT)
        
        var x_pos = float(entry.ring_position) * PIXELS_PER_RING
        btn.position = Vector2(x_pos, 50.0)
        
        if x_pos + 500 > max_x:
            max_x = x_pos + 500
            
        var lbl = Label.new()
        lbl.text = entry.type_id
        lbl.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
        lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
        lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
        lbl.clip_text = true
        lbl.add_theme_font_size_override("font_size", 10)
        btn.add_child(lbl)
        
        btn.gui_input.connect(_on_entry_gui_input.bind(btn, i))
        timeline_container.add_child(btn)
        
    timeline_container.custom_minimum_size.x = max_x

func _on_entry_gui_input(event: InputEvent, btn: Control, index: int):
    if event is InputEventMouseButton:
        if event.button_index == MOUSE_BUTTON_LEFT:
            if event.pressed:
                _select_entry(index)
                _dragging_entry = btn
                _drag_start_x = event.global_position.x - btn.position.x
            else:
                _dragging_entry = null
    elif event is InputEventMouseMotion and _dragging_entry == btn:
        var new_x = event.global_position.x - _drag_start_x
        new_x = max(0, new_x)
        btn.position.x = new_x
        _sequence[index].ring_position = int(new_x / PIXELS_PER_RING)
        _build_inspector(index) # Update UI values
        
func _on_timeline_gui_input(event: InputEvent):
    if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
        _select_entry(-1)

func _select_entry(index: int):
    _selected_index = index
    _rebuild_timeline()
    _build_inspector(index)

func _build_inspector(index: int):
    for c in inspector_props.get_children():
        c.queue_free()
        
    if index < 0:
        # Global Level Settings
        var header = Label.new()
        header.text = "Level Settings"
        header.add_theme_font_size_override("font_size", 20)
        inspector_props.add_child(header)
        
        var themes = _get_available_themes()
        _add_prop_ui("Theme Name", _current_theme_name, func(v): _current_theme_name = v, themes)
        
        var songs = _get_available_songs()
        _add_prop_ui("Song Path", _current_song_path, func(v): _current_song_path = v, songs)
        
        var hint = Label.new()
        hint.text = "Custom music can be added to user://custom_music/"
        hint.add_theme_font_size_override("font_size", 12)
        hint.modulate = Color(0.7, 0.7, 0.7)
        inspector_props.add_child(hint)
        return

func _get_available_themes() -> Array[String]:
    var themes: Array[String] = []
    var dir = DirAccess.open("res://resources/themes/")
    if dir:
        dir.list_dir_begin()
        var file_name = dir.get_next()
        while file_name != "":
            if not dir.current_is_dir() and file_name.ends_with(".tres"):
                themes.append(file_name.get_basename())
            file_name = dir.get_next()
        dir.list_dir_end()
    themes.sort()
    return themes

func _get_available_songs() -> Array[String]:
    var songs: Array[String] = []
    # Built-in songs
    var dir = DirAccess.open("res://audio/")
    if dir:
        dir.list_dir_begin()
        var file_name = dir.get_next()
        while file_name != "":
            if not dir.current_is_dir() and file_name.ends_with(".wav"):
                songs.append("res://audio/" + file_name)
            file_name = dir.get_next()
        dir.list_dir_end()
        
    # Custom songs
    var custom_music_loader = load("res://scripts/core/external_audio_loader.gd")
    if custom_music_loader:
        songs.append_array(custom_music_loader.get_custom_music_list())
        
    songs.sort()
    return songs
        
    if index >= _sequence.size():
        return
        
    var entry = _sequence[index]
    
    _add_prop_ui("Ring Position", entry.ring_position, func(v):
        entry.ring_position = int(v)
        _rebuild_timeline()
    )
    
    _add_prop_ui("Type ID", entry.type_id, func(v):
        entry.type_id = v
        _rebuild_timeline()
    )
    
    _add_prop_ui("Cruise Gap (sec)", entry.cruise_gap_sec, func(v): entry.cruise_gap_sec = float(v))
    _add_prop_ui("Starting Angle", entry.starting_angle, func(v): entry.starting_angle = float(v))
    _add_prop_ui("Rotation Speed", entry.rotation_speed, func(v): entry.rotation_speed = float(v))
    
    var del_btn = Button.new()
    del_btn.text = "Delete Entry"
    del_btn.add_theme_font_size_override("font_size", 18)
    del_btn.custom_minimum_size.y = 40
    del_btn.pressed.connect(func():
        if UiSfxManager: UiSfxManager.play_click()
        _sequence.remove_at(index)
        _select_entry(-1)
    )
    inspector_props.add_child(del_btn)

func _add_prop_ui(label_text: String, value, callback: Callable, options: Array = []):
    var hbox = HBoxContainer.new()
    var lbl = Label.new()
    lbl.text = label_text
    lbl.custom_minimum_size.x = 180
    lbl.add_theme_font_size_override("font_size", 16)
    hbox.add_child(lbl)
    
    if not options.is_empty():
        var opt = OptionButton.new()
        opt.size_flags_horizontal = SIZE_EXPAND_FILL
        for i in range(options.size()):
            opt.add_item(options[i])
            if str(options[i]) == str(value):
                opt.select(i)
        opt.item_selected.connect(func(idx): callback.call(options[idx]))
        hbox.add_child(opt)
    elif value is String:
        var edit = LineEdit.new()
        edit.text = value
        edit.size_flags_horizontal = SIZE_EXPAND_FILL
        edit.text_changed.connect(callback)
        hbox.add_child(edit)
    else:
        var spin = SpinBox.new()
        spin.min_value = -10000
        spin.max_value = 10000
        spin.step = 0.1 if value is float else 1
        spin.value = value
        spin.size_flags_horizontal = SIZE_EXPAND_FILL
        spin.value_changed.connect(callback)
        hbox.add_child(spin)
        
    inspector_props.add_child(hbox)


func _get_default_level_path() -> String:
    var extension: String = "somap"
    if ExtraStimulantsPlusSettings and not ExtraStimulantsPlusSettings.prefers_somap():
        extension = "json"
    return "user://custom_levels/custom_map.%s" % extension


func _normalize_level_path(path: String, for_save: bool) -> String:
    var trimmed: String = path.strip_edges()
    if trimmed.is_empty():
        return _get_default_level_path() if for_save else ""
    var ext: String = trimmed.get_extension().to_lower()
    if ext in ["json", "somap"]:
        return trimmed
    return trimmed + (".somap" if ExtraStimulantsPlusSettings == null or ExtraStimulantsPlusSettings.prefers_somap() else ".json")

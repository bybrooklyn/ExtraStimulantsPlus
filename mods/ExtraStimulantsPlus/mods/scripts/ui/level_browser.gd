extends Control

@onready var level_list = %LevelList
@onready var play_btn = %PlayBtn
@onready var back_btn = %BackBtn
@onready var empty_label = %EmptyLabel
@onready var theme_label = %ThemeLabel
@onready var song_label = %SongLabel
@onready var obstacle_count_label = %ObstacleCountLabel

var _custom_sequences: Array[String] = []
var _selected_path: String = ""

func _ready():
    if UiSfxManager: UiSfxManager.play_click()
    
    play_btn.pressed.connect(_on_play_pressed)
    back_btn.pressed.connect(_on_back_pressed)
    level_list.item_selected.connect(_on_level_selected)
    
    play_btn.disabled = true
    _scan_for_custom_levels()

func _scan_for_custom_levels():
    level_list.clear()
    _custom_sequences.clear()
    
    var dir = DirAccess.open("user://")
    if dir:
        if not dir.dir_exists("custom_levels"):
            dir.make_dir("custom_levels")
            
        var levels_dir = DirAccess.open("user://custom_levels")
        if levels_dir:
            levels_dir.list_dir_begin()
            var file_name = levels_dir.get_next()
            while file_name != "":
                if not levels_dir.current_is_dir() and (file_name.ends_with(".json") or file_name.ends_with(".somap")):
                    var full_path = "user://custom_levels/" + file_name
                    _custom_sequences.append(full_path)
                    level_list.add_item(file_name.get_basename())
                file_name = levels_dir.get_next()
            levels_dir.list_dir_end()
            
    if _custom_sequences.is_empty():
        empty_label.visible = true
        level_list.visible = false
    else:
        empty_label.visible = false
        level_list.visible = true

func _on_level_selected(index: int):
    if index >= 0 and index < _custom_sequences.size():
        _selected_path = _custom_sequences[index]
        play_btn.disabled = false
        if UiSfxManager: UiSfxManager.play_hover()
        
        var meta = ObstacleSequenceSerializer.load_metadata_from_path(_selected_path)
        var sequence = ObstacleSequenceSerializer.load_from_path(_selected_path)
        
        theme_label.text = "Theme: " + meta.get("theme", "tornado")
        var s_path = meta.get("song", "res://audio/Song-1.wav")
        song_label.text = "Song: " + s_path.get_file()
        obstacle_count_label.text = "Obstacles: " + str(sequence.size())

func _on_play_pressed():
    if _selected_path == "": return
    if UiSfxManager: UiSfxManager.play_click()
    
    var meta = ObstacleSequenceSerializer.load_metadata_from_path(_selected_path)
    var theme_name = meta.get("theme", "tornado")
    var song_path = meta.get("song", "res://audio/Song-1.wav")
    var runtime_sequence_path: String = _selected_path

    if _selected_path.get_extension().to_lower() == "somap":
        var runtime_meta: Dictionary = meta.duplicate(true)
        var runtime_sequence: Array = ObstacleSequenceSerializer.load_from_path(_selected_path)
        runtime_sequence_path = "user://custom_levels/_runtime_selected.json"
        ObstacleSequenceSerializer.save_to_json(runtime_sequence, runtime_sequence_path, runtime_meta)
    
    # We need to construct a dynamic LevelData/StageDef for the custom sequence
    var level_def = CampaignLevelDef.new()
    level_def.level_name = _selected_path.get_file().get_basename()
    
    var stage = StageDef.new()
    stage.stage_name = "Custom Stage"
    
    # Load Theme
    var theme_res = load("res://resources/themes/" + theme_name + ".tres")
    if theme_res:
        stage.theme = theme_res

    # Load Song
    var song_res: AudioStream = null
    if song_path.begins_with("user://"):
        var loader = load("res://scripts/core/external_audio_loader.gd")
        if loader:
            song_res = loader.load_external_audio(song_path)
    else:
        song_res = load(song_path)

    if song_res:
        stage.song = song_res
    
    var substage = SubStageDef.new()
    substage.obstacle_sequence_path = runtime_sequence_path
    
    stage.substages.append(substage)
    level_def.stages.append(stage)
    
    # Inject this custom level into the CampaignManager
    if CampaignManager:
        CampaignManager._cached_all_levels = [level_def]
        CampaignManager.current_level = level_def
        CampaignManager.current_stage_index = 0
    
    GameContext.set_mode(GameContext.GameMode.CAMPAIGN)
    get_tree().change_scene_to_file("res://scenes/game.tscn")

func _on_back_pressed():
    if UiSfxManager: UiSfxManager.play_back()
    GameContext.set_mode(GameContext.GameMode.MENU)
    get_tree().change_scene_to_file("res://scenes/main.tscn")

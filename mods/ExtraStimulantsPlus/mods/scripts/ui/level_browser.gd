extends Control

@onready var level_list = %LevelList
@onready var play_btn = %PlayBtn
@onready var back_btn = %BackBtn
@onready var empty_label = %EmptyLabel
@onready var theme_label = %ThemeLabel
@onready var song_label = %SongLabel
@onready var obstacle_count_label = %ObstacleCountLabel

var _custom_records: Array[Dictionary] = []
var _selected_record: Dictionary = {}


func _ready():
    if UiSfxManager: UiSfxManager.play_click()
    
    play_btn.pressed.connect(_on_play_pressed)
    back_btn.pressed.connect(_on_back_pressed)
    level_list.item_selected.connect(_on_level_selected)
    
    play_btn.disabled = true
    _scan_for_custom_levels()


func _scan_for_custom_levels():
    level_list.clear()
    _custom_records.clear()

    var api := get_node_or_null("/root/ESP")
    if api and api.level_registry and api.level_registry.has_method("scan_custom_levels"):
        api.level_registry.scan_custom_levels()
        if api.level_registry.has_method("get_custom_level_records"):
            _custom_records = api.level_registry.get_custom_level_records()

    if _custom_records.is_empty():
        empty_label.visible = true
        level_list.visible = false
        return

    empty_label.visible = false
    level_list.visible = true
    for record in _custom_records:
        var title := String(record.get("display_title", record.get("title", record.get("file_name", "Custom Level"))))
        if not bool(record.get("valid", false)):
            title += " (invalid)"
        level_list.add_item(title)


func _on_level_selected(index: int):
    if index < 0 or index >= _custom_records.size():
        return

    _selected_record = _custom_records[index]
    play_btn.disabled = not bool(_selected_record.get("valid", false))
    if UiSfxManager: UiSfxManager.play_hover()

    theme_label.text = "Theme: " + String(_selected_record.get("theme", "tornado"))
    var s_path := String(_selected_record.get("song", "res://audio/Song-1.wav"))
    song_label.text = "Song: " + s_path.get_file()
    var prefix := ""
    if String(_selected_record.get("campaign_title", "")).strip_edges() != "":
        prefix = "Campaign: %s\n" % String(_selected_record.get("campaign_title", ""))
    obstacle_count_label.text = "%sObstacles: %d" % [prefix, int(_selected_record.get("obstacle_count", 0))]


func _on_play_pressed():
    var selected_path := String(_selected_record.get("path", ""))
    if selected_path.is_empty():
        return
    if UiSfxManager: UiSfxManager.play_click()

    var api := get_node_or_null("/root/ESP")
    if api and api.has_method("play_custom_level_path"):
        api.play_custom_level_path(selected_path, {"practice_mode": true})
        return

    push_warning("Level Browser: ESP campaign adapter unavailable; cannot play custom level")


func _on_back_pressed():
    if UiSfxManager: UiSfxManager.play_back()
    GameContext.set_mode(GameContext.GameMode.MENU)
    get_tree().change_scene_to_file("res://scenes/main.tscn")

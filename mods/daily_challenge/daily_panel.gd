extends Control

# Modal-ish panel built in code — no .tscn dependency. The mod entrypoint
# constructs one of these on click, populates it via show_for_pool(...), then
# adds it to the scene tree. Closing happens via the close button or the
# play_requested signal (the entrypoint frees us once the level launches).

signal play_requested(seed_value, options)
signal closed

var _content: VBoxContainer
var _date_label: Label
var _title_label: Label
var _description_label: Label
var _streak_label: Label
var _status_label: Label
var _play_button: Button
var _close_button: Button

var _seed_value: int = 0
var _options: Dictionary = {}
var _has_payload: bool = false


func _ready() -> void:
    set_anchors_preset(Control.PRESET_FULL_RECT)
    mouse_filter = Control.MOUSE_FILTER_STOP

    var dim := ColorRect.new()
    dim.color = Color(0, 0, 0, 0.65)
    dim.set_anchors_preset(Control.PRESET_FULL_RECT)
    dim.mouse_filter = Control.MOUSE_FILTER_STOP
    add_child(dim)

    var center := CenterContainer.new()
    center.set_anchors_preset(Control.PRESET_FULL_RECT)
    add_child(center)

    var panel := PanelContainer.new()
    panel.custom_minimum_size = Vector2(520, 360)
    center.add_child(panel)

    var margin := MarginContainer.new()
    margin.add_theme_constant_override("margin_left", 24)
    margin.add_theme_constant_override("margin_right", 24)
    margin.add_theme_constant_override("margin_top", 20)
    margin.add_theme_constant_override("margin_bottom", 20)
    panel.add_child(margin)

    _content = VBoxContainer.new()
    _content.add_theme_constant_override("separation", 12)
    margin.add_child(_content)

    var heading := Label.new()
    heading.text = "DAILY CHALLENGE"
    heading.add_theme_font_size_override("font_size", 28)
    heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _content.add_child(heading)

    _date_label = Label.new()
    _date_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _date_label.modulate = Color(0.7, 0.85, 1.0, 1.0)
    _content.add_child(_date_label)

    var spacer := Control.new()
    spacer.custom_minimum_size = Vector2(0, 8)
    _content.add_child(spacer)

    _title_label = Label.new()
    _title_label.add_theme_font_size_override("font_size", 22)
    _title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _content.add_child(_title_label)

    _description_label = Label.new()
    _description_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _description_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    _description_label.modulate = Color(0.85, 0.85, 0.85, 1.0)
    _content.add_child(_description_label)

    _streak_label = Label.new()
    _streak_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _content.add_child(_streak_label)

    _status_label = Label.new()
    _status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    _status_label.modulate = Color(0.6, 1.0, 0.6, 1.0)
    _content.add_child(_status_label)

    var buttons := HBoxContainer.new()
    buttons.alignment = BoxContainer.ALIGNMENT_CENTER
    buttons.add_theme_constant_override("separation", 16)
    _content.add_child(buttons)

    _play_button = Button.new()
    _play_button.text = "PLAY"
    _play_button.custom_minimum_size = Vector2(160, 48)
    _play_button.pressed.connect(_on_play_pressed)
    buttons.add_child(_play_button)

    _close_button = Button.new()
    _close_button.text = "Close"
    _close_button.custom_minimum_size = Vector2(120, 48)
    _close_button.pressed.connect(_on_close_pressed)
    buttons.add_child(_close_button)


# Called by the entrypoint with the procedurally generated daily challenge
# meta + the player's streak state. `generated` is the dict returned by
# ESP.campaign.generate_sequence (see scripts/core/level_generator.gd).
func populate_generated(date_str: String, seed_value: int, generated: Dictionary, options: Dictionary, streak: int, completed_today: bool) -> void:
    _seed_value = seed_value
    _options = options
    _has_payload = true
    _date_label.text = "UTC %s" % date_str

    var meta: Dictionary = generated.get("meta", {})
    _title_label.text = String(meta.get("title", "Daily Challenge"))
    _description_label.text = String(meta.get("description", ""))
    _streak_label.text = "Current streak: %d %s" % [streak, "day" if streak == 1 else "days"]
    if completed_today:
        _status_label.text = "✓ Completed today"
        _play_button.text = "REPLAY"
    else:
        _status_label.text = ""
        _play_button.text = "PLAY"
    _play_button.disabled = false


func _on_play_pressed() -> void:
    if not _has_payload:
        return
    play_requested.emit(_seed_value, _options)


func _on_close_pressed() -> void:
    closed.emit()
    queue_free()

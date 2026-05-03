extends Control


@onready var title_control = $TitleContainer
@onready var debug_panel = $DebugPanel
@onready var menu_container = $MenuContainer


var _hover_tweens = {}


const _BUTTON_PALETTE: = {
    "CampaignButton": {
        "accent": Color(1.0, 1.0, 0.0, 1.0), 
        "glow": Color(1.0, 1.0, 0.0, 1.0), 
        "box_bg": Color(0.102, 0.102, 0.0, 0.4), 
    }, 
    "EditorButton": {
        "accent": Color(0.933, 0.573, 0.055, 1.0), 
        "glow": Color(0.933, 0.573, 0.055, 1.0), 
        "box_bg": Color(0.145, 0.086, 0.0, 0.4), 
    }, 
    "ZenButton": {
        "accent": Color(0.482, 0.059, 0.776, 1.0), 
        "glow": Color(0.647, 0.141, 1.0, 1.0), 
        "box_bg": Color(0.098, 0.0, 0.165, 0.4), 
    }, 
    "SettingsButton": {
        "accent": Color(0.667, 0.91, 0.149, 1.0), 
        "glow": Color(0.745, 1.0, 0.192, 1.0), 
        "box_bg": Color(0.149, 0.216, 0.0, 0.4), 
    }, 
    "QuitButton": {
        "accent": Color(0.039, 0.757, 0.808, 1.0), 
        "glow": Color(0.161, 0.937, 0.992, 1.0), 
        "box_bg": Color(0.0, 0.161, 0.173, 0.4), 
    }, 
    "CustomMapsButton": {
        "accent": Color(0.1, 0.8, 0.3, 1.0), 
        "glow": Color(0.2, 1.0, 0.4, 1.0), 
        "box_bg": Color(0.0, 0.2, 0.1, 0.4), 
    }, 
}

var _funnel_main_menu_sent: bool = false

func _ready():
    _setup_debug_ui()

    call_deferred("_setup_buttons")
    _set_steam_rich_presence_menu()

    if not _funnel_main_menu_sent:
        _funnel_main_menu_sent = true
        var ga: = get_node_or_null("/root/GameAnalytics")
        if ga and ga.has_method("record_funnel_milestone"):
            ga.record_funnel_milestone("main_menu_reached")

    var zen_btn = menu_container.get_node_or_null("ZenButton")
    if zen_btn:
        zen_btn.visible = false
    var editor_btn = menu_container.get_node_or_null("EditorButton")
    if editor_btn:
        editor_btn.visible = ExtraStimulantsPlusSettings == null or ExtraStimulantsPlusSettings.should_show_editor_entry()
    if OS.has_feature("demo"):
        for btn_name in ["EndlessButton", "ZenButton", "HighScoresButton"]:
            var btn = menu_container.get_node_or_null(btn_name)
            if btn:
                btn.visible = false

    _ensure_custom_maps_button()
    _add_extra_stimulants_plus_badge()


func _on_custom_maps_pressed():
    if UiSfxManager: UiSfxManager.play_click()
    GameContext.set_mode(GameContext.GameMode.EDITOR)
    get_tree().change_scene_to_file("res://scenes/level_editor/level_browser.tscn")


func _ensure_custom_maps_button() -> void:
    var custom_btn: Button = menu_container.get_node_or_null("CustomMapsButton")
    if custom_btn == null:
        custom_btn = Button.new()
        custom_btn.name = "CustomMapsButton"
        custom_btn.text = "CUSTOM MAPS"
        custom_btn.custom_minimum_size = Vector2(410, 55)
        custom_btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
        custom_btn.pressed.connect(_on_custom_maps_pressed)
        menu_container.add_child(custom_btn)

    var settings_btn := menu_container.get_node_or_null("SettingsButton")
    if settings_btn != null:
        menu_container.move_child(custom_btn, settings_btn.get_index())


func _add_extra_stimulants_plus_badge() -> void:
    if not ExtraStimulantsPlusSettings:
        return
    var existing := get_node_or_null("ExtraStimulantsPlusBadge")
    if existing:
        existing.queue_free()

    var box := VBoxContainer.new()
    box.name = "ExtraStimulantsPlusBadge"
    box.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
    box.offset_left = -420
    box.offset_top = 18
    box.offset_right = -20
    box.offset_bottom = 90
    add_child(box)

    if ExtraStimulantsPlusSettings.should_show_version_badge():
        var version_label := Label.new()
        version_label.text = "ExtraStimulantsPlus %s" % ExtraStimulantsPlusSettings.get_version()
        version_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
        version_label.add_theme_font_size_override("font_size", 18)
        version_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4, 0.95))
        box.add_child(version_label)

    if ExtraStimulantsPlusSettings.should_show_mod_status():
        var mod_loader = get_node_or_null("/root/ModLoader")
        var num_mods: int = mod_loader.loaded_mods.size() if mod_loader else 0
        var status_label := Label.new()
        status_label.text = "%d mod%s loaded" % [num_mods, "" if num_mods == 1 else "s"]
        status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
        status_label.add_theme_font_size_override("font_size", 14)
        status_label.add_theme_color_override("font_color", Color(0.72, 0.72, 0.78, 0.9))
        box.add_child(status_label)

func _set_steam_rich_presence_menu() -> void :
    var sm = get_node_or_null("/root/SteamManager")
    if sm and sm.is_steam_available() and sm.rich_presence and sm.rich_presence.has_method("set_rich_presence"):
        sm.rich_presence.set_rich_presence("status", "In Main Menu")

func _setup_buttons():







    for child in menu_container.get_children():
        if child is Button:
            child.pivot_offset = child.size / 2.0
            var palette: Dictionary = _BUTTON_PALETTE.get(child.name, {})
            if not palette.is_empty():
                var normal_sb: = MainMenuButtonStyleBox.new()
                normal_sb.accent_color = palette["accent"]
                normal_sb.accent_glow_color = palette["glow"]
                normal_sb.box_bg_color = palette["box_bg"]


                var hover_sb: = MainMenuButtonStyleBox.new()
                hover_sb.accent_color = palette["accent"]
                hover_sb.accent_glow_color = palette["glow"]



                hover_sb.box_bg_color = palette["accent"]
                hover_sb.border_alpha = 0.13
                hover_sb.box_right_ratio = 0.8007
                hover_sb.box_top_ratio = 0.0579
                hover_sb.box_bottom_ratio = 0.9421

                child.add_theme_stylebox_override("normal", normal_sb)
                child.add_theme_stylebox_override("hover", hover_sb)
                child.add_theme_stylebox_override("focus", hover_sb)
                child.add_theme_stylebox_override("pressed", hover_sb)



                child.add_theme_color_override("font_color", Color.WHITE)
                child.add_theme_color_override("font_hover_color", Color.BLACK)
                child.add_theme_color_override("font_focus_color", Color.BLACK)
                child.add_theme_color_override("font_pressed_color", Color.BLACK)
                child.add_theme_color_override("font_hover_pressed_color", Color.BLACK)
            child.set_meta("base_scale", Vector2.ONE)
            child.mouse_entered.connect(_on_button_hover.bind(child))
            child.mouse_exited.connect(_on_button_exit.bind(child))
            child.focus_entered.connect(_on_button_hover.bind(child))
            child.focus_exited.connect(_on_button_exit.bind(child))

func _on_button_hover(btn: Button):
    UiSfxManager.play_hover()

    if _hover_tweens.has(btn) and _hover_tweens[btn]:
        _hover_tweens[btn].kill()

    var tween = create_tween()
    _hover_tweens[btn] = tween
    tween.set_parallel(true)
    tween.set_trans(Tween.TRANS_EXPO)
    tween.set_ease(Tween.EASE_OUT)


    tween.tween_property(btn, "scale", Vector2(1.0488, 1.0488), 0.1)





func _on_button_exit(btn: Button):

    if _hover_tweens.has(btn) and _hover_tweens[btn]:
        _hover_tweens[btn].kill()

    var tween = create_tween()
    _hover_tweens[btn] = tween
    tween.set_parallel(true)
    tween.set_trans(Tween.TRANS_ELASTIC)
    tween.set_ease(Tween.EASE_OUT)

    tween.tween_property(btn, "scale", Vector2(1.0, 1.0), 0.4)
    tween.tween_property(btn, "rotation", 0.0, 0.4)









func _on_play_pressed():
    UiSfxManager.play_click()

    _start_game_sequence(GameContext.GameMode.CAMPAIGN)

func _on_campaign_pressed():
    UiSfxManager.play_click()
    var ui_manager = get_parent() as UIManager
    if ui_manager:
        ui_manager.show_level_select(true)
    else:

        EventBus.game_state_changed.emit("CampaignSelect")

func _on_endless_pressed():
    UiSfxManager.play_click()
    _start_game_sequence(GameContext.GameMode.ENDLESS)

func _on_zen_pressed():
    UiSfxManager.play_click()
    _start_game_sequence(GameContext.GameMode.ZEN, "res://scenes/dev/visual_gym_performance.tscn")

func _on_editor_pressed():
    UiSfxManager.play_click()


    GameContext.set_mode(GameContext.GameMode.EDITOR)
    get_tree().change_scene_to_file("res://scenes/level_editor/level_editor.tscn")

func _on_high_scores_pressed():
    UiSfxManager.play_click()
    var panel = get_node_or_null("HighScoresPanel")
    var list_node = get_node_or_null("HighScoresPanel/MarginContainer/VBoxContainer/ScrollContainer/HighScoresList")
    var summary_label = get_node_or_null("HighScoresPanel/MarginContainer/VBoxContainer/SummaryLabel")
    if panel and list_node:
        menu_container.visible = false
        panel.visible = true
        var details_panel = get_node_or_null("%RunDetailsPanel")
        var compare_panel = get_node_or_null("%ComparePanel")
        if details_panel: details_panel.visible = false
        if compare_panel: compare_panel.visible = false
        _refresh_high_scores(list_node, summary_label)

func _on_high_scores_back_pressed():
    UiSfxManager.play_back()
    _close_compare_panel()
    _close_run_details_panel()
    var panel = get_node_or_null("HighScoresPanel")
    if panel:
        panel.visible = false
        menu_container.visible = true

func _update_compare_runs_button() -> void :
    var btn = get_node_or_null("%CompareRunsButton")
    if btn:
        btn.disabled = _compare_levels.is_empty()

func _on_compare_runs_pressed() -> void :
    var scroll = get_node_or_null("HighScoresPanel/MarginContainer/VBoxContainer/ScrollContainer")
    var back_btn = get_node_or_null("%HighScoresBackButton")
    var compare_btn = get_node_or_null("%CompareRunsButton")
    var panel = get_node_or_null("%ComparePanel")
    var level_opt = get_node_or_null("%CompareLevelOption")
    if not panel or not level_opt or _compare_levels.is_empty():
        return
    if scroll: scroll.visible = false
    if back_btn: back_btn.visible = false
    if compare_btn: compare_btn.visible = false
    panel.visible = true
    level_opt.clear()
    for i in range(_compare_levels.size()):
        var entry = _compare_levels[i]
        level_opt.add_item(entry.display_name, i)
    level_opt.select(0)
    _fill_compare_run_options(0)
    var result_container = get_node_or_null("%CompareResultContainer")
    if result_container:
        for c in result_container.get_children():
            c.queue_free()

func _on_run_row_pressed(compare_level_index: int, run_index_in_history: int) -> void :
    var scroll = get_node_or_null("HighScoresPanel/MarginContainer/VBoxContainer/ScrollContainer")
    var back_btn = get_node_or_null("%HighScoresBackButton")
    var compare_btn = get_node_or_null("%CompareRunsButton")
    var details_panel = get_node_or_null("%RunDetailsPanel")
    if not details_panel or compare_level_index < 0 or compare_level_index >= _compare_levels.size():
        return
    _run_details_compare_level_index = compare_level_index
    var runs: Array = _compare_levels[compare_level_index].runs
    run_index_in_history = clampi(run_index_in_history, 0, runs.size() - 1)
    _run_details_run_index = run_index_in_history
    if scroll: scroll.visible = false
    if back_btn: back_btn.visible = false
    if compare_btn: compare_btn.visible = false
    details_panel.visible = true
    _fill_run_details_panel(compare_level_index, run_index_in_history)
    var run_details_compare_btn = get_node_or_null("%RunDetailsCompareButton")
    if run_details_compare_btn:
        run_details_compare_btn.visible = runs.size() >= 2

func _fill_run_details_panel(compare_level_index: int, run_index_in_history: int) -> void :
    var title_l = get_node_or_null("%RunDetailsTitle")
    var content = get_node_or_null("%RunDetailsContent")
    if compare_level_index < 0 or compare_level_index >= _compare_levels.size() or not content:
        return
    var entry = _compare_levels[compare_level_index]
    var level_name: String = entry.get("display_name", "—")
    var runs: Array = entry.runs
    run_index_in_history = clampi(run_index_in_history, 0, runs.size() - 1)
    var run: Dictionary = runs[run_index_in_history]
    if title_l:
        var run_num: int = runs.size() - run_index_in_history
        title_l.text = "Run details — %s (Run #%d)" % [level_name, run_num]
    for c in content.get_children():
        c.queue_free()
    var score_val: int = run.get("score", 0)
    var time_val: float = run.get("time", 0.0)
    var slide_val: float = run.get("longest_slide", 0.0)
    var stars_val: int = run.get("stars", 0)
    var completed: bool = run.get("completed", false)
    var rows = [
        ["Score", str(score_val)], 
        ["Time", _format_time_hm(time_val)], 
        ["Longest slide", _format_slide_s(slide_val)], 
        ["Stars", "%d ★" % stars_val], 
        ["Result", "✓ Completed" if completed else "✗ Failed"]
    ]
    for r in rows:
        var row = HBoxContainer.new()
        row.add_theme_constant_override("separation", 16)
        var name_l = Label.new()
        name_l.text = r[0] + ":"
        name_l.add_theme_font_size_override("font_size", 16)
        name_l.add_theme_color_override("font_color", Color(0.55, 0.55, 0.65))
        name_l.custom_minimum_size.x = 140
        row.add_child(name_l)
        var value_l = Label.new()
        value_l.text = r[1]
        value_l.add_theme_font_size_override("font_size", 18)
        value_l.add_theme_color_override("font_color", Color(0.9, 0.9, 0.95))
        if r[0] == "Result":
            value_l.add_theme_color_override("font_color", Color(0.3, 0.9, 0.4) if completed else Color(0.9, 0.35, 0.3))
        row.add_child(value_l)
        content.add_child(row)

func _on_run_details_back_pressed() -> void :
    _close_run_details_panel()

func _close_run_details_panel() -> void :
    var scroll = get_node_or_null("HighScoresPanel/MarginContainer/VBoxContainer/ScrollContainer")
    var back_btn = get_node_or_null("%HighScoresBackButton")
    var compare_btn = get_node_or_null("%CompareRunsButton")
    var details_panel = get_node_or_null("%RunDetailsPanel")
    if scroll: scroll.visible = true
    if back_btn: back_btn.visible = true
    if compare_btn: compare_btn.visible = true
    if details_panel: details_panel.visible = false

func _on_run_details_compare_pressed() -> void :
    var details_panel = get_node_or_null("%RunDetailsPanel")
    var compare_panel = get_node_or_null("%ComparePanel")
    var level_opt = get_node_or_null("%CompareLevelOption")
    var run_a_opt = get_node_or_null("%CompareRunAOption")
    var run_b_opt = get_node_or_null("%CompareRunBOption")
    if not compare_panel or not level_opt or not run_a_opt or not run_b_opt or _run_details_compare_level_index < 0 or _run_details_compare_level_index >= _compare_levels.size():
        return
    if details_panel: details_panel.visible = false
    compare_panel.visible = true
    level_opt.clear()
    for i in range(_compare_levels.size()):
        var entry = _compare_levels[i]
        level_opt.add_item(entry.display_name, i)
    level_opt.select(_run_details_compare_level_index)
    _fill_compare_run_options(_run_details_compare_level_index)
    var runs: Array = _compare_levels[_run_details_compare_level_index].runs
    var run_index_in_history: int = clampi(_run_details_run_index, 0, runs.size() - 1)
    var run_a_item_index: int = runs.size() - 1 - run_index_in_history
    run_a_opt.select(run_a_item_index)
    var run_b_idx: int = (run_index_in_history + 1) % runs.size() if runs.size() > 1 else run_index_in_history
    var run_b_item_index: int = runs.size() - 1 - run_b_idx
    run_b_opt.select(run_b_item_index)
    var result_container = get_node_or_null("%CompareResultContainer")
    if result_container:
        for c in result_container.get_children():
            c.queue_free()

func _fill_compare_run_options(level_index: int) -> void :
    var run_a_opt = get_node_or_null("%CompareRunAOption")
    var run_b_opt = get_node_or_null("%CompareRunBOption")
    if level_index < 0 or level_index >= _compare_levels.size() or not run_a_opt or not run_b_opt:
        return
    var runs: Array = _compare_levels[level_index].runs
    run_a_opt.clear()
    run_b_opt.clear()
    for i in range(runs.size() - 1, -1, -1):
        var run: Dictionary = runs[i]
        var run_num: int = runs.size() - i
        var score_s: String = str(run.get("score", 0))
        var time_s: String = _format_time_hm(run.get("time", 0.0))
        var stars_s: String = "%d★" % run.get("stars", 0)
        var res_s: String = "✓" if run.get("completed", false) else "✗"
        var label: String = "Run #%d – %s – %s – %s – %s" % [run_num, score_s, time_s, stars_s, res_s]
        run_a_opt.add_item(label, i)
        run_b_opt.add_item(label, i)
    if runs.size() > 0:
        run_a_opt.select(0)
        run_b_opt.select(mini(1, runs.size() - 1))

func _on_compare_level_selected(index: int) -> void :
    _fill_compare_run_options(index)

func _on_compare_do_pressed() -> void :
    var level_opt = get_node_or_null("%CompareLevelOption")
    var run_a_opt = get_node_or_null("%CompareRunAOption")
    var run_b_opt = get_node_or_null("%CompareRunBOption")
    var result_container = get_node_or_null("%CompareResultContainer")
    if not level_opt or not run_a_opt or not run_b_opt or not result_container or _compare_levels.is_empty():
        return
    for c in result_container.get_children():
        c.queue_free()
    var level_idx: int = level_opt.get_selected_id()
    if level_idx < 0 or level_idx >= _compare_levels.size():
        return
    var runs: Array = _compare_levels[level_idx].runs
    var run_a_idx: int = run_a_opt.get_selected_id() if run_a_opt.get_selected_id() >= 0 else 0
    var run_b_idx: int = run_b_opt.get_selected_id() if run_b_opt.get_selected_id() >= 0 else 0
    run_a_idx = clampi(run_a_idx, 0, runs.size() - 1)
    run_b_idx = clampi(run_b_idx, 0, runs.size() - 1)
    var run_a: Dictionary = runs[run_a_idx]
    var run_b: Dictionary = runs[run_b_idx]
    var score_a: int = run_a.get("score", 0)
    var score_b: int = run_b.get("score", 0)
    var time_a: float = run_a.get("time", 0.0)
    var time_b: float = run_b.get("time", 0.0)
    var slide_a: float = run_a.get("longest_slide", 0.0)
    var slide_b: float = run_b.get("longest_slide", 0.0)
    var stars_a: int = run_a.get("stars", 0)
    var stars_b: int = run_b.get("stars", 0)
    var completed_a: bool = run_a.get("completed", false)
    var completed_b: bool = run_b.get("completed", false)
    var header_row = HBoxContainer.new()
    header_row.add_theme_constant_override("separation", 16)
    for header_text in ["Metric", "Run A", "Run B", "Diff"]:
        var h = Label.new()
        h.text = header_text
        h.add_theme_font_size_override("font_size", 12)
        h.add_theme_color_override("font_color", Color(0.55, 0.55, 0.65))
        h.custom_minimum_size.x = 90 if header_text != "Metric" else 100
        if header_text == "Metric":
            h.custom_minimum_size.x = 100
        header_row.add_child(h)
    result_container.add_child(header_row)
    var rows = [
        ["Score", str(score_a), str(score_b), str(score_b - score_a)], 
        ["Time", _format_time_hm(time_a), _format_time_hm(time_b), _format_time_diff(time_b - time_a)], 
        ["Longest slide", _format_slide_s(slide_a), _format_slide_s(slide_b), _format_slide_diff(slide_b - slide_a)], 
        ["Stars", "%d ★" % stars_a, "%d ★" % stars_b, "%+d" % (stars_b - stars_a)], 
        ["Result", "Completed" if completed_a else "Failed", "Completed" if completed_b else "Failed", ""]
    ]
    for r in rows:
        var row = HBoxContainer.new()
        row.add_theme_constant_override("separation", 16)
        var name_l = Label.new()
        name_l.text = r[0]
        name_l.custom_minimum_size.x = 100
        name_l.add_theme_font_size_override("font_size", 14)
        row.add_child(name_l)
        var a_l = Label.new()
        a_l.text = r[1]
        a_l.custom_minimum_size.x = 90
        a_l.add_theme_font_size_override("font_size", 13)
        row.add_child(a_l)
        var b_l = Label.new()
        b_l.text = r[2]
        b_l.custom_minimum_size.x = 90
        b_l.add_theme_font_size_override("font_size", 13)
        row.add_child(b_l)
        var diff_l = Label.new()
        diff_l.text = r[3]
        diff_l.custom_minimum_size.x = 70
        diff_l.add_theme_font_size_override("font_size", 12)
        var diff_val: String = r[3]
        if diff_val.length() > 0 and diff_val != "0" and diff_val != "0s":
            var is_time: bool = (r[0] == "Time")
            var b_better: bool = (is_time and diff_val.begins_with("-")) or ( not is_time and (diff_val.begins_with("+") or diff_val.to_int() > 0))
            if b_better:
                diff_l.add_theme_color_override("font_color", Color(0.3, 0.85, 0.4))
            else:
                diff_l.add_theme_color_override("font_color", Color(0.85, 0.4, 0.3))
        row.add_child(diff_l)
        result_container.add_child(row)

func _format_time_diff(sec: float) -> String:
    if abs(sec) < 0.005:
        return "0s"
    return "%+.2fs" % sec

func _format_slide_diff(sec: float) -> String:
    if abs(sec) < 0.005:
        return "0s"
    return "%+.2fs" % sec

func _on_compare_close_pressed() -> void :
    _close_compare_panel()

func _close_compare_panel() -> void :
    var scroll = get_node_or_null("HighScoresPanel/MarginContainer/VBoxContainer/ScrollContainer")
    var back_btn = get_node_or_null("%HighScoresBackButton")
    var compare_btn = get_node_or_null("%CompareRunsButton")
    var panel = get_node_or_null("%ComparePanel")
    if scroll: scroll.visible = true
    if back_btn: back_btn.visible = true
    if compare_btn: compare_btn.visible = true
    if panel: panel.visible = false

func _format_time_hm(seconds: float) -> String:
    if seconds <= 0.0:
        return "—"
    var m = int(seconds / 60.0)
    var s = fmod(seconds, 60.0)
    return "%d:%05.2f" % [m, s]

func _format_slide_s(seconds: float) -> String:
    if seconds <= 0.0:
        return "—"
    return "%.2fs" % seconds

func _refresh_high_scores(list_container: VBoxContainer, summary_label: Label) -> void :
    for child in list_container.get_children():
        child.queue_free()
    var save_data = CampaignManager.current_save_data if CampaignManager else null
    if not save_data:
        if summary_label:
            summary_label.text = "No save data."
        return
    var total_completions = save_data.total_levels_completed
    var total_attempts = 0
    var all_levels: = CampaignLevelLoader.load_all_levels()
    if all_levels.is_empty():
        if summary_label:
            summary_label.text = "Levels completed: %d" % total_completions
        return
    _compare_levels.clear()
    var header = _make_high_score_header()
    list_container.add_child(header)
    for level_def in all_levels:
        for stage_idx in range(level_def.get_stage_count()):
            var stage: StageDef = level_def.get_stage(stage_idx)
            var display_name: = "%s - %s" % [level_def.level_name, stage.stage_name] if stage and not stage.stage_name.is_empty() else "%s - Stage %d" % [level_def.level_name, stage_idx + 1]
            var stats: LevelStats = CampaignManager.get_stage_stats(level_def, stage_idx)
            total_attempts += stats.total_attempts
            var row = _make_high_score_row(display_name, stats)
            list_container.add_child(row)
            var history: Array = stats.run_history if stats else []
            var compare_level_index: = -1
            if history.size() >= 1:
                _compare_levels.append({
                    "level_id": level_def.get_stage_id(stage_idx), 
                    "display_name": display_name, 
                    "runs": history.duplicate()
                })
                compare_level_index = _compare_levels.size() - 1
            _add_run_history_rows(list_container, display_name, stats, compare_level_index)
    if summary_label:
        summary_label.text = "Levels completed: %d  |  Total attempts: %d" % [total_completions, total_attempts]
    _update_compare_runs_button()

func _make_high_score_header() -> Control:
    var row = HBoxContainer.new()
    row.add_theme_constant_override("separation", 12)
    var labels = ["LEVEL", "SCORE", "TIME", "SLIDE", "STARS", "W/L"]
    var widths = [0, 90, 72, 56, 44, 70]
    for i in range(labels.size()):
        var l = Label.new()
        l.text = labels[i]
        l.add_theme_font_size_override("font_size", 14)
        l.add_theme_color_override("font_color", Color(0.55, 0.55, 0.65))
        if i == 0:
            l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        else:
            l.custom_minimum_size.x = widths[i]
        row.add_child(l)
    return row

func _make_high_score_row(display_name: String, stats: LevelStats) -> Control:
    var row = HBoxContainer.new()
    row.add_theme_constant_override("separation", 12)
    var name_l = Label.new()
    name_l.text = display_name
    name_l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    name_l.add_theme_font_size_override("font_size", 18)
    row.add_child(name_l)
    var score_l = Label.new()
    score_l.text = str(stats.high_score)
    score_l.custom_minimum_size.x = 90
    score_l.add_theme_font_size_override("font_size", 16)
    row.add_child(score_l)
    var time_l = Label.new()
    time_l.text = _format_time_hm(stats.fastest_time)
    time_l.custom_minimum_size.x = 72
    time_l.add_theme_font_size_override("font_size", 14)
    time_l.add_theme_color_override("font_color", Color(0.75, 0.75, 0.85))
    row.add_child(time_l)
    var slide_l = Label.new()
    slide_l.text = _format_slide_s(stats.longest_slide_seconds)
    slide_l.custom_minimum_size.x = 56
    slide_l.add_theme_font_size_override("font_size", 14)
    slide_l.add_theme_color_override("font_color", Color(0.75, 0.75, 0.85))
    row.add_child(slide_l)
    var stars_l = Label.new()
    stars_l.text = "%d ★" % stats.best_stars
    stars_l.custom_minimum_size.x = 44
    stars_l.add_theme_font_size_override("font_size", 16)
    row.add_child(stars_l)
    var attempts_l = Label.new()
    attempts_l.text = "%d / %d" % [stats.total_completions, stats.total_attempts]
    attempts_l.custom_minimum_size.x = 70
    attempts_l.add_theme_font_size_override("font_size", 14)
    attempts_l.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7))
    row.add_child(attempts_l)
    return row

const RUN_HISTORY_DISPLAY_MAX = 30

var _compare_levels: Array = []
var _run_details_compare_level_index: int = -1
var _run_details_run_index: int = -1

func _add_run_history_header(list_container: VBoxContainer, level_name: String) -> void :
    var section_l = Label.new()
    section_l.text = "Run history: %s (full details below)" % level_name
    section_l.add_theme_font_size_override("font_size", 12)
    section_l.add_theme_color_override("font_color", Color(0.5, 0.55, 0.7))
    list_container.add_child(section_l)
    var row = HBoxContainer.new()
    row.add_theme_constant_override("separation", 12)
    var sub_labels = ["#", "Score", "Time", "Longest slide", "Stars", "Result"]
    var sub_widths = [32, 90, 72, 88, 44, 52]
    for j in range(sub_labels.size()):
        var l = Label.new()
        l.text = sub_labels[j]
        l.add_theme_font_size_override("font_size", 11)
        l.add_theme_color_override("font_color", Color(0.45, 0.45, 0.55))
        if j == 0:
            l.custom_minimum_size.x = 28 + sub_widths[0]
        else:
            l.custom_minimum_size.x = sub_widths[j]
        row.add_child(l)
    list_container.add_child(row)

func _add_run_history_rows(list_container: VBoxContainer, display_name: String, stats: LevelStats, compare_level_index: int = -1) -> void :
    var history: Array = stats.run_history if stats else []
    if history.is_empty():
        return
    _add_run_history_header(list_container, display_name)
    var start = maxi(0, history.size() - RUN_HISTORY_DISPLAY_MAX)
    for i in range(history.size() - 1, start - 1, -1):
        var run: Dictionary = history[i]
        var score_val: int = run.get("score", 0)
        var time_val: float = run.get("time", 0.0)
        var slide_val: float = run.get("longest_slide", 0.0)
        var completed: bool = run.get("completed", false)
        var row = HBoxContainer.new()
        row.add_theme_constant_override("separation", 12)
        var indent = Control.new()
        indent.custom_minimum_size.x = 28
        row.add_child(indent)
        var run_l = Label.new()
        run_l.text = "#%d" % (history.size() - i)
        run_l.custom_minimum_size.x = 32
        run_l.add_theme_font_size_override("font_size", 12)
        run_l.add_theme_color_override("font_color", Color(0.5, 0.5, 0.6))
        row.add_child(run_l)
        var score_l = Label.new()
        score_l.text = str(score_val)
        score_l.custom_minimum_size.x = 90
        score_l.add_theme_font_size_override("font_size", 12)
        row.add_child(score_l)
        var time_l = Label.new()
        time_l.text = _format_time_hm(time_val)
        time_l.custom_minimum_size.x = 72
        time_l.add_theme_font_size_override("font_size", 12)
        time_l.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7))
        row.add_child(time_l)
        var slide_l = Label.new()
        slide_l.text = _format_slide_s(slide_val)
        slide_l.custom_minimum_size.x = 88
        slide_l.add_theme_font_size_override("font_size", 12)
        slide_l.add_theme_color_override("font_color", Color(0.6, 0.6, 0.7))
        row.add_child(slide_l)
        var stars_val: int = run.get("stars", 0)
        var stars_l = Label.new()
        stars_l.text = "%d ★" % stars_val
        stars_l.custom_minimum_size.x = 44
        stars_l.add_theme_font_size_override("font_size", 12)
        row.add_child(stars_l)
        var result_l = Label.new()
        result_l.text = "✓ Completed" if completed else "✗ Failed"
        result_l.custom_minimum_size.x = 52
        result_l.add_theme_font_size_override("font_size", 14)
        result_l.add_theme_color_override("font_color", Color(0.3, 0.9, 0.4) if completed else Color(0.9, 0.35, 0.3))
        row.add_child(result_l)
        if compare_level_index >= 0:
            var run_btn = Button.new()
            run_btn.flat = true
            run_btn.custom_minimum_size.y = 32
            row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
            row.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
            run_btn.add_child(row)
            run_btn.pressed.connect(_on_run_row_pressed.bind(compare_level_index, i))
            list_container.add_child(run_btn)
        else:
            list_container.add_child(row)

func _start_game_sequence(mode: GameContext.GameMode, target_scene: String = ""):

    menu_container.mouse_filter = Control.MOUSE_FILTER_IGNORE


    var main_tween = create_tween()
    main_tween.set_parallel(true)


    main_tween.tween_property(menu_container, "modulate:a", 0.0, 1.0)\
.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
    main_tween.tween_property(title_control, "modulate:a", 0.0, 1.0)\
.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

    if debug_panel and debug_panel.visible:
        main_tween.tween_property(debug_panel, "modulate:a", 0.0, 0.5)



    main_tween.tween_property(self, "_cam_rotation_angles", Vector3(0, 0, 0), 3.0)\
.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


    var player = get_tree().current_scene.get_node_or_null("PlayerController") as PlayerController
    var current_s = player.current_vertical_speed if player else 0.0
    var target_s = 150.0


    main_tween.tween_method( func(v): EventBus.speed_changed.emit(v), current_s, target_s, 3.5)\
.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


    if target_scene != "":

        var fader = _get_or_create_fader()

        main_tween.tween_property(fader, "color:a", 1.0, 1.0).set_delay(2.5)


        main_tween.tween_callback( func():
            GameContext.set_mode(mode)
            get_tree().change_scene_to_file(target_scene)
        ).set_delay(3.5)
    else:


        main_tween.tween_callback( func():
            GameContext.set_mode(mode)
            var game = get_tree().current_scene
            if game and game.has_node("StateMachine"):
                game.get_node("StateMachine").change_state("Playing")
            else:
                push_error("MainMenu: Could not find Game StateMachine!")
        ).set_delay(2.0)

func _get_or_create_fader() -> ColorRect:
    var fader = get_node_or_null("Fader")
    if not fader:
        fader = ColorRect.new()
        fader.name = "Fader"
        fader.color = Color(0, 0, 0, 0)
        fader.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
        add_child(fader)
    fader.visible = true
    return fader

func _on_settings_pressed():
    UiSfxManager.play_click()
    var ui_manager = get_parent() as UIManager
    if ui_manager and ui_manager.has_method("show_settings"):
        ui_manager.show_settings(true)
        if ui_manager.settings_menu:
            call_deferred("_ensure_extra_stimulants_plus_settings_entry", ui_manager.settings_menu)


func _ensure_extra_stimulants_plus_settings_entry(settings_menu: Control) -> void:
    if settings_menu == null or not is_instance_valid(settings_menu):
        return
    var gameplay_box: VBoxContainer = settings_menu.get("_gameplay_vbox")
    if gameplay_box == null:
        return
    if gameplay_box.get_node_or_null("ExtraStimulantsPlusRow") != null:
        return

    gameplay_box.add_child(HSeparator.new())

    var title := Label.new()
    title.name = "ExtraStimulantsPlusHeader"
    title.text = "EXTRASTIMULANTSPLUS"
    title.add_theme_font_size_override("font_size", 18)
    title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.4))
    gameplay_box.add_child(title)

    var row := HBoxContainer.new()
    row.name = "ExtraStimulantsPlusRow"
    row.add_theme_constant_override("separation", 16)

    var label := Label.new()
    label.text = "Mod settings"
    label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    label.add_theme_font_size_override("font_size", 22)
    gameplay_box.add_child(row)
    row.add_child(label)

    var button := Button.new()
    button.text = "Open"
    button.custom_minimum_size = Vector2(120, 36)
    button.pressed.connect(_open_extra_stimulants_plus_settings.bind(settings_menu))
    row.add_child(button)


func _open_extra_stimulants_plus_settings(settings_menu: Control) -> void:
    if UiSfxManager:
        UiSfxManager.play_click()

    var dialog := AcceptDialog.new()
    dialog.title = "ExtraStimulantsPlus Settings"
    dialog.size = Vector2i(520, 260)

    var root := VBoxContainer.new()
    root.add_theme_constant_override("separation", 12)
    dialog.add_child(root)

    root.add_child(_make_mod_settings_toggle(
        "Show version badge",
        ExtraStimulantsPlusSettings.should_show_version_badge(),
        func(on: bool):
            ExtraStimulantsPlusSettings.set_show_version_badge(on)
            _add_extra_stimulants_plus_badge()
    ))
    root.add_child(_make_mod_settings_toggle(
        "Show mod count",
        ExtraStimulantsPlusSettings.should_show_mod_status(),
        func(on: bool):
            ExtraStimulantsPlusSettings.set_show_mod_status(on)
            _add_extra_stimulants_plus_badge()
    ))
    root.add_child(_make_mod_settings_toggle(
        "Prefer .somap exports",
        ExtraStimulantsPlusSettings.prefers_somap(),
        func(on: bool): ExtraStimulantsPlusSettings.set_prefer_somap(on)
    ))
    root.add_child(_make_mod_settings_toggle(
        "Always show level editor entry",
        ExtraStimulantsPlusSettings.should_show_editor_entry(),
        func(on: bool):
            ExtraStimulantsPlusSettings.set_show_editor_entry(on)
            var editor_btn: Button = menu_container.get_node_or_null("EditorButton")
            if editor_btn:
                editor_btn.visible = on
    ))

    settings_menu.add_child(dialog)
    dialog.popup_centered()


func _make_mod_settings_toggle(label_text: String, initial_value: bool, callback: Callable) -> HBoxContainer:
    var row := HBoxContainer.new()
    row.add_theme_constant_override("separation", 12)

    var label := Label.new()
    label.text = label_text
    label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    label.add_theme_font_size_override("font_size", 18)
    row.add_child(label)

    var toggle := CheckButton.new()
    toggle.button_pressed = initial_value
    toggle.toggled.connect(callback)
    row.add_child(toggle)
    return row

func _start_game(mode: GameContext.GameMode):
    GameContext.set_mode(mode)



    var game = get_tree().current_scene
    if game and game.has_node("StateMachine"):
        game.get_node("StateMachine").change_state("Playing")
    else:
        push_error("MainMenu: Could not find Game StateMachine!")

func _on_quit_pressed():
    UiSfxManager.play_back()
    var sm = get_node_or_null("/root/SteamManager")
    if sm and sm.is_steam_available() and sm.rich_presence:
        if sm.rich_presence.has_method("clear_rich_presence"):
            sm.rich_presence.clear_rich_presence()
    get_tree().quit()

func _setup_debug_ui():

    if not has_node("DebugPanel"):
        return

    var title_material = title_control.material as ShaderMaterial
    if not title_material:
        return


    var container = $DebugPanel / ScrollContainer / VBoxContainer


    var init_slider = func(slider_name, param):
        var slider = container.get_node_or_null(slider_name)
        if slider:
            var val = title_material.get_shader_parameter(param)
            if val == null:
                val = 0.0
            slider.value = val

    init_slider.call("SeedSlider", "seed_offset")
    init_slider.call("ShakePowerSlider", "shake_power")
    init_slider.call("ShakeRateSlider", "shake_rate")
    init_slider.call("AberrationAmtSlider", "aberration_amount")
    init_slider.call("AberrationOpSlider", "aberration_opacity")
    init_slider.call("BlurSlider", "blur_amount")


    var picker1 = container.get_node_or_null("Color1Picker")
    if picker1:
        var c = title_material.get_shader_parameter("color_1")
        if c == null:
            c = Color(0.965, 0.098, 0.933, 1.0)
            title_material.set_shader_parameter("color_1", c)
        picker1.color = c

    var picker2 = container.get_node_or_null("Color2Picker")
    if picker2:
        var c = title_material.get_shader_parameter("color_2")
        if c == null:
            c = Color(0.055, 1.0, 0.455, 1.0)
            title_material.set_shader_parameter("color_2", c)
        picker2.color = c

    var picker3 = container.get_node_or_null("Color3Picker")
    if picker3:
        var c = title_material.get_shader_parameter("color_3")
        if c == null:
            c = Color(1.0, 0.831, 0.122, 1.0)
            title_material.set_shader_parameter("color_3", c)
        picker3.color = c

    var picker4 = container.get_node_or_null("Color4Picker")
    if picker4:
        var c = title_material.get_shader_parameter("color_4")
        if c == null:
            c = Color(0.404, 0.2, 0.878, 1.0)
            title_material.set_shader_parameter("color_4", c)
        picker4.color = c


    _update_label("LabelSeed", "Glitch Seed", "seed_offset")
    _update_label("LabelPower", "Shake Power", "shake_power")
    _update_label("LabelRate", "Shake Rate", "shake_rate")
    _update_label("LabelAmt", "Aberration Amt", "aberration_amount")
    _update_label("LabelOp", "Aberration Op", "aberration_opacity")
    _update_label("LabelBlur", "Blur Amount", "blur_amount")

func _update_label(node_name, prefix, param):
    var label = $DebugPanel / ScrollContainer / VBoxContainer.get_node_or_null(node_name)
    if label and title_control and title_control.material:
        var val = (title_control.material as ShaderMaterial).get_shader_parameter(param)
        if val == null: val = 0.0
        label.text = prefix + ": " + str(snapped(val, 0.01))


var _auto_cycle_seed: bool = true
var _cycle_speed: float = 24.0
var _cycle_timer: float = 0.0
var _current_seed_val: float = 0.0

func _input(event: InputEvent) -> void :
    if OS.has_feature("demo"):
        return

    if event is InputEventKey and event.pressed and not event.echo:
        if event.keycode == KEY_F1:
            if debug_panel:
                debug_panel.visible = not debug_panel.visible

func _process(delta):

    if _auto_cycle_seed and title_control and title_control.material:
        _cycle_timer += delta
        var interval = 1.0 / max(_cycle_speed, 0.001)

        if _cycle_timer >= interval:
            _cycle_timer = 0.0
            var mat = title_control.material as ShaderMaterial



            _current_seed_val += 1.37;
            if _current_seed_val > 100.0: _current_seed_val = 0.0

            mat.set_shader_parameter("seed_offset", _current_seed_val)

            if debug_panel and debug_panel.visible:
                var slider = $DebugPanel / ScrollContainer / VBoxContainer.get_node_or_null("SeedSlider")

                if slider: slider.set_value_no_signal(_current_seed_val)
                _update_label("LabelSeed", "Glitch Seed", "seed_offset")


    _update_player_camera()

func _on_seed_changed(value):
    _current_seed_val = value
    _set_shader_param("seed_offset", value)
    _update_label("LabelSeed", "Glitch Seed", "seed_offset")

func _on_cycle_seed_toggled(toggled_on):
    _auto_cycle_seed = toggled_on

func _on_cycle_speed_changed(value):
    _cycle_speed = value
    if $DebugPanel / ScrollContainer / VBoxContainer.get_node_or_null("LabelCycleSpeed"):
        $DebugPanel / ScrollContainer / VBoxContainer / LabelCycleSpeed.text = "Cycle Speed: " + str(value) + " Hz"

func _on_shake_power_changed(value):
    _set_shader_param("shake_power", value)
    _update_label("LabelPower", "Shake Power", "shake_power")

func _on_shake_rate_changed(value):
    _set_shader_param("shake_rate", value)
    _update_label("LabelRate", "Shake Rate", "shake_rate")

func _on_aberration_amount_changed(value):
    _set_shader_param("aberration_amount", value)
    _update_label("LabelAmt", "Aberration Amt", "aberration_amount")

func _on_aberration_opacity_changed(value):
    _set_shader_param("aberration_opacity", value)
    _update_label("LabelOp", "Aberration Op", "aberration_opacity")

func _on_blur_changed(value):
    _set_shader_param("blur_amount", value)
    _update_label("LabelBlur", "Blur Amount", "blur_amount")

func _on_color_1_changed(color):
    _set_shader_param("color_1", color)

func _on_color_2_changed(color):
    _set_shader_param("color_2", color)

func _on_color_3_changed(color):
    _set_shader_param("color_3", color)

func _on_color_4_changed(color):
    _set_shader_param("color_4", color)

func _set_shader_param(param_name, value):
    if title_control and title_control.material:
        (title_control.material as ShaderMaterial).set_shader_parameter(param_name, value)


var _cam_rotation_angles = Vector3(0.0, 0.0, -25.0)

func _on_cam_x_changed(value):
    _cam_rotation_angles.x = value
    $DebugPanel / ScrollContainer / VBoxContainer / LabelCamX.text = "Pitch: " + str(value)
    _update_player_camera()

func _on_cam_y_changed(value):
    _cam_rotation_angles.y = value
    $DebugPanel / ScrollContainer / VBoxContainer / LabelCamY.text = "Yaw: " + str(value)
    _update_player_camera()

func _on_cam_z_changed(value):
    _cam_rotation_angles.z = value
    $DebugPanel / ScrollContainer / VBoxContainer / LabelCamZ.text = "Roll: " + str(value)
    _update_player_camera()

func _update_player_camera():


    if not visible:
        return

    var game = get_tree().current_scene
    if game and game.has_node("PlayerController"):
        var pc = game.get_node("PlayerController")
        if pc.has_method("debug_set_menu_look_target"):
            pc.debug_set_menu_look_target(_cam_rotation_angles)

func _on_tunnel_offset_changed(value):
    $DebugPanel / ScrollContainer / VBoxContainer / LabelTunnelOffset.text = "Tunnel Pos Y: " + str(value)
    var game = get_tree().current_scene
    if game and game.has_node("PlayerController"):
        var pc = game.get_node("PlayerController")
        if pc.has_method("debug_set_position_y"):
            pc.debug_set_position_y(value)


var _logo_resolution_mult: float = 2.0

func capture_logo_transparent() -> void :







    var viewport = get_viewport()
    if not viewport:
        push_error("[MainMenu] Cannot get viewport for logo capture")
        return


    var original_transparent = viewport.transparent_bg
    var menu_was_visible = menu_container.visible
    var debug_was_visible = debug_panel.visible if debug_panel else false
    var bg_node = get_node_or_null("BackgroundGradient")
    var bg_was_visible = bg_node.visible if bg_node else false


    var world_env: WorldEnvironment = null
    var original_env_bg_mode: int = -1
    var original_env_bg_color: Color = Color.BLACK
    var scene_root = get_tree().current_scene
    if scene_root:
        world_env = scene_root.get_node_or_null("WorldEnvironment") as WorldEnvironment
        if not world_env:

            for child in scene_root.get_children():
                if child is WorldEnvironment:
                    world_env = child
                    break

    if world_env and world_env.environment:
        original_env_bg_mode = world_env.environment.background_mode
        original_env_bg_color = world_env.environment.background_color


    var hidden_nodes: Array[Node] = []
    if scene_root:
        for child in scene_root.get_children():

            if child is Node3D and not child is WorldEnvironment and child.visible:
                child.visible = false
                hidden_nodes.append(child)

            elif child is Control and child != self and child != get_parent() and child.visible:

                var is_ancestor = false
                var check = self
                while check:
                    if check == child:
                        is_ancestor = true
                        break
                    check = check.get_parent()
                if not is_ancestor:
                    child.visible = false
                    hidden_nodes.append(child)


    if world_env and world_env.environment:
        world_env.environment.background_mode = Environment.BG_COLOR
        world_env.environment.background_color = Color(0, 0, 0, 0)

    var parent = get_parent()
    if parent:
        for sibling in parent.get_children():
            if sibling != self and sibling is Control and sibling.visible:
                sibling.visible = false
                hidden_nodes.append(sibling)


    var title_rect = title_control.get_global_rect()


    menu_container.visible = false
    if debug_panel:
        debug_panel.visible = false
    if bg_node:
        bg_node.visible = false


    var hs_panel = get_node_or_null("HighScoresPanel")
    var hs_was_visible = hs_panel.visible if hs_panel else false
    if hs_panel:
        hs_panel.visible = false


    var camera: Camera3D = viewport.get_camera_3d()
    var camera_was_current = false
    if camera:
        camera_was_current = camera.current
        camera.current = false


    var original_ambient_energy: float = 0.0
    var original_fog_enabled: bool = false
    var original_glow_enabled: bool = false
    if world_env and world_env.environment:
        original_ambient_energy = world_env.environment.ambient_light_energy
        original_fog_enabled = world_env.environment.volumetric_fog_enabled
        original_glow_enabled = world_env.environment.glow_enabled
        world_env.environment.ambient_light_energy = 0.0
        world_env.environment.volumetric_fog_enabled = false
        world_env.environment.glow_enabled = false


    viewport.transparent_bg = true


    await get_tree().process_frame
    await get_tree().process_frame
    await get_tree().process_frame


    var full_image = viewport.get_texture().get_image()


    viewport.transparent_bg = original_transparent
    menu_container.visible = menu_was_visible
    if debug_panel:
        debug_panel.visible = debug_was_visible
    if bg_node:
        bg_node.visible = bg_was_visible
    if hs_panel:
        hs_panel.visible = hs_was_visible


    if camera and camera_was_current:
        camera.current = true


    if world_env and world_env.environment:
        if original_env_bg_mode >= 0:
            world_env.environment.background_mode = original_env_bg_mode
            world_env.environment.background_color = original_env_bg_color
        world_env.environment.ambient_light_energy = original_ambient_energy
        world_env.environment.volumetric_fog_enabled = original_fog_enabled
        world_env.environment.glow_enabled = original_glow_enabled


    for node in hidden_nodes:
        if is_instance_valid(node):
            node.visible = true


    var padding = 20
    var crop_x = int(max(0, title_rect.position.x - padding))
    var crop_y = int(max(0, title_rect.position.y - padding))
    var crop_w = int(min(title_rect.size.x + padding * 2, full_image.get_width() - crop_x))
    var crop_h = int(min(title_rect.size.y + padding * 2, full_image.get_height() - crop_y))

    var cropped_image = full_image.get_region(Rect2i(crop_x, crop_y, crop_w, crop_h))


    if _logo_resolution_mult > 1.0:
        var new_width = int(cropped_image.get_width() * _logo_resolution_mult)
        var new_height = int(cropped_image.get_height() * _logo_resolution_mult)
        cropped_image.resize(new_width, new_height, Image.INTERPOLATE_LANCZOS)


    var timestamp = Time.get_datetime_string_from_system().replace(":", "-").replace("T", "_")
    var filename = "logo_glitch_%s.png" % timestamp


    var dir_path = "user://screenshots/logo"
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir_path))


    var full_path = dir_path + "/" + filename
    var err = cropped_image.save_png(full_path)

    if err == OK:
        var global_path = ProjectSettings.globalize_path(full_path)
        print("[MainMenu] Logo captured with effects: " + global_path)
        print("[MainMenu] Size: %dx%d" % [cropped_image.get_width(), cropped_image.get_height()])

        _flash_capture_feedback()
    else:
        push_error("[MainMenu] Failed to save logo: " + full_path)

func _flash_capture_feedback() -> void :

    var flash = ColorRect.new()
    flash.color = Color(1, 1, 1, 0.3)
    flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    add_child(flash)

    var tween = create_tween()
    tween.tween_property(flash, "color:a", 0.0, 0.3)
    tween.tween_callback(flash.queue_free)

func open_logo_folder() -> void :
    var path = OS.get_user_data_dir() + "/screenshots/logo"
    DirAccess.make_dir_recursive_absolute(path)
    OS.shell_open(path)

func _on_logo_res_changed(value: float) -> void :
    _logo_resolution_mult = value
    $DebugPanel / ScrollContainer / VBoxContainer / LabelLogoRes.text = "Resolution: %sx" % str(value)

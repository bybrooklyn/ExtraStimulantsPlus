extends Node

# Daily Challenge entrypoint.
#
# Flow:
#   esp_ready -> wait for MainMenu -> inject button
#   click     -> derive UTC seed, generate level, show panel
#   PLAY      -> launch via ESP.campaign.play_generated, mark "in flight"
#   level_completed (hook) -> if in-flight flag is set, update streak + last_played

const MOD_ID := "daily_challenge"
const DailySeed := preload("seed.gd")
const DailyPanel := preload("daily_panel.gd")

const OBSTACLE_COUNT := 60
const DIFFICULTY := 3

var api: Node
var meta: Dictionary

var _panel: Control
var _pending_completion: bool = false


func esp_init(p_api: Node, p_meta: Dictionary) -> bool:
    api = p_api
    meta = p_meta
    return true


func esp_ready(_api: Node, _meta: Dictionary) -> void:
    api.events.on("level_completed", Callable(self, "_on_level_completed"), {"owner_id": MOD_ID})
    api.ui.inject_main_menu_button(
        "DAILY CHALLENGE",
        Callable(self, "_on_button_pressed"),
        MOD_ID,
        {"position": "after:CustomMapsButton"}
    )


# --- UI -------------------------------------------------------------------

func _on_button_pressed() -> void:
    if _panel and is_instance_valid(_panel):
        return

    var date_str := DailySeed.utc_date_string()
    var seed_value := DailySeed.fnv1a64(date_str)
    var options := {
        "date_label": date_str,
        "obstacle_count": OBSTACLE_COUNT,
        "difficulty": DIFFICULTY,
    }
    var generated: Dictionary = api.campaign.generate_sequence(seed_value, options)

    var saved := api.saves.get_mod_data(MOD_ID)
    var streak := int(saved.get("streak", 0))
    var last_played := String(saved.get("last_played_date", ""))
    var completed_today := last_played == date_str

    _panel = DailyPanel.new()
    _panel.populate_generated(date_str, seed_value, generated, options, streak, completed_today)
    _panel.play_requested.connect(_on_play_requested)
    _panel.closed.connect(_on_panel_closed)

    api.saves.set_data(MOD_ID, "last_seed", seed_value)
    api.saves.save()
    api.log_info("[%s] picked seed %d for %s" % [MOD_ID, seed_value, date_str])

    get_tree().root.add_child(_panel)


func _on_panel_closed() -> void:
    _panel = null


# --- Level launch ---------------------------------------------------------

func _on_play_requested(seed_value: int, options: Dictionary) -> void:
    _pending_completion = true
    if not api.campaign.play_generated(seed_value, options):
        _pending_completion = false
        api.log_warn("[%s] failed to launch generated daily level" % MOD_ID)
        return
    if _panel and is_instance_valid(_panel):
        _panel.queue_free()
        _panel = null


# --- Completion handling --------------------------------------------------

func _on_level_completed(_payload = null) -> void:
    if not _pending_completion:
        return
    _pending_completion = false

    var date_str := DailySeed.utc_date_string()
    var saved := api.saves.get_mod_data(MOD_ID)
    var prior_date := String(saved.get("last_played_date", ""))
    var prior_streak := int(saved.get("streak", 0))

    var new_streak := prior_streak
    var delta := DailySeed.day_delta(date_str, prior_date)
    if delta == 0:
        # Already counted today — keep streak as-is.
        pass
    elif delta == 1:
        new_streak = prior_streak + 1
    else:
        new_streak = 1

    api.saves.set_data(MOD_ID, "last_played_date", date_str)
    api.saves.set_data(MOD_ID, "streak", new_streak)
    api.saves.save()
    api.log_info("[%s] daily streak now %d (date %s)" % [MOD_ID, new_streak, date_str])

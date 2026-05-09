extends Node

# {{name}} — entrypoint with event hooks.
#
# Event subscriptions can be declared two ways:
#  1. Declaratively in mod.json under `hooks.events` (the array entries here
#     point at methods on this script — see `_on_level_started` below).
#  2. Imperatively at runtime via `api.events.on("event_name", callback, opts)`.
# Use the declarative form for stable wiring; imperative for conditional hooks.
#
# Common events (see scripts/core/esp_event_adapter.gd::GAME_EVENT_MAP for all):
#   level_started(level_id, attempt_index)
#   level_completed
#   player_died
#   obstacle_passed(obstacle)
#   obstacle_hit(obstacle)
#   score_updated(score)
#   game_started / game_over(reason)

const MOD_ID := "{{id}}"

var api: Node
var meta: Dictionary

func esp_init(p_api: Node, p_meta: Dictionary) -> bool:
    api = p_api
    meta = p_meta
    api.log_info("[%s] init" % MOD_ID)

    # Imperative subscription example — fires once for the next score update.
    # api.events.once(event_name, callback, options) -> bool
    api.events.once("score_updated", Callable(self, "_on_first_score"), {"owner_id": MOD_ID})

    return true

# Declarative-hook callbacks. Names match `hooks.events[].method` in mod.json.

func _on_level_started(level_id, attempt_index) -> void:
    api.log_info("[%s] level_started: %s (attempt %s)" % [MOD_ID, level_id, attempt_index])

func _on_obstacle_passed(obstacle) -> void:
    api.log_info("[%s] obstacle passed: %s" % [MOD_ID, obstacle])

func _on_first_score(score) -> void:
    api.log_info("[%s] first score event of the run: %s" % [MOD_ID, score])

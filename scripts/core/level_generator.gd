class_name ESPLevelGenerator extends RefCounted

# Deterministic procedural level generator. Pure helpers — no node lifecycle,
# no global state. Given an integer seed, produces an obstacle sequence that
# round-trips through ObstacleSequenceSerializer's JSON format.
#
# Two entry points:
#   generate_sequence(seed, options) -> Dictionary  # in-memory {sequence, meta}
#   write_generated_json(seed, options) -> String   # writes to user://, returns path
#
# The framework's CampaignNamespace exposes these as
# ESP.campaign.generate_sequence and ESP.campaign.play_generated.

const RUNTIME_DIR := "user://esp/runtime/levels"
const FORMAT_VERSION := 2  # matches ObstacleSequenceSerializer.FORMAT_VERSION

# Game obstacle types from SensoryOverload/scripts/domains/obstacles/
# obstacle_type_registry.gd, bucketed by difficulty tier (SIMPLE/MODERATE/COMPLEX).
const POOL_SIMPLE: Array[String] = [
    "crossing_bar", "diagonal_bar", "sector_wall", "block_square",
]
const POOL_MODERATE: Array[String] = [
    "cross_wall", "hole_gap", "double_slit", "triple_slit", "keyhole",
    "parallel_lanes", "sweeper_bar", "pillars", "sliding_bar",
]
const POOL_COMPLEX: Array[String] = [
    "mesh_wall", "spiral_steps", "concentric_rings", "windmill",
]

const DEFAULT_OBSTACLE_COUNT := 60
const DEFAULT_GAP_MIN := 0.55
const DEFAULT_GAP_MAX := 1.05
const DEFAULT_DIFFICULTY := 3
const DEFAULT_TEMPO_BPM := 120


# Returns a dict with shape:
#   {"sequence": Array[Dictionary], "meta": Dictionary}
# `sequence` entries use the compact serializer keys (t, g, sa, ...). Animation
# params (rotation/swing/slide/pulse) fall through to serializer defaults.
static func generate_sequence(seed_value: int, options: Dictionary = {}) -> Dictionary:
    var rng := RandomNumberGenerator.new()
    rng.seed = seed_value

    var count: int = max(int(options.get("obstacle_count", DEFAULT_OBSTACLE_COUNT)), 1)
    var gap_min: float = float(options.get("gap_min", DEFAULT_GAP_MIN))
    var gap_max: float = float(options.get("gap_max", DEFAULT_GAP_MAX))
    var difficulty: int = clampi(int(options.get("difficulty", DEFAULT_DIFFICULTY)), 1, 5)

    var sequence: Array = []
    for i in range(count):
        var t: float = float(i) / float(max(count - 1, 1))  # progress 0.0 → 1.0
        var weights := _difficulty_weights(t, difficulty)
        var pool := _pick_pool(rng, weights)
        var obstacle_type: String = pool[rng.randi_range(0, pool.size() - 1)]
        # Tighten gap as the level approaches its end — late-section pacing pressure.
        var base_gap := rng.randf_range(gap_min, gap_max)
        var tight_gap := rng.randf_range(gap_min, gap_max) * 0.6
        var gap: float = lerp(base_gap, tight_gap, t)
        sequence.append({
            "t": obstacle_type,
            "g": gap,
            "sa": rng.randf_range(0.0, TAU),
        })

    var date_label := String(options.get("date_label", str(seed_value)))
    return {
        "sequence": sequence,
        "meta": {
            "title": "Daily Challenge — %s" % date_label,
            "description": "Procedurally generated. Difficulty %d, %d obstacles." % [difficulty, count],
            "difficulty": difficulty,
            "stage_name": "Procedural Stage",
            "stage_id": "esp_proc_%d" % seed_value,
            "seed": seed_value,
        },
    }


# Writes a generated sequence to user://esp/runtime/levels/generated_<seed>.json.
# Returns the absolute (user://-prefixed) path on success, "" on failure.
# The on-disk shape matches what ObstacleSequenceSerializer.load_from_json reads.
static func write_generated_json(seed_value: int, options: Dictionary = {}) -> String:
    var generated := generate_sequence(seed_value, options)
    if not DirAccess.dir_exists_absolute(RUNTIME_DIR):
        var dir_err := DirAccess.make_dir_recursive_absolute(RUNTIME_DIR)
        if dir_err != OK:
            return ""
    # Use abs() so the filename never starts with `-` (signed Int64 seeds
    # land negative ~half the time). Avoids confusing CLI tools that treat
    # a leading `-` as a flag — the rare collision across signed-flip pairs
    # just overwrites the same temp file with regenerated content.
    var path := RUNTIME_DIR.path_join("generated_%d.json" % abs(seed_value))
    var body := {
        "name": generated.meta.get("title", "Daily Challenge"),
        "version": FORMAT_VERSION,
        "tempo_bpm": int(options.get("tempo_bpm", DEFAULT_TEMPO_BPM)),
        "obstacles": generated.sequence,
    }
    var file := FileAccess.open(path, FileAccess.WRITE)
    if file == null:
        return ""
    file.store_string(JSON.stringify(body))
    file.close()
    return path


static func _difficulty_weights(t: float, difficulty: int) -> Dictionary:
    # difficulty 1 = gentle (mostly SIMPLE throughout)
    # difficulty 5 = aggressive (sharp ramp into COMPLEX by end)
    var d_norm := float(difficulty) / 5.0
    return {
        "simple": lerp(0.7, 0.1, t) * (1.2 - d_norm),
        "moderate": 0.3 + 0.4 * t,
        "complex": lerp(0.0, 0.7, t) * d_norm,
    }


static func _pick_pool(rng: RandomNumberGenerator, weights: Dictionary) -> Array[String]:
    var w_simple: float = float(weights.get("simple", 0.0))
    var w_moderate: float = float(weights.get("moderate", 0.0))
    var w_complex: float = float(weights.get("complex", 0.0))
    var total := w_simple + w_moderate + w_complex
    if total <= 0.0:
        return POOL_SIMPLE
    var r := rng.randf_range(0.0, total)
    if r < w_simple:
        return POOL_SIMPLE
    if r < w_simple + w_moderate:
        return POOL_MODERATE
    return POOL_COMPLEX

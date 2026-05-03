extends Node3D
class_name ObstacleManager

const ObstacleInstance = preload("res://scripts/domains/obstacles/obstacle_instance.gd")









@export var config: Resource
@export var rotator_script: Script = preload("res://scripts/domains/obstacles/rotator.gd")
@export var debris_script: Script = preload("res://scripts/gameplay/debris_cube.gd")


const DESTRUCTION_DURATION: float = 1.5

const GHOST_DESTROY_DISTANCE: float = 28.0

const GHOST_DESTROY_DURATION: float = 0.7


@export var min_time_between_traps_sec: float = 1.6

@export var min_distance_between_traps: float = 20.0

@export var min_rings_floor: int = 20


const SPAWN_LOG_THRESHOLD_MS: float = 4.0
static var _spawn_log_enabled: bool = OS.is_debug_build()


class ObstacleTypeConfig:
    var id: String
    var name: String
    var enabled: bool = true
    var spawn_weight: float = 10.0
    var rotation_chance: float = 0.5
    var rotation_speed_min: float = 1.0
    var rotation_speed_max: float = 3.0

    var oscillate_chance: float = 0.0
    var oscillate_speed_min: float = 1.0
    var oscillate_speed_max: float = 3.0

    var random_orientation: bool = false

    func _init(_id: String, _name: String, _weight: float = 10.0):
        id = _id
        name = _name
        spawn_weight = _weight




var debris_material_template: StandardMaterial3D



var debris_shard_mesh: Mesh
var type_configs: Dictionary = {}

var current_level_index: int = 0
var manual_level_override: int = -1

var safe_path_angle: float = 0.0
var rings_since_obstacle: int = 0
var next_obstacle_interval: int = -1
var override_interval_min: int = -1
var override_interval_max: int = -1




var interval_lock_speed: float = -1.0

var spawn_enabled: bool = true
var ghost_mode: bool = false
var ghost_destruction_enabled: bool = true

var active_obstacles: Array[Node3D] = []
var last_checked_ring: int = 0
var base_material: Material



var _swap_preview_material: StandardMaterial3D = null


var last_obstacle_color: Color = Color.BLACK


var beat_palette_color: Variant = null

var beat_palette_colors: Array[Color] = []
var current_theme: LevelTheme





var current_substage: SubStageDef = null
var twist_time: float = 0.0
var section_rotation_time: float = 0.0
var wobble_time: float = 0.0
var breathing_time: float = 0.0
var ripple_time: float = 0.0
var tide_time: float = 0.0
var shear_time: float = 0.0
var helix_time: float = 0.0
var pinch_time: float = 0.0
var mobius_time: float = 0.0
var last_cam_y: float = 0.0
var player_offset_x: float = 0.0
var player_offset_z: float = 0.0
var ring_origin_offset: float = 0.0
var _time_externally_synced: bool = false
var _cached_theme_overrides: Dictionary = {}
var current_speed: float = 28.0
var speed_scaling_factor: float = 1.0
var max_difficulty_level: int = 6



var use_encounter_system: bool = false

var suppress_legacy_spawning: bool = false

var encounter_sequencer: EncounterSequencer

var obstacle_library: ObstacleDefinitionLibrary


var pacing_mode: bool = false
var _player_controller: Node3D



var _shared_box_shapes: Dictionary = {}





const _OBSTACLE_POOL_CAP: = 8
var _obstacle_pool: Dictionary = {}






var _local_rng: = RandomNumberGenerator.new()

func _ready():
    _local_rng.randomize()
    _setup_material()
    _init_default_configs()

    if not config:
        config = load("res://resources/tunnel_config.tres")
        if not config:
            push_error("ObstacleManager: No TunnelConfig found!")


    obstacle_library = ObstacleDefinitionLibrary.new()
    obstacle_library.setup(config.base_radius if config else 10.0)
    obstacle_library.load_all()


    EventBus.level_started.connect(_on_level_started)
    EventBus.origin_shifted.connect( func(amount):
        _on_origin_shifted(amount)
        ring_origin_offset += (amount / config.ring_spacing)
    )
    EventBus.player_moved.connect( func(data):
        last_cam_y = data.y
        if data.z != 0.0:
            move_active_obstacles(data.z)
        update_obstacles(data.x, data.y)
    )


    _player_controller = get_parent().get_parent().get_node_or_null("PlayerController")
    if not _player_controller:
        _player_controller = get_tree().current_scene.find_child("PlayerController", true, false)

func _init_default_configs():

    type_configs["crossing_bar"] = ObstacleTypeConfig.new("crossing_bar", "Crossing Bar", 10.0)
    type_configs["diagonal_bar"] = ObstacleTypeConfig.new("diagonal_bar", "Diagonal Bar", 10.0)
    type_configs["sector_wall"] = ObstacleTypeConfig.new("sector_wall", "Ring Sector", 10.0)
    type_configs["cross_wall"] = ObstacleTypeConfig.new("cross_wall", "Cross Pattern", 0.0)
    type_configs["hole_gap"] = ObstacleTypeConfig.new("hole_gap", "Wall Blocker", 0.0)
    type_configs["mesh_wall"] = ObstacleTypeConfig.new("mesh_wall", "Mesh Pattern", 0.0)
    type_configs["spiral_steps"] = ObstacleTypeConfig.new("spiral_steps", "Spiral Steps", 0.0)
    type_configs["block_square"] = ObstacleTypeConfig.new("block_square", "Block Square", 0.0)
    type_configs["block_square"].rotation_chance = 0.0

    type_configs["double_slit"] = ObstacleTypeConfig.new("double_slit", "Double Slit", 0.0)
    type_configs["triple_slit"] = ObstacleTypeConfig.new("triple_slit", "Triple Slit", 0.0)
    type_configs["keyhole"] = ObstacleTypeConfig.new("keyhole", "Keyhole", 0.0)
    type_configs["concentric_rings"] = ObstacleTypeConfig.new("concentric_rings", "Concentric Rings", 0.0)
    type_configs["parallel_lanes"] = ObstacleTypeConfig.new("parallel_lanes", "Parallel Lanes", 0.0)


    type_configs["sweeper_bar"] = ObstacleTypeConfig.new("sweeper_bar", "Sweeper Bar", 0.0)
    type_configs["windmill"] = ObstacleTypeConfig.new("windmill", "Windmill", 0.0)

    type_configs["pillars"] = ObstacleTypeConfig.new("pillars", "Pillars", 0.0)

    type_configs["sliding_bar"] = ObstacleTypeConfig.new("sliding_bar", "Sliding Bar", 0.0)





    refresh_difficulty_weights(0)

func refresh_difficulty_weights(level_idx: int):

    if manual_level_override != -1: return


    var effective_idx = min(level_idx, max_difficulty_level)


    for k in type_configs:
        type_configs[k].spawn_weight = 0.0


    if effective_idx <= 1:
        type_configs["sector_wall"].spawn_weight = 25.0
        type_configs["block_square"].spawn_weight = 15.0
        if effective_idx >= 1:
            type_configs["crossing_bar"].spawn_weight = 10.0
            type_configs["diagonal_bar"].spawn_weight = 10.0
        return


    type_configs["crossing_bar"].spawn_weight = 20.0
    type_configs["diagonal_bar"].spawn_weight = 20.0
    type_configs["sector_wall"].spawn_weight = 20.0


    if effective_idx >= 3:
        type_configs["block_square"].spawn_weight = 10.0


    if effective_idx >= 2:
        type_configs["cross_wall"].spawn_weight = 15.0
        type_configs["hole_gap"].spawn_weight = 15.0


    if effective_idx >= 4:
        type_configs["mesh_wall"].spawn_weight = 10.0
        type_configs["spiral_steps"].spawn_weight = 10.0

var shared_obstacle_mat: ShaderMaterial
var shared_obstacle_mat_opaque: ShaderMaterial
var shared_edge_mat: ShaderMaterial




var _current_obstacle_opacity: float = 1.0
var current_edge_width: float = 0.05


var _destruction_tween: Tween
var _destruction_mats: Array[ShaderMaterial] = []
var _destruction_obstacles: Array[Node3D] = []



var _ghost_destroying: Dictionary = {}

func _setup_material():
    var shader_transparent = load("res://materials/obstacle.gdshader")
    var shader_opaque = load("res://materials/obstacle_opaque.gdshader")
    if not shader_transparent or not shader_opaque:
        push_error("Obstacle Shader not found!")
        return




    shared_obstacle_mat = ShaderMaterial.new()
    shared_obstacle_mat.shader = shader_transparent
    shared_obstacle_mat.set_shader_parameter("metallic", 0.1)
    shared_obstacle_mat.set_shader_parameter("roughness", 0.81)
    shared_obstacle_mat.set_shader_parameter("specular", 0.2)

    shared_obstacle_mat.set_shader_parameter("emission_energy", 0.35)
    shared_obstacle_mat.set_shader_parameter("emission_brightness", 1.0)

    shared_obstacle_mat.set_shader_parameter("dissolve_delay", 0.35)




    shared_obstacle_mat_opaque = ShaderMaterial.new()
    shared_obstacle_mat_opaque.shader = shader_opaque
    shared_obstacle_mat_opaque.set_shader_parameter("metallic", 0.1)
    shared_obstacle_mat_opaque.set_shader_parameter("roughness", 0.81)
    shared_obstacle_mat_opaque.set_shader_parameter("specular", 0.2)

    shared_obstacle_mat_opaque.set_shader_parameter("emission_energy", 0.35)
    shared_obstacle_mat_opaque.set_shader_parameter("emission_brightness", 1.0)
    shared_obstacle_mat_opaque.set_shader_parameter("dissolve_delay", 0.35)




    shared_edge_mat = shared_obstacle_mat_opaque.duplicate()
    shared_edge_mat.set_shader_parameter("emission_energy", 1.0)
    shared_edge_mat.set_shader_parameter("emission_brightness", 3.0)

    shared_edge_mat.set_shader_parameter("dissolve_delay", 0.0)





func _get_body_material() -> ShaderMaterial:
    if _current_obstacle_opacity < 0.999:
        return shared_obstacle_mat
    return shared_obstacle_mat_opaque


func set_obstacle_roughness(amount: float):
    if shared_obstacle_mat: shared_obstacle_mat.set_shader_parameter("roughness_amount", amount)
    if shared_obstacle_mat_opaque: shared_obstacle_mat_opaque.set_shader_parameter("roughness_amount", amount)
    if shared_edge_mat: shared_edge_mat.set_shader_parameter("roughness_amount", amount)

func set_outline_width(width: float):
    current_edge_width = width







    pass

func set_outline_brightness(brightness: float):
    if shared_edge_mat:
        shared_edge_mat.set_shader_parameter("emission_brightness", brightness)

func set_outline_enabled(enabled: bool):
    if shared_edge_mat:
        shared_edge_mat.set_shader_parameter("emission_energy", 1.0 if enabled else 0.0)

func set_outline_fade_dist(dist: float):
    if shared_edge_mat:
        shared_edge_mat.set_shader_parameter("outline_fade_dist", dist)


func set_obstacle_opacity(opacity: float):
    _current_obstacle_opacity = opacity


    if shared_obstacle_mat:
        shared_obstacle_mat.set_shader_parameter("obstacle_opacity", opacity)
    if shared_obstacle_mat_opaque:
        shared_obstacle_mat_opaque.set_shader_parameter("obstacle_opacity", opacity)
    if shared_edge_mat:
        shared_edge_mat.set_shader_parameter("obstacle_opacity", opacity)


func _physics_process(delta: float) -> void :






    if _player_controller:
        player_offset_x = _player_controller.position.x
        player_offset_z = _player_controller.position.z


    var time_wrap: float = 1000.0 * PI

    if _time_externally_synced:

        _time_externally_synced = false
        _update_obstacle_transforms(delta)
    elif current_theme:



        var td: = _cached_theme_overrides
        twist_time = fmod(twist_time + delta * td.get("twist_speed", 0.3), time_wrap)
        section_rotation_time = fmod(section_rotation_time + delta * td.get("section_spin", 0.0), time_wrap)
        wobble_time = fmod(wobble_time + delta * td.get("wobble_frequency", 0.0), time_wrap)
        breathing_time = fmod(breathing_time + delta * td.get("breathing_frequency", 0.0), time_wrap)
        ripple_time = fmod(ripple_time + delta * td.get("ripple_frequency", 0.0), time_wrap)
        shear_time = fmod(shear_time + delta * td.get("shear_frequency", 0.0), time_wrap)
        helix_time = fmod(helix_time + delta * td.get("helix_speed", 0.0), time_wrap)
        pinch_time = fmod(pinch_time + delta * td.get("pinch_speed", 0.0), time_wrap)
        mobius_time = fmod(mobius_time + delta * td.get("mobius_speed", 0.0), time_wrap)
        _update_obstacle_transforms(delta)
    else:

        twist_time = fmod(twist_time + delta, time_wrap)
        section_rotation_time = fmod(section_rotation_time + delta, time_wrap)
        wobble_time = fmod(wobble_time + delta, time_wrap)
        breathing_time = fmod(breathing_time + delta, time_wrap)
        ripple_time = fmod(ripple_time + delta, time_wrap)
        _update_obstacle_transforms(delta)





const LF_ROTATION: = 1
const LF_ANIMATION: = 2
const LF_PULSE: = 4
const LF_SWAP: = 8




func _compute_loop_flags(obs: Node3D) -> int:
    var f: int = 0
    if obs.has_meta("base_rot_speed") and obs.base_rot_speed != 0.0:
        f |= LF_ROTATION
    elif obs.current_rot_val != 0.0:
        f |= LF_ROTATION
    if obs.animation_type == "sliding_bar":
        f |= LF_ANIMATION
    if obs.pulse_enabled:
        f |= LF_PULSE
    if obs.swap_enabled:
        f |= LF_SWAP
    return f








func _tick_obstacle_animation(obs: Node3D, delta: float, apply_offset: bool) -> void :

    var anim_speed: float = obs.animation_speed
    var anim_phase: float = obs.animation_phase
    var slide_amplitude: float = obs.slide_amplitude
    anim_phase += delta * anim_speed * deg_to_rad(1.0)
    obs.animation_phase = anim_phase
    var slide_offset: float = sin(anim_phase) * slide_amplitude
    obs.slide_position_offset = slide_offset
    if not apply_offset:
        return
    if absf(slide_offset) <= 0.001:
        return
    if obs.slide_axis == 0:
        obs.position.x += slide_offset
    else:
        obs.position.z += slide_offset

func _update_obstacle_transforms(_delta: float, time_data: Dictionary = {}) -> void :
    if active_obstacles.is_empty(): return
    var theme: LevelTheme = current_theme


    var cur_section_rot_time: float = time_data.get("section_rotation_time", section_rotation_time)
    var cur_twist_time: float = time_data.get("twist_time", twist_time)
    var cur_wobble_time: float = time_data.get("wobble_time", wobble_time)
    var cur_ripple_time: float = time_data.get("ripple_time", ripple_time)
    var cur_shear_time: float = time_data.get("shear_time", shear_time)
    var cur_breathing_time: float = time_data.get("breathing_time", breathing_time)
    var cur_helix_time: float = time_data.get("helix_time", helix_time)
    var cur_mobius_time: float = time_data.get("mobius_time", mobius_time)
    var cur_pinch_time: float = time_data.get("pinch_time", pinch_time)


    var td: Dictionary = _cached_theme_overrides
    var has_td: bool = not td.is_empty()
    var eff_spin: float = 0.0
    var is_step: bool = false
    var eff_wobble: float = 0.0
    var eff_twist: float = 0.0
    var eff_ripple: float = 0.0
    var eff_shear: float = 0.0
    var eff_breathing: float = 0.0
    var eff_helix: float = 0.0
    var eff_mobius: float = 0.0
    var eff_pinch: float = 0.0
    var eff_curve: float = 0.0
    var eff_exp: float = 0.0
    var eff_tide: float = 0.0
    var eff_react: float = 0.0
    var eff_rp: float = 0.0


    var t_section_offset: int = 0
    var t_section_length: float = 25.0
    var t_sync_rotation: bool = false
    var t_spin_obstacles: bool = false
    var t_helix_freq: float = 0.0
    var t_mobius_offset_rad: float = 0.0
    var t_pinch_freq: float = 0.0
    var t_pinch_w: float = 1.0
    var t_shear_x: float = 1.0
    var t_shear_z: float = 0.0
    var t_pr_start: float = 0.0
    var t_rp_obstacles: bool = false
    var t_pr_obstacles: bool = false

    if theme:


        eff_spin = td.get("section_spin", 0.0)
        is_step = bool(td.get("step_rotation", false))
        eff_wobble = td.get("wobble_amount", 0.0)
        eff_twist = td.get("tunnel_twist", 0.0)
        eff_ripple = td.get("ripple_amount", 0.0)
        eff_shear = td.get("shear_amount", 0.0)
        eff_breathing = td.get("breathing_amount", 0.0)
        eff_helix = td.get("helix_amount", 0.0)
        eff_mobius = td.get("mobius_amount", 0.0)
        eff_pinch = td.get("pinch_amount", 0.0)
        eff_curve = td.get("tunnel_curve", 0.0)
        eff_exp = td.get("tunnel_expansion", 0.0)
        eff_tide = td.get("tide_amount", 0.0)
        eff_react = td.get("player_reactive_curve", 0.0)
        eff_rp = td.get("reverse_perspective", 0.0)

        t_section_offset = int(td.get("section_offset", 0))
        t_section_length = float(td.get("section_length", 25.0))
        t_sync_rotation = bool(td.get("sync_rotation", false))
        t_spin_obstacles = bool(td.get("spin_obstacles_with_walls", true))
        t_helix_freq = td.get("helix_frequency", 0.0)
        t_mobius_offset_rad = deg_to_rad(td.get("mobius_offset", 0.0))
        t_pinch_freq = td.get("pinch_frequency", 0.0)
        t_pinch_w = td.get("pinch_width", 15.0)
        t_shear_x = td.get("shear_x", 1.0)
        t_shear_z = td.get("shear_z", 0.0)
        t_pr_start = td.get("player_reactive_start", 0.0)
        t_rp_obstacles = bool(td.get("reverse_perspective_obstacles", true))
        t_pr_obstacles = bool(td.get("player_reactive_obstacles", true))


    var has_spin: bool = absf(eff_spin) > 0.001 and t_spin_obstacles




    var has_any_deform: bool = (
        absf(eff_wobble) > 0.001 or absf(eff_helix) > 0.001 or 
        absf(eff_twist) > 0.001 or absf(eff_shear) > 0.001 or 
        absf(eff_breathing) > 0.001 or absf(eff_mobius) > 0.001 or 
        absf(eff_pinch) > 0.001 or absf(eff_curve) > 0.001 or 
        absf(eff_exp) > 0.001 or absf(eff_tide) > 0.001 or 
        absf(eff_ripple) > 0.001 or 
        (t_rp_obstacles and absf(eff_rp) > 0.001) or 
        (t_pr_obstacles and absf(eff_react) > 0.001)
    )


    var c_ring_spacing: float = config.ring_spacing






    var _player_off2: = Vector2(player_offset_x, player_offset_z)

    # Turbo Optimization: Pre-calculate music pulse for the entire loop
    var precomputed_pulse: float = 0.0
    var settings = get_node_or_null("/root/ExtraStimulantsPlusSettings")
    if settings and settings.is_deformation_reactivity_enabled():
        var visualizer = get_node_or_null("/root/AudioVisualizer")
        if visualizer:
            precomputed_pulse = visualizer.get_bass_pulse() * settings.get_reactivity_intensity()

    for obs in active_obstacles:
        var world_y: float = obs.position.y





        var lf: int = obs._loop_flags
        if lf == -1:
            lf = _compute_loop_flags(obs)
            obs._loop_flags = lf
        var has_anim: bool = (lf & LF_ANIMATION) != 0


        var dist_from_cam: float = abs(last_cam_y - world_y)
        if dist_from_cam > 200.0:



            if has_anim:
                _tick_obstacle_animation(obs, _delta, false)
            continue

        var rot_offset: float = 0.0


        var ring_raw: float = ((50.0 - world_y) / c_ring_spacing) + ring_origin_offset
        var wrapped_ring: float = fmod(ring_raw, 3600.0)


        if has_spin:
            @warning_ignore("integer_division")
            var sec_idx: int = int((ring_raw + t_section_offset) / t_section_length)
            var dir: float = 1.0 if (t_sync_rotation or sec_idx % 2 == 0) else -1.0
            var raw_rot: float = cur_section_rot_time * dir

            if is_step:
                var step_val: float = PI / 4.0
                rot_offset += round(raw_rot / step_val) * step_val
            else:
                rot_offset += raw_rot


        if (lf & LF_ROTATION) != 0:
            var base_speed: float = obs.base_rot_speed
            if base_speed != 0.0:
                var is_osc: bool = obs.oscillate

                var current_rot: float = obs.current_rot_val
                current_rot += _delta * base_speed
                obs.current_rot_val = current_rot
                if is_osc:
                    var osc_amplitude: float = obs.oscillate_amplitude
                    var osc_phase: float = obs.oscillate_phase
                    rot_offset += sin(current_rot + osc_phase) * osc_amplitude
                else:
                    rot_offset += current_rot
            else:

                rot_offset += obs.current_rot_val

        obs.rotation.y = - rot_offset


        if not theme:
            if has_anim:
                _tick_obstacle_animation(obs, _delta, true)
            continue






        if has_any_deform:
            TunnelDeformUtil.apply_deform_to_obstacle(
                ring_raw, wrapped_ring, world_y, last_cam_y, 
                eff_wobble, cur_wobble_time, 
                eff_helix, cur_helix_time, t_helix_freq, 
                eff_mobius, cur_mobius_time, t_mobius_offset_rad, 
                eff_twist, cur_twist_time, false, 
                eff_shear, cur_shear_time, t_shear_x, t_shear_z, 
                eff_tide, tide_time, 
                eff_breathing, cur_breathing_time, 
                eff_pinch, cur_pinch_time, t_pinch_w, t_pinch_freq, 
                eff_curve, 
                eff_exp, 
                eff_rp, t_rp_obstacles, 
                eff_react, t_pr_obstacles, t_pr_start, 
                eff_ripple, cur_ripple_time, 
                _player_off2,
                obs,
                rot_offset,
                precomputed_pulse
            )
        else:
            obs.scale = Vector3.ONE
            obs.position.x = 0.0
            obs.position.z = 0.0
            obs.rotation.y = - rot_offset


        if has_anim:
            _tick_obstacle_animation(obs, _delta, true)


        if (lf & LF_PULSE) != 0:
            var p_speed: float = obs.pulse_speed
            var p_amp: float = obs.pulse_amplitude
            var p_phase: float = obs.pulse_phase
            var p_axis: int = obs.pulse_axis
            var p_time: float = obs.pulse_time
            p_time += _delta
            obs.pulse_time = p_time
            var pulse_val: float = 1.0 + sin(p_time * p_speed * TAU + p_phase) * p_amp
            match p_axis:
                0: obs.scale = Vector3.ONE * pulse_val
                1: obs.scale.x = pulse_val
                2: obs.scale.z = pulse_val





        if (lf & LF_SWAP) != 0:
            var s_period: float = obs.swap_period_sec
            if s_period > 0.001:
                var s_phase: float = obs.swap_phase_sec
                var s_count: int = obs.swap_variant_count
                var s_time: float = obs.swap_time + _delta
                obs.swap_time = s_time
                var s_idx: int = _compute_swap_variant_index(s_time, s_phase, s_period, s_count)
                if s_idx != obs.swap_active_index:
                    _set_active_swap_variant(obs, s_idx)



                _update_swap_flash(obs, s_time, s_phase, s_period, s_idx)


                _update_swap_preview(obs, s_time, s_phase, s_period, s_idx, s_count)


func update_obstacles(logical_dist: float, real_camera_y: float = INF, time_data: Dictionary = {}, theme_data: Dictionary = {}):


    if real_camera_y == INF: real_camera_y = - logical_dist

    last_cam_y = real_camera_y

    if not time_data.is_empty():
        twist_time = time_data.get("twist_time", twist_time)
        section_rotation_time = time_data.get("section_rotation_time", section_rotation_time)
        wobble_time = time_data.get("wobble_time", wobble_time)
        breathing_time = time_data.get("breathing_time", breathing_time)
        ripple_time = time_data.get("ripple_time", ripple_time)
        tide_time = time_data.get("tide_time", tide_time)
        shear_time = time_data.get("shear_time", shear_time)
        helix_time = time_data.get("helix_time", helix_time)
        pinch_time = time_data.get("pinch_time", pinch_time)
        mobius_time = time_data.get("mobius_time", mobius_time)
        _time_externally_synced = true

    if not theme_data.is_empty():
        _cached_theme_overrides = theme_data


    for obs in active_obstacles:
        if not obs.passed:


            if real_camera_y < obs.position.y:
                obs.passed = true
                EventBus.obstacle_passed.emit(obs)


    if ghost_mode and ghost_destruction_enabled:
        for obs in active_obstacles:
            if _ghost_destroying.has(obs):
                continue
            if obs.passed:
                continue




            var dist_to_cam: float = real_camera_y - obs.position.y
            if dist_to_cam > 0.0 and dist_to_cam < GHOST_DESTROY_DISTANCE:
                _ghost_destroy_obstacle(obs)

    _cleanup_obstacles(real_camera_y)

    if not spawn_enabled: return

    var current_ring = int(logical_dist / config.ring_spacing)

    if current_ring > last_checked_ring:

        if (current_ring - last_checked_ring) > 500:
            push_warning("ObstacleManager: Large ring gap detected (%d). Skipping for performance." % (current_ring - last_checked_ring))
            last_checked_ring = current_ring
            return

        if not suppress_legacy_spawning:




            for r in range(last_checked_ring + 1, current_ring + 1):
                if _should_spawn_obstacle(r):
                    var lookahead_time = 4.0
                    var lookahead_dist = current_speed * lookahead_time
                    lookahead_dist = max(lookahead_dist, 50.0)
                    var spawn_y = real_camera_y - lookahead_dist
                    _spawn_obstacle_at(r, spawn_y)
        last_checked_ring = current_ring

func move_active_obstacles(amount: float):
    for obs in active_obstacles:
        obs.position.y += amount
        var old_base = obs.base_y
        obs.base_y = old_base + amount

func _cleanup_obstacles(camera_y: float):
    for i in range(active_obstacles.size() - 1, -1, -1):
        var obs = active_obstacles[i]
        if _ghost_destroying.has(obs):
            continue
        if camera_y < (obs.position.y - 50.0):
            active_obstacles.remove_at(i)
            if not _release_to_pool(obs):
                obs.queue_free()



func _get_shared_box_shape(size: Vector3) -> BoxShape3D:
    var cached = _shared_box_shapes.get(size)
    if cached != null:
        return cached
    var shape: = BoxShape3D.new()
    shape.size = size
    _shared_box_shapes[size] = shape
    return shape



func _try_acquire_pooled_obstacle(type_id: String, new_color: Color) -> Node3D:
    var bucket: Array = _obstacle_pool.get(type_id, [])
    if bucket.is_empty():
        return null
    var container: Node3D = bucket.pop_back()
    _obstacle_pool[type_id] = bucket
    _reset_pooled_obstacle(container, new_color)
    return container



func _release_to_pool(container: Node3D) -> bool:
    if not container.has_meta("pool_type_id"):
        return false
    var type_id: String = container.pool_type_id
    var bucket: Array = _obstacle_pool.get(type_id, [])
    if bucket.size() >= _OBSTACLE_POOL_CAP:
        return false
    if container.get_parent():
        container.get_parent().remove_child(container)
    bucket.push_back(container)
    _obstacle_pool[type_id] = bucket
    return true



func _reset_pooled_obstacle(container: Node3D, new_color: Color) -> void :
    container.transform = Transform3D.IDENTITY
    container.visible = true
    
    # Clear Turbo properties
    container.hit_box_positions = PackedVector3Array()
    container.hit_box_half_size = Vector3.ZERO
    container.collision_area = null

    for child in container.get_children():
        if child is Area3D:
            child.collision_layer = 0 if ghost_mode else 4
            child.collision_mask = 0 if ghost_mode else 2
            child.monitorable = not ghost_mode
            child.monitoring = not ghost_mode






    for key in container.get_meta_list():
        if key == "pool_type_id" or key == "pool_last_color":
            continue
        container.remove_meta(key)
    var last_color: Color = container.pool_last_color
    if last_color != new_color:
        for child in container.get_children():
            if child is MultiMeshInstance3D:
                var mm: MultiMesh = child.multimesh
                if mm:
                    for i in range(mm.instance_count):
                        mm.set_instance_color(i, new_color)
        container.pool_last_color = new_color



func _clear_obstacle_pool() -> void :
    for type_id in _obstacle_pool:
        for container in _obstacle_pool[type_id]:
            if is_instance_valid(container):
                container.queue_free()
    _obstacle_pool.clear()

















func prewarm_all_obstacle_types() -> void :
    if not config:
        push_warning("ObstacleManager.prewarm: no config, skipping")
        return
    if not obstacle_library:
        push_warning("ObstacleManager.prewarm: no obstacle_library, skipping")
        return

    var t0_msec: = Time.get_ticks_msec()
    var prewarm_y: float = 10000.0
    var prewarm_color: = Color.WHITE
    var prewarmed: Array[Node3D] = []
    var skipped: Array[String] = []
    var cube_mesh: = BoxMesh.new()
    cube_mesh.size = Vector3.ONE * config.cube_size






    var prev_ghost_mode: = ghost_mode
    ghost_mode = true

    for type_id in type_configs.keys():
        var def: = obstacle_library.get_definition(type_id)
        if def == null or def.filled_cells.is_empty():
            skipped.append(type_id)
            continue
        var instances_data: Array = def.get_cell_data(
            config.base_radius, config.cube_size, prewarm_color, 0.0
        )
        if instances_data.is_empty():
            skipped.append(type_id)
            continue
        var container: Node3D = _build_multimesh(instances_data, cube_mesh, _get_body_material())
        if container == null:
            skipped.append(type_id)
            continue
        container.pool_type_id = type_id
        container.pool_last_color = prewarm_color
        container.position.y = prewarm_y
        container.visible = true
        add_child(container)
        prewarmed.append(container)



    ghost_mode = prev_ghost_mode



    await get_tree().process_frame
    await get_tree().process_frame

    var pooled: = 0
    var freed: = 0
    for container in prewarmed:
        if not is_instance_valid(container):
            continue
        if _release_to_pool(container):
            pooled += 1
        else:
            container.queue_free()
            freed += 1

    var dt_ms: int = Time.get_ticks_msec() - t0_msec
    print("ObstacleManager: prewarm complete in %d ms - pooled=%d, freed=%d, skipped=%d %s" % [
        dt_ms, pooled, freed, skipped.size(), 
        ("(skipped: " + ", ".join(skipped) + ")") if not skipped.is_empty() else "", 
    ])


func _log_spawn_step(label: String, t0_usec: int) -> void :
    if not _spawn_log_enabled:
        return
    var dt_ms: float = (Time.get_ticks_usec() - t0_usec) / 1000.0
    if dt_ms >= SPAWN_LOG_THRESHOLD_MS:
        print("[SPAWN-PEAK] frame=%d %s took %.2f ms" % [Engine.get_process_frames(), label, dt_ms])


func _spawn_obstacle_at(_logical_r: int, y_pos: float):
    var _spawn_t0: = Time.get_ticks_usec() if _spawn_log_enabled else 0
    safe_path_angle += randf_range(-20.0, 20.0)
    safe_path_angle = fmod(safe_path_angle + 360.0, 360.0)



    var ring_index = int(((50.0 - y_pos) / config.ring_spacing) + ring_origin_offset)

    var cube_mesh = BoxMesh.new()
    cube_mesh.size = Vector3(1, 1, 1) * config.cube_size


    var color = Color.WHITE
    if not beat_palette_colors.is_empty():
        color = beat_palette_colors[active_obstacles.size() % beat_palette_colors.size()]
    elif beat_palette_color is Color:
        color = beat_palette_color
    elif current_theme and not current_theme.palette.is_empty():
        var attempts = 0
        var valid_color = false




        var palette: Array[Color] = []
        if current_substage != null and not current_substage.obstacle_palette.is_empty():
            palette = current_substage.obstacle_palette
        while not valid_color and attempts < 10:
            attempts += 1
            var base_color = current_theme.palette.pick_random()
            if not palette.is_empty():
                color = palette.pick_random()
            else:
                var h = base_color.h + 0.5
                if h > 1.0: h -= 1.0
                color = Color.from_hsv(h, 0.9, 1.0)
            var dist = sqrt(pow(color.r - last_obstacle_color.r, 2) + pow(color.g - last_obstacle_color.g, 2) + pow(color.b - last_obstacle_color.b, 2))
            if dist > 0.2: valid_color = true
    last_obstacle_color = color




    var obs = _generate_obstacle_geometry(y_pos, ring_index, cube_mesh, _get_body_material(), color)
    if obs:
        obs.position.y = y_pos
        obs.base_y = y_pos
        active_obstacles.append(obs)
        add_child(obs)
        print("[SPAWN] Type: Legacy/Cruise | Ring: %d | Y: %.1f" % [ring_index, y_pos])
    _log_spawn_step("_spawn_obstacle_at", _spawn_t0)

func _should_spawn_obstacle(ring_index: int) -> bool:
    if pacing_mode: return false
    if ring_index < config.initial_obstacle_free_rings: return false


    if next_obstacle_interval == -1:
        _calculate_next_interval()

    rings_since_obstacle += 1
    if rings_since_obstacle >= next_obstacle_interval:
        rings_since_obstacle = 0
        _calculate_next_interval()
        return true
    return false

func _calculate_next_interval():


    var calc_speed: float = current_speed
    if interval_lock_speed > 0.0:
        calc_speed = interval_lock_speed


    var scaled_min_time = min_time_between_traps_sec * speed_scaling_factor
    var scaled_min_dist = min_distance_between_traps * speed_scaling_factor
    var scaled_floor = max(1, int(min_rings_floor * speed_scaling_factor))

    var min_rings_by_time: = 0
    var min_rings_by_dist: = 0
    if config:
        if scaled_min_time > 0.0:
            min_rings_by_time = int(ceil((calc_speed * scaled_min_time) / config.ring_spacing))
        if scaled_min_dist > 0.0 and config.ring_spacing > 0.0:
            min_rings_by_dist = int(ceil(scaled_min_dist / config.ring_spacing))
    var min_rings = maxi(min_rings_by_time, min_rings_by_dist)
    min_rings = maxi(min_rings, scaled_floor)

    if override_interval_min != -1 and override_interval_max != -1:
        next_obstacle_interval = randi_range(override_interval_min, override_interval_max)
        next_obstacle_interval = maxi(next_obstacle_interval, min_rings)
        return

    var effective_level = current_level_index
    if manual_level_override != -1: effective_level = manual_level_override
    effective_level = min(effective_level, max_difficulty_level)

    var speed_multiplier = (calc_speed / 28.0) * speed_scaling_factor
    var base = config.base_obstacle_interval * 2 * speed_multiplier
    if effective_level >= 5: base = config.base_obstacle_interval * 1.5 * speed_multiplier
    if effective_level >= 7: base = config.base_obstacle_interval * 1.0 * speed_multiplier







    var physical_min_rings = 8


    var design_min_interval = max(config.min_obstacle_interval * 2 * speed_multiplier, 20 * speed_multiplier)


    base = max(base, design_min_interval)
    base = max(base, physical_min_rings)

    var variance = int(base * 0.2)
    next_obstacle_interval = base + randi_range( - variance, variance)


    next_obstacle_interval = maxi(next_obstacle_interval, min_rings)

func get_first_obstacle_y() -> float:
    if active_obstacles.is_empty(): return - INF

    var first_obs = active_obstacles[0]
    return first_obs.position.y

func _pick_obstacle_type() -> String:
    var total_weight = 0.0
    var choices = []
    for k in type_configs:
        var c = type_configs[k]
        if not c.enabled or c.spawn_weight <= 0.0:
            continue
        total_weight += c.spawn_weight
        choices.append(c)

    if total_weight <= 0.0: return ""

    var roll = randf() * total_weight
    var acc = 0.0
    var chosen_config = null

    for c in choices:
        acc += c.spawn_weight
        if roll <= acc:
            chosen_config = c
            break

    if not chosen_config: chosen_config = choices[0]
    return chosen_config.id
























func _apply_spawn_behavior(container: Node3D, params: Dictionary) -> void :

    var base_rot_speed: float = params.get("base_rot_speed", 0.0)
    var starting_angle: float = params.get("starting_angle_rad", 0.0)
    var is_osc: bool = params.get("oscillate", false)
    container.base_rot_speed = base_rot_speed
    container.current_rot_val = starting_angle
    container.oscillate = is_osc
    if is_osc:
        container.oscillate_amplitude = params.get("oscillate_amplitude", PI * 0.5)
        container.oscillate_phase = params.get("oscillate_phase", 0.0)
    if absf(starting_angle) > 0.001:
        container.rotation.y = - starting_angle


    var anim_type: String = params.get("animation_type", "")
    if anim_type != "":
        container.animation_type = anim_type
        container.animation_speed = params.get("animation_speed", 40.0)
        container.animation_phase = params.get("animation_phase", 0.0)
        if anim_type == "sliding_bar":
            container.slide_amplitude = params.get("slide_amplitude", 8.0)
            container.slide_axis = params.get("slide_axis", "z")


    if params.get("pulse_enabled", false):
        container.pulse_enabled = true
        container.pulse_axis = params.get("pulse_axis", 0)
        container.pulse_speed = params.get("pulse_speed", 1.0)
        container.pulse_amplitude = params.get("pulse_amplitude", 0.0)
        container.pulse_phase = params.get("pulse_phase", 0.0)


    if params.get("random_orientation", false):
        container.random_orientation = true


    container.gap_angle_deg = params.get("gap_angle_deg", 0.0)
    container.gap_width_world = params.get("gap_width_world", 5.0)
    container.obstacle_type_id = params.get("type_id", "")



    container.remove_meta("_loop_flags")


















func setup_mesh_swap(host: Node3D, host_type_id: String, swap_targets: PackedStringArray, 
        period_sec: float, phase_sec: float, color: Color) -> void :
    if not is_instance_valid(host) or swap_targets.is_empty() or period_sec <= 0.001:
        return


    var cycle: = PackedStringArray()
    cycle.append(host_type_id)
    for t in swap_targets:
        cycle.append(t)



    var variant_0: = ObstacleInstance.new()
    variant_0.name = "Variant_0"
    var to_move: Array = []
    for c in host.get_children():
        if c is MultiMeshInstance3D or c is Area3D:
            to_move.append(c)
    host.add_child(variant_0)
    for c in to_move:
        host.remove_child(c)
        variant_0.add_child(c)





    var host_gap_angle_deg: float = host.gap_angle_deg
    var host_gap_width: float = host.gap_width_world
    var variant_gap_meta: Array = []
    variant_gap_meta.append({
        "type_id": host_type_id, 
        "gap_angle_deg": host_gap_angle_deg, 
        "gap_width_world": host_gap_width, 
    })



    var cube_mesh: = BoxMesh.new()
    cube_mesh.size = Vector3.ONE * config.cube_size
    var body_mat: Material = _get_body_material()

    for i in range(swap_targets.size()):
        var t_id: String = swap_targets[i]
        var def: = obstacle_library.get_definition(t_id)
        if def == null or def.filled_cells.is_empty():
            push_warning("ObstacleManager.setup_mesh_swap: missing definition for '%s'" % t_id)
            continue
        var inst_data: Array = def.get_cell_data(
            config.base_radius, config.cube_size, color, 0.0
        )
        if inst_data.is_empty():
            push_warning("ObstacleManager.setup_mesh_swap: empty geometry for '%s'" % t_id)
            continue



        var built: Node3D = _build_multimesh(inst_data, cube_mesh, body_mat)
        var variant_n: = ObstacleInstance.new()
        variant_n.name = "Variant_%d" % (i + 1)
        var built_children: Array = built.get_children()
        for c in built_children:
            built.remove_child(c)
            variant_n.add_child(c)
        built.queue_free()



        variant_n.visible = false
        _set_variant_collision_enabled(variant_n, false)
        host.add_child(variant_n)


        var v_gap_width: = host_gap_width
        var v_meta: = ObstacleDefinitionLibrary.compute_gap_metadata(
            def, config.base_radius, config.cube_size
        )
        if v_meta:
            v_gap_width = v_meta.gap_width_world
        variant_gap_meta.append({
            "type_id": t_id, 
            "gap_angle_deg": host_gap_angle_deg, 
            "gap_width_world": v_gap_width, 
        })




    if variant_gap_meta.size() <= 1:
        return
    while cycle.size() > variant_gap_meta.size():
        cycle.remove_at(cycle.size() - 1)

    host.swap_enabled = true
    host.swap_cycle = cycle
    host.swap_variant_count = cycle.size()
    host.swap_variant_gap_meta = variant_gap_meta
    host.swap_period_sec = period_sec
    host.swap_phase_sec = phase_sec
    host.swap_time = 0.0
    host.swap_active_index = -1




    host.swap_targets = swap_targets
    host.swap_host_type_id = host_type_id


    host.remove_meta("_loop_flags")

    var initial_idx: int = _compute_swap_variant_index(0.0, phase_sec, period_sec, cycle.size())
    _set_active_swap_variant(host, initial_idx)




static func _compute_swap_variant_index(swap_time: float, phase_sec: float, 
        period_sec: float, count: int) -> int:
    if count <= 0 or period_sec <= 0.001:
        return 0
    var idx: int = int(floor((swap_time + phase_sec) / period_sec)) % count
    if idx < 0:
        idx += count
    return idx





func _set_variant_collision_enabled(variant_node: Node3D, enabled: bool) -> void :
    var should_enable: = enabled and not ghost_mode
    for c in variant_node.get_children():
        if c is Area3D:
            var area: = c as Area3D
            if should_enable:
                area.collision_layer = 4
                area.collision_mask = 2
                area.monitorable = true
                area.monitoring = true
            else:
                area.collision_layer = 0
                area.collision_mask = 0
                area.monitorable = false
                area.monitoring = false







func _set_active_swap_variant(host: Node3D, idx: int) -> void :
    var current: int = host.swap_active_index
    if current == idx:
        return
    var newly_active: Node3D = null
    for c in host.get_children():
        if c is Node3D:
            var name_str: String = c.name
            if name_str.begins_with("Variant_"):
                var n_idx: int = name_str.trim_prefix("Variant_").to_int()
                var active: bool = n_idx == idx
                c.visible = active
                _set_variant_collision_enabled(c, active)
                if active:
                    newly_active = c
    host.swap_active_index = idx


    if newly_active != null:
        _restore_variant_pristine_colors(newly_active)

    var gap_meta: Array = host.swap_variant_gap_meta
    if idx >= 0 and idx < gap_meta.size():
        var entry: Dictionary = gap_meta[idx]
        host.gap_angle_deg = entry.get("gap_angle_deg", 0.0)
        host.gap_width_world = entry.get("gap_width_world", 5.0)
        host.obstacle_type_id = entry.get("type_id", "")





const SWAP_TELEGRAPH_SEC: float = 0.3
const SWAP_TELEGRAPH_FLASH_COUNT: int = 3






func _update_swap_flash(host: Node3D, s_time: float, s_phase: float, 
        s_period: float, active_idx: int) -> void :
    var t_in_period: float = fposmod(s_time + s_phase, s_period)
    var t_to_swap: float = s_period - t_in_period
    var window: float = minf(SWAP_TELEGRAPH_SEC, s_period * 0.5)

    var flash_amount: float = 0.0
    if t_to_swap < window and window > 0.001:

        var progress: float = 1.0 - (t_to_swap / window)



        var phase: float = progress * float(SWAP_TELEGRAPH_FLASH_COUNT) * PI
        flash_amount = absf(sin(phase))

    var was_flashing: bool = host._swap_flashing
    if flash_amount > 0.001:
        _apply_variant_flash(host, active_idx, flash_amount)
        host._swap_flashing = true
    elif was_flashing:


        _apply_variant_flash(host, active_idx, 0.0)
        host._swap_flashing = false






func _apply_variant_flash(host: Node3D, active_idx: int, flash_amount: float) -> void :
    var target_name: String = "Variant_%d" % active_idx
    var variant_node: Node3D = null
    for c in host.get_children():
        if c is Node3D and (c as Node3D).name == target_name:
            variant_node = c as Node3D
            break
    if variant_node == null:
        return
    for c in variant_node.get_children():
        if c is MultiMeshInstance3D:
            var mmi: = c as MultiMeshInstance3D
            var mm: MultiMesh = mmi.multimesh
            if mm == null or not mm.use_colors:
                continue

            if not mmi.has_meta("_swap_original_colors"):
                var snap: = PackedColorArray()
                for i in range(mm.instance_count):
                    snap.append(mm.get_instance_color(i))
                mmi.set_meta("_swap_original_colors", snap)
            var originals: PackedColorArray = mmi.get_meta("_swap_original_colors")
            var n: int = mini(mm.instance_count, originals.size())
            for i in range(n):
                mm.set_instance_color(i, originals[i].lerp(Color.WHITE, flash_amount))





func _restore_variant_pristine_colors(variant_node: Node3D) -> void :
    for c in variant_node.get_children():
        if c is MultiMeshInstance3D:
            var mmi: = c as MultiMeshInstance3D
            if not mmi.has_meta("_swap_original_colors"):
                continue
            var mm: MultiMesh = mmi.multimesh
            if mm == null or not mm.use_colors:
                continue
            var originals: PackedColorArray = mmi.get_meta("_swap_original_colors")
            var n: int = mini(mm.instance_count, originals.size())
            for i in range(n):
                mm.set_instance_color(i, originals[i])





func _get_swap_preview_material() -> StandardMaterial3D:
    if _swap_preview_material == null:
        var m: = StandardMaterial3D.new()
        m.albedo_color = Color(1.0, 0.15, 0.15, 0.55)
        m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
        m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
        m.cull_mode = BaseMaterial3D.CULL_DISABLED
        _swap_preview_material = m
    return _swap_preview_material









func _update_swap_preview(host: Node3D, s_time: float, s_phase: float, 
        s_period: float, active_idx: int, count: int) -> void :
    if count <= 1:
        return
    var t_in_period: float = fposmod(s_time + s_phase, s_period)
    var t_to_swap: float = s_period - t_in_period
    var window: float = minf(SWAP_TELEGRAPH_SEC, s_period * 0.5)
    var in_window: bool = t_to_swap < window and window > 0.001
    var next_idx: int = (active_idx + 1) % count
    var current_preview: int = host._swap_preview_idx

    if in_window:
        if current_preview != next_idx:
            if current_preview >= 0:
                _clear_variant_preview(host, current_preview)
            _apply_variant_preview(host, next_idx)
            host._swap_preview_idx = next_idx
    elif current_preview >= 0:
        _clear_variant_preview(host, current_preview)
        host._swap_preview_idx = -1


func _find_swap_variant(host: Node3D, idx: int) -> Node3D:
    var target_name: String = "Variant_%d" % idx
    for c in host.get_children():
        if c is Node3D and (c as Node3D).name == target_name:
            return c as Node3D
    return null






func _apply_variant_preview(host: Node3D, idx: int) -> void :
    var variant: Node3D = _find_swap_variant(host, idx)
    if variant == null:
        return
    variant.visible = true
    var preview_mat: = _get_swap_preview_material()
    for c in variant.get_children():
        if c is MultiMeshInstance3D:
            var mmi: = c as MultiMeshInstance3D
            if not mmi.has_meta("_preview_orig_override"):
                mmi.set_meta("_preview_orig_override", mmi.material_override)
            mmi.material_override = preview_mat





func _clear_variant_preview(host: Node3D, idx: int) -> void :
    var variant: Node3D = _find_swap_variant(host, idx)
    if variant == null:
        return
    for c in variant.get_children():
        if c is MultiMeshInstance3D:
            var mmi: = c as MultiMeshInstance3D
            if mmi.has_meta("_preview_orig_override"):
                mmi.material_override = mmi.get_meta("_preview_orig_override")
                mmi.remove_meta("_preview_orig_override")
    var active_idx: int = host.swap_active_index
    if idx != active_idx:
        variant.visible = false


func _generate_obstacle_geometry(y_pos: float, ring_index: int, mesh: Mesh, mat: Material, color: Color) -> Node3D:
    var instances_data: Array = []
    var type_id = _pick_obstacle_type()
    if type_id == "" or not type_configs.has(type_id):
        return null
    var conf: ObstacleTypeConfig = type_configs[type_id]
    var container: Node3D


    if type_id == "sliding_bar":
        var bar_angle: = 0.0 if randf() > 0.5 else 90.0
        var slide_axis: = "z" if bar_angle == 0.0 else "x"
        var bar_def: = obstacle_library.get_definition(type_id)
        var bar_data: Array = []
        if bar_def and not bar_def.filled_cells.is_empty():
            bar_data = bar_def.get_cell_data_rotated(
                config.base_radius, config.cube_size, color, bar_angle, 0.0
            )
        if bar_data.is_empty():
            return null
        container = _build_multimesh(bar_data, mesh, mat)
        _apply_spawn_behavior(container, {
            "type_id": type_id, 
            "gap_angle_deg": safe_path_angle, 
            "gap_width_world": _compute_gap_width_for_type(type_id), 
            "animation_type": "sliding_bar", 
            "animation_speed": randf_range(20.0, 60.0), 
            "animation_phase": randf() * TAU, 
            "slide_amplitude": 8.0, 
            "slide_axis": slide_axis, 
        })
        return container

    _generate_shape_data(conf, y_pos, color, instances_data, ring_index)
    if instances_data.is_empty():
        return null

    container = _build_multimesh(instances_data, mesh, mat)


    var params: Dictionary = {
        "type_id": type_id, 
        "gap_angle_deg": safe_path_angle, 
        "gap_width_world": _compute_gap_width_for_type(type_id), 
    }

    if type_id == "sweeper_bar" or type_id == "windmill":

        var rs: = randf_range(0.5, 1.5)
        if randf() > 0.5:
            rs = - rs
        params["base_rot_speed"] = rs
    else:



        if randf() < conf.oscillate_chance:
            params["oscillate"] = true
            params["base_rot_speed"] = randf_range(conf.oscillate_speed_min, conf.oscillate_speed_max)
        elif randf() < conf.rotation_chance:
            var rs: = randf_range(conf.rotation_speed_min, conf.rotation_speed_max)
            if randf() > 0.5:
                rs = - rs
            params["base_rot_speed"] = rs

    _apply_spawn_behavior(container, params)
    return container




func spawn_cruise_obstacle(y_pos: float, type_id: String, p_spin_chance: float, 
        spin_speed_range: Vector2, gap_scale: float, angle_override: float = -1.0) -> Dictionary:
    var _cruise_t0: = Time.get_ticks_usec() if _spawn_log_enabled else 0

    if angle_override >= 0.0:
        safe_path_angle = fmod(angle_override, 360.0)
    else:
        safe_path_angle += randf_range(-20.0, 20.0)
        safe_path_angle = fmod(safe_path_angle + 360.0, 360.0)

    var ring_index = int(((50.0 - y_pos) / config.ring_spacing) + ring_origin_offset)

    var cube_mesh = BoxMesh.new()
    cube_mesh.size = Vector3(1, 1, 1) * config.cube_size


    var color = Color.WHITE
    if not beat_palette_colors.is_empty():
        color = beat_palette_colors[active_obstacles.size() % beat_palette_colors.size()]
    elif beat_palette_color is Color:
        color = beat_palette_color
    elif current_theme and not current_theme.palette.is_empty():
        var attempts = 0
        var valid_color = false




        var palette: Array[Color] = []
        if current_substage != null and not current_substage.obstacle_palette.is_empty():
            palette = current_substage.obstacle_palette
        while not valid_color and attempts < 10:
            attempts += 1
            var base_color = current_theme.palette.pick_random()
            if not palette.is_empty():
                color = palette.pick_random()
            else:
                var h = base_color.h + 0.5
                if h > 1.0: h -= 1.0
                color = Color.from_hsv(h, 0.9, 1.0)
            var dist = sqrt(pow(color.r - last_obstacle_color.r, 2) + pow(color.g - last_obstacle_color.g, 2) + pow(color.b - last_obstacle_color.b, 2))
            if dist > 0.2: valid_color = true
    last_obstacle_color = color


    var container: Node3D
    var sliding_bar_axis: String = ""
    if type_id == "sliding_bar":

        var bar_angle: = 0.0 if randf() > 0.5 else 90.0
        sliding_bar_axis = "z" if bar_angle == 0.0 else "x"
        var bar_def: = obstacle_library.get_definition(type_id)
        var bar_data: Array = []
        if bar_def and not bar_def.filled_cells.is_empty():
            bar_data = bar_def.get_cell_data_rotated(
                config.base_radius, config.cube_size, color, bar_angle, 0.0
            )
        if bar_data.is_empty():
            return {}
        container = _build_multimesh(bar_data, cube_mesh, _get_body_material())
    else:

        container = _try_acquire_pooled_obstacle(type_id, color)
        if container == null:

            var instances_data: Array = []
            if type_configs.has(type_id):
                var conf: ObstacleTypeConfig = type_configs[type_id]
                _generate_shape_data(conf, y_pos, color, instances_data, ring_index)
            else:

                var def: = obstacle_library.get_definition(type_id)
                if def and not def.filled_cells.is_empty():
                    instances_data = def.get_cell_data(
                        config.base_radius, config.cube_size, color, 0.0
                    )

            if instances_data.is_empty():
                return {}

            container = _build_multimesh(instances_data, cube_mesh, _get_body_material())
            container.pool_type_id = type_id
            container.pool_last_color = color


    var gap_angle_rad = deg_to_rad(safe_path_angle)
    var gap_center: Vector2
    var gap_width: float
    var cruise_def: = obstacle_library.get_definition(type_id)
    if cruise_def:
        var gap_meta: = ObstacleDefinitionLibrary.compute_gap_metadata(cruise_def, config.base_radius, config.cube_size)
        gap_width = gap_meta.gap_width_world * gap_scale

        var gc: Vector2 = gap_meta.gap_center
        var cos_a: = cos(gap_angle_rad)
        var sin_a: = sin(gap_angle_rad)
        gap_center = Vector2(gc.x * cos_a - gc.y * sin_a, gc.x * sin_a + gc.y * cos_a)
    else:
        var gap_dist: float = config.base_radius * 0.5 if config else 4.0
        gap_center = Vector2(cos(gap_angle_rad) * gap_dist, sin(gap_angle_rad) * gap_dist)
        var base_gap_width: float = (config.safe_zone_width / 360.0) * (2.0 * PI * config.base_radius) if config else 5.0
        gap_width = base_gap_width * gap_scale


    var behavior: Dictionary = {
        "type_id": type_id, 
        "gap_angle_deg": safe_path_angle, 
        "gap_width_world": gap_width, 
    }

    if type_id == "sliding_bar":
        behavior["animation_type"] = "sliding_bar"
        behavior["animation_speed"] = randf_range(20.0, 60.0)
        behavior["animation_phase"] = randf() * TAU
        behavior["slide_amplitude"] = 8.0
        behavior["slide_axis"] = sliding_bar_axis
    else:

        var conf_entry: ObstacleTypeConfig = type_configs.get(type_id) as ObstacleTypeConfig
        var eff_spin_chance: float = p_spin_chance
        var eff_spin_min: float = spin_speed_range.x
        var eff_spin_max: float = spin_speed_range.y
        if conf_entry:
            eff_spin_chance = conf_entry.rotation_chance
            eff_spin_min = conf_entry.rotation_speed_min
            eff_spin_max = conf_entry.rotation_speed_max

        var rot_speed: = 0.0
        if randf() < eff_spin_chance:
            rot_speed = randf_range(eff_spin_min, eff_spin_max)
            if randf() > 0.5:
                rot_speed = - rot_speed
        behavior["base_rot_speed"] = rot_speed






        if conf_entry and conf_entry.oscillate_chance > 0.0 and randf() < conf_entry.oscillate_chance:
            behavior["oscillate"] = true
            behavior["base_rot_speed"] = randf_range(conf_entry.oscillate_speed_min, conf_entry.oscillate_speed_max)

        if conf_entry and conf_entry.random_orientation:
            behavior["random_orientation"] = true


    if type_id == "sweeper_bar" or type_id == "windmill":
        var base: float = behavior.get("base_rot_speed", 0.0)
        if absf(base) < 0.001:
            base = randf_range(0.5, 1.5)
            if randf() > 0.5:
                base = - base
        behavior["base_rot_speed"] = base
        behavior["oscillate"] = false


    if angle_override >= 0.0:
        behavior["starting_angle_rad"] = deg_to_rad(angle_override)


    container.position.y = y_pos
    container.base_y = y_pos
    _apply_spawn_behavior(container, behavior)
    active_obstacles.append(container)
    add_child(container)

    _log_spawn_step("spawn_cruise_obstacle(type=%s)" % type_id, _cruise_t0)
    return {"gap_center": gap_center, "gap_width_world": gap_width}



func _compute_gap_width_for_type(p_type_id: String, p_gap_scale: float = 1.0) -> float:
    var def: = obstacle_library.get_definition(p_type_id)
    if def:
        var gap_meta: = ObstacleDefinitionLibrary.compute_gap_metadata(def, config.base_radius, config.cube_size)
        return gap_meta.gap_width_world * p_gap_scale

    var base_gap_width: float = (config.safe_zone_width / 360.0) * (2.0 * PI * config.base_radius) if config else 5.0
    return base_gap_width * p_gap_scale


func get_angle_avoiding_safe_path() -> float:
    var offset = randf_range(30.0, 150.0)
    if randi() % 2 == 0:
        offset = - offset
    return fmod(safe_path_angle + offset + 360.0, 360.0)

func is_near_safe_path(angle: float) -> bool:
    var diff = abs(angle - safe_path_angle)
    diff = min(diff, 360.0 - diff)
    return diff < (config.safe_zone_width * 0.5 if config else 45.0)

func _generate_shape_data(conf: ObstacleTypeConfig, _y_pos: float, color: Color, data: Array, _ring_idx: int):


    var def: = obstacle_library.get_definition(conf.id)
    if def and not def.filled_cells.is_empty():
        var generated: = def.get_cell_data(
            config.base_radius, config.cube_size, color, 0.0
        )
        data.append_array(generated)
        return


    push_warning("ObstacleManager: Definition not found for type '%s', skipping" % conf.id)

func _build_multimesh(data: Array, mesh: Mesh, mat: Material) -> Node3D:
    var _bm_t0: = Time.get_ticks_usec() if _spawn_log_enabled else 0
    var container = ObstacleInstance.new()

    var main_instances = []
    var edge_instances = []


    var positions = {}
    for d in data:
        var key = Vector3(round(d.pos.x), round(d.pos.y), round(d.pos.z))
        positions[key] = true

    var cube_step = config.cube_size
    var width = current_edge_width






    for i in range(data.size()):
        var d = data[i]
        var p = d.pos






        var seed_val = _local_rng.randf()
        var custom_color = Color(seed_val, 0, 0, 0)


        main_instances.append({
            "trans": Transform3D(Basis(), p), 
            "color": d.color, 
            "custom": custom_color
        })



        if not positions.has(Vector3(round(p.x + cube_step), round(p.y), round(p.z))):
            var t = Transform3D()
            t.basis = t.basis.scaled(Vector3(width, 1.0, 1.0))
            t.origin = p + Vector3(cube_step * 0.5 + width * 0.5, 0, 0)
            edge_instances.append({"trans": t, "color": d.color, "custom": custom_color})


        if not positions.has(Vector3(round(p.x - cube_step), round(p.y), round(p.z))):
            var t = Transform3D()
            t.basis = t.basis.scaled(Vector3(width, 1.0, 1.0))
            t.origin = p + Vector3( - cube_step * 0.5 - width * 0.5, 0, 0)
            edge_instances.append({"trans": t, "color": d.color, "custom": custom_color})


        if not positions.has(Vector3(round(p.x), round(p.y), round(p.z + cube_step))):
            var t = Transform3D()
            t.basis = t.basis.scaled(Vector3(1.0, 1.0, width))
            t.origin = p + Vector3(0, 0, cube_step * 0.5 + width * 0.5)
            edge_instances.append({"trans": t, "color": d.color, "custom": custom_color})


        if not positions.has(Vector3(round(p.x), round(p.y), round(p.z - cube_step))):
            var t = Transform3D()
            t.basis = t.basis.scaled(Vector3(1.0, 1.0, width))
            t.origin = p + Vector3(0, 0, - cube_step * 0.5 - width * 0.5)
            edge_instances.append({"trans": t, "color": d.color, "custom": custom_color})


    if not main_instances.is_empty():
        var mm = MultiMesh.new()
        mm.transform_format = MultiMesh.TRANSFORM_3D
        mm.use_colors = true
        mm.use_custom_data = true
        mm.mesh = mesh
        mm.instance_count = main_instances.size()
        for i in range(main_instances.size()):
            mm.set_instance_transform(i, main_instances[i].trans)
            mm.set_instance_color(i, main_instances[i].color)
            mm.set_instance_custom_data(i, main_instances[i].custom)

        var mmi = MultiMeshInstance3D.new()
        mmi.multimesh = mm
        mmi.material_override = mat
        mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


        mmi.set_layer_mask_value(1, false)
        mmi.set_layer_mask_value(2, true)
        container.add_child(mmi)


    if not edge_instances.is_empty():
        var mm = MultiMesh.new()
        mm.transform_format = MultiMesh.TRANSFORM_3D
        mm.use_colors = true
        mm.use_custom_data = true
        mm.mesh = mesh
        mm.instance_count = edge_instances.size()
        for i in range(edge_instances.size()):
            mm.set_instance_transform(i, edge_instances[i].trans)
            mm.set_instance_color(i, edge_instances[i].color)
            mm.set_instance_custom_data(i, edge_instances[i].custom)

        var mmi = MultiMeshInstance3D.new()
        mmi.multimesh = mm
        mmi.material_override = shared_edge_mat
        mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


        mmi.set_layer_mask_value(1, false)
        mmi.set_layer_mask_value(2, true)
        container.add_child(mmi)



    var area = Area3D.new()
    area.collision_layer = 0 if ghost_mode else 4
    area.collision_mask = 0 if ghost_mode else 2
    area.monitorable = not ghost_mode
    area.monitoring = not ghost_mode
    area.add_to_group("Obstacles")
    container.add_child(area)
    container.collision_area = area


    var shared_cube_shape: BoxShape3D = null
    if not ghost_mode:
        shared_cube_shape = _get_shared_box_shape(Vector3(1.0, 1.0, 1.0) * config.cube_size)
    var hit_positions: = PackedVector3Array()
    for i in range(data.size()):
        var p = data[i].pos
        var key = Vector3(round(p.x), round(p.y), round(p.z))

        var is_edge: = false
        for offset in [Vector3(cube_step, 0, 0), Vector3( - cube_step, 0, 0), 
                       Vector3(0, cube_step, 0), Vector3(0, - cube_step, 0), 
                       Vector3(0, 0, cube_step), Vector3(0, 0, - cube_step)]:
            if not positions.has(Vector3(round(key.x + offset.x), round(key.y + offset.y), round(key.z + offset.z))):
                is_edge = true
                break
        if is_edge:
            if not ghost_mode:
                var col = CollisionShape3D.new()
                col.shape = shared_cube_shape
                col.position = p
                area.add_child(col)
            hit_positions.append(p)





    container.hit_box_positions = hit_positions
    container.hit_box_half_size = Vector3.ONE * (0.5 * config.cube_size)
    _log_spawn_step("_build_multimesh(cubes=%d)" % data.size(), _bm_t0)
    return container









const _HIT_CHECK_Y_PROXIMITY: float = 1.5

func check_sphere_hit(global_pos: Vector3, radius: float, sweep_prev_pos: Vector3 = Vector3.INF, sweep_total_move: float = 0.0) -> Dictionary:
    var radius_sq: float = radius * radius
    var do_sweep: bool = sweep_total_move > 0.001 and sweep_prev_pos.x != INF

    for obs in active_obstacles:
        if not is_instance_valid(obs):
            continue

        if do_sweep:
            var end_rel_y: float = global_pos.y - obs.position.y
            var start_rel_y: float = end_rel_y + sweep_total_move

            if end_rel_y > _HIT_CHECK_Y_PROXIMITY or start_rel_y < - _HIT_CHECK_Y_PROXIMITY:
                continue

            var t: float = clampf(start_rel_y / sweep_total_move, 0.0, 1.0)
            var interp_pos: Vector3 = sweep_prev_pos.lerp(global_pos, t)

            var result: Dictionary = _check_hit_direct(obs, interp_pos, radius_sq)
            if not result.is_empty():
                return result
        else:
            if absf(global_pos.y - obs.position.y) > _HIT_CHECK_Y_PROXIMITY:
                continue
            var result: Dictionary = _check_hit_direct(obs, global_pos, radius_sq)
            if not result.is_empty():
                return result

    return {}


func _check_hit_direct(obs: ObstacleInstance, global_pos: Vector3, radius_sq: float) -> Dictionary:
    var area: = obs.collision_area
    if not area or area.collision_layer == 0:
        return {}
        
    var area_xform: Transform3D = area.global_transform
    var player_local: Vector3 = area_xform.affine_inverse() * global_pos
    var px: float = player_local.x
    var pz: float = player_local.z

    var positions: PackedVector3Array = obs.hit_box_positions
    if positions.size() > 0:
        var hs: Vector3 = obs.hit_box_half_size
        var hx: float = hs.x
        var hy: float = hs.y
        var hz: float = hs.z
        for i in range(positions.size()):
            var cp: Vector3 = positions[i]
            var dx: float = maxf(0.0, absf(px - cp.x) - hx)
            var dz: float = maxf(0.0, absf(pz - cp.z) - hz)
            if dx * dx + dz * dz < radius_sq:
                var nearest_local: = Vector3(
                    clampf(player_local.x, cp.x - hx, cp.x + hx), 
                    clampf(player_local.y, cp.y - hy, cp.y + hy), 
                    clampf(player_local.z, cp.z - hz, cp.z + hz)
                )
                return {"area": area, "contact": area_xform * nearest_local}
        return {}

    # Fallback to children search if somehow properties are missing (e.g. legacy/source)
    return _check_hit_in_node(obs, global_pos, radius_sq)










func check_graze_tiers(global_pos: Vector3, near_r: float, dare_r: float, death_r: float) -> Array:
    var results: Array = []
    var near_sq: float = near_r * near_r
    var dare_sq: float = dare_r * dare_r
    var death_sq: float = death_r * death_r
    var y_proximity: float = _HIT_CHECK_Y_PROXIMITY + near_r

    for obs in active_obstacles:
        if not is_instance_valid(obs):
            continue
        if absf(global_pos.y - obs.position.y) > y_proximity:
            continue
        var hit: Dictionary = _closest_area_dist_sq(obs, global_pos, near_sq)
        if hit.is_empty():
            continue
        var d_sq: float = hit.dist_sq
        var tier: int = 1
        if d_sq < dare_sq:
            tier = 2
        if d_sq < death_sq:
            tier = 3
        results.append({"area": hit.area, "tier": tier})
    return results





func _closest_area_dist_sq(node: Node, global_pos: Vector3, cap_sq: float) -> Dictionary:
    var state: Array = [cap_sq, null]
    _walk_for_closest_area(node, null, global_pos, state)
    if state[1]:
        return {"area": state[1], "dist_sq": state[0]}
    return {}


func _walk_for_closest_area(node: Node, current_area: Area3D, global_pos: Vector3, state: Array) -> void :
    var area_for_children: Area3D = current_area
    if node is ObstacleInstance:
        var obs: = node as ObstacleInstance
        area_for_children = obs.collision_area
        if not area_for_children or area_for_children.collision_layer == 0:
            return

        var positions: PackedVector3Array = obs.hit_box_positions
        if positions.size() > 0:
            var hs_fast: Vector3 = obs.hit_box_half_size
            var hx: float = hs_fast.x
            var hy: float = hs_fast.y
            var hz: float = hs_fast.z
            var player_local: Vector3 = area_for_children.global_transform.affine_inverse() * global_pos
            var lpx: float = player_local.x
            var lpy: float = player_local.y
            var lpz: float = player_local.z
            for i in range(positions.size()):
                var cp: Vector3 = positions[i]
                var dx: float = maxf(0.0, absf(lpx - cp.x) - hx)
                var dy: float = maxf(0.0, absf(lpy - cp.y) - hy)
                var dz: float = maxf(0.0, absf(lpz - cp.z) - hz)
                var d_sq: float = dx * dx + dy * dy + dz * dz
                if d_sq < state[0]:
                    state[0] = d_sq
                    state[1] = area_for_children
            return
    
    # Generic node traversal for non-ObstacleInstance cases (e.g. debris)
    if node is Area3D:
        area_for_children = node as Area3D
        if area_for_children.collision_layer == 0:
            return

    for child in node.get_children():
        if child is CollisionShape3D and area_for_children:
            var col: = child as CollisionShape3D
            var shape = col.shape
            if shape is BoxShape3D:
                var xf: Transform3D = col.global_transform
                var local_player: Vector3 = xf.affine_inverse() * global_pos
                var hs: Vector3 = shape.size * 0.5
                var dx_f: float = maxf(0.0, absf(local_player.x) - hs.x)
                var dy_f: float = maxf(0.0, absf(local_player.y) - hs.y)
                var dz_f: float = maxf(0.0, absf(local_player.z) - hs.z)
                var d_sq_f: float = dx_f * dx_f + dy_f * dy_f + dz_f * dz_f
                if d_sq_f < state[0]:
                    state[0] = d_sq_f
                    state[1] = area_for_children
        elif child is Node3D:
            _walk_for_closest_area(child, area_for_children, global_pos, state)







func is_world_point_visible(world_point: Vector3) -> bool:
    var cam: = get_viewport().get_camera_3d()
    if not cam:
        return true
    return cam.is_position_in_frustum(world_point)








func closest_point_on_collider(node: Node3D, player_global_pos: Vector3) -> Vector3:
    var state: Array = [INF, node.global_position]
    _collect_closest_point_recursive(node, player_global_pos, state)
    return state[1]


func _collect_closest_point_recursive(node: Node, player_global_pos: Vector3, state: Array) -> void :
    if node is ObstacleInstance:
        var obs: = node as ObstacleInstance
        var area: = obs.collision_area
        if not area: return
        
        var positions: PackedVector3Array = obs.hit_box_positions
        if positions.size() > 0:
            var hs_fast: Vector3 = obs.hit_box_half_size
            var hx: float = hs_fast.x
            var hy: float = hs_fast.y
            var hz: float = hs_fast.z
            var area_xform: Transform3D = area.global_transform
            var local_player_fast: Vector3 = area_xform.affine_inverse() * player_global_pos
            for i in range(positions.size()):
                var cp: Vector3 = positions[i]
                var nearest_local_fast: = Vector3(
                    clampf(local_player_fast.x, cp.x - hx, cp.x + hx), 
                    clampf(local_player_fast.y, cp.y - hy, cp.y + hy), 
                    clampf(local_player_fast.z, cp.z - hz, cp.z + hz)
                )
                var d_sq_fast: = nearest_local_fast.distance_squared_to(local_player_fast)
                if d_sq_fast < state[0]:
                    state[0] = d_sq_fast
                    state[1] = area_xform * nearest_local_fast
            return

    for child in node.get_children():
        if child is CollisionShape3D:
            var col: = child as CollisionShape3D
            var shape = col.shape
            if shape is BoxShape3D:
                var xf: Transform3D = col.global_transform
                var local_player: Vector3 = xf.affine_inverse() * player_global_pos
                var hs: Vector3 = shape.size * 0.5
                var nearest_local: = Vector3(
                    clampf(local_player.x, - hs.x, hs.x), 
                    clampf(local_player.y, - hs.y, hs.y), 
                    clampf(local_player.z, - hs.z, hs.z)
                )
                var d_sq: = nearest_local.distance_squared_to(local_player)
                if d_sq < state[0]:
                    state[0] = d_sq
                    state[1] = xf * nearest_local
            continue
        if child is Node3D:
            _collect_closest_point_recursive(child, player_global_pos, state)




func would_sphere_overlap_obstacles(global_origin: Vector3, radius: float) -> bool:
    var radius_sq: = radius * radius
    var y_margin: = 8.0
    for obs in active_obstacles:
        if abs(obs.position.y - global_origin.y) > y_margin:
            continue
        var area: Area3D = null
        for c in obs.get_children():
            if c is Area3D:
                area = c
                break
        if not area:
            continue
        for node in area.get_children():
            if not node is CollisionShape3D:
                continue
            var col: = node as CollisionShape3D
            var shape = col.shape
            if not shape is BoxShape3D:
                continue
            var box: = shape as BoxShape3D
            var half: = box.size * 0.5
            var col_tr: = col.global_transform
            var corners: = [
                col_tr * Vector3( - half.x, - half.y, - half.z), 
                col_tr * Vector3(half.x, - half.y, - half.z), 
                col_tr * Vector3( - half.x, half.y, - half.z), 
                col_tr * Vector3(half.x, half.y, - half.z), 
                col_tr * Vector3( - half.x, - half.y, half.z), 
                col_tr * Vector3(half.x, - half.y, half.z), 
                col_tr * Vector3( - half.x, half.y, half.z), 
                col_tr * Vector3(half.x, half.y, half.z), 
            ]
            var min_v: Vector3 = corners[0]
            var max_v: Vector3 = corners[0]
            for c in corners:
                min_v = min_v.min(c)
                max_v = max_v.max(c)
            var aabb: = AABB(min_v, max_v - min_v)
            var closest: = Vector3(
                clampf(global_origin.x, aabb.position.x, aabb.position.x + aabb.size.x), 
                clampf(global_origin.y, aabb.position.y, aabb.position.y + aabb.size.y), 
                clampf(global_origin.z, aabb.position.z, aabb.position.z + aabb.size.z)
            )
            if global_origin.distance_squared_to(closest) <= radius_sq:
                return true
    return false

func _on_level_started(idx: int, theme: Resource):
    current_level_index = idx
    current_theme = theme

    rings_since_obstacle = 0
    last_checked_ring = 0
    _cleanup_obstacles(100.0)




    if idx != -1:
        _clear_obstacle_pool()

    if theme:



        var td: Dictionary = _cached_theme_overrides
        for mat in [shared_obstacle_mat, shared_obstacle_mat_opaque, shared_edge_mat]:
            if not mat:
                continue
            mat.set_shader_parameter("metallic", theme.metallic_intensity)
            mat.set_shader_parameter("surface_roughness", theme.wall_roughness)
            mat.set_shader_parameter("surface_anims_amount", td.get("surface_anims_amount", 0.0))


        var t_exp: float = td.get("tunnel_expansion", 0.0)
        for mat in [shared_obstacle_mat, shared_obstacle_mat_opaque, shared_edge_mat]:
            if mat:
                mat.set_shader_parameter("tunnel_expansion", t_exp)


    if manual_level_override == -1:
        refresh_difficulty_weights(idx)


    if encounter_sequencer and current_theme:
        encounter_sequencer.set_theme(current_theme)

    print("ObstacleManager: Level Started %d with theme" % idx)
    _warm_up_debris_shader()






func set_active_substage(substage: SubStageDef) -> void :
    current_substage = substage
    if encounter_sequencer:
        encounter_sequencer.set_active_substage(substage)

func _on_origin_shifted(amount: float):
    for obs in active_obstacles:
        obs.position.y += amount
        var old_base = obs.base_y
        obs.base_y = old_base + amount

    var ring_shift = int(amount / config.ring_spacing)
    last_checked_ring = max(0, last_checked_ring - ring_shift)

    if encounter_sequencer:
        encounter_sequencer.on_origin_shifted(ring_shift)










func setup_encounter_system(_initial_difficulty: float = 0.3) -> void :
    pass

func enable_encounter_system(_start_ring: int = -1) -> void :
    pass

func disable_encounter_system() -> void :
    use_encounter_system = false

func set_encounter_difficulty(_d: float) -> void :
    pass


func shatter_obstacle(obstacle_area: Area3D, hit_point: Vector3, forward_speed: float) -> void :
    var st0 = Time.get_ticks_usec()
    var container = obstacle_area.get_parent()
    if not container or container.is_queued_for_deletion():
        return


    var _lane_manager = get_tree().get_first_node_in_group("LaneManager")


    if active_obstacles.has(container):
        active_obstacles.erase(container)

    var cube_step = config.cube_size if config else 2.0
    var shatter_count = 0
    var max_shatter = 25
    var st1 = Time.get_ticks_usec()


    var main_mmi: MultiMeshInstance3D = null
    for child in container.get_children():
        if child is MultiMeshInstance3D and child.visible:
            main_mmi = child
            break

    var debris_create_us: int = 0
    var debris_addchild_us: int = 0
    var debris_setup_us: int = 0

    if main_mmi and main_mmi.multimesh:
        var mm = main_mmi.multimesh
        for i in range(mm.instance_count):
            var local_trans = mm.get_instance_transform(i)
            var global_pos = container.to_global(local_trans.origin)

            var dist = global_pos.distance_to(hit_point)

            if dist < 10.0 or mm.instance_count < 15:
                if shatter_count >= max_shatter: break

                var color = mm.get_instance_color(i)
                var dc0 = Time.get_ticks_usec()
                var debris = RigidBody3D.new()
                debris.set_script(debris_script)
                var dc1 = Time.get_ticks_usec()

                get_tree().current_scene.add_child(debris)
                var dc2 = Time.get_ticks_usec()



                var tangent = Vector3(0, -1, 0)
                if _lane_manager:
                    var next_y = global_pos.y - 10.0
                    var off_now = _lane_manager.get_dynamic_offset(global_pos.y, last_cam_y)
                    var off_next = _lane_manager.get_dynamic_offset(next_y, last_cam_y)
                    tangent = Vector3(off_next.x - off_now.x, -10.0, off_next.y - off_now.y).normalized()




                var shatter_speed = maxf(forward_speed, 50.0)
                var fwd_speed = shatter_speed * randf_range(1.8, 2.8)


                var up_guess: Vector3 = Vector3.RIGHT if absf(tangent.dot(Vector3.RIGHT)) < 0.9 else Vector3.FORWARD
                var perp_a = tangent.cross(up_guess).normalized()
                var perp_b = tangent.cross(perp_a).normalized()


                const GOLDEN_ANGLE: = 2.39996
                var angle = shatter_count * GOLDEN_ANGLE + randf_range(-0.2, 0.2)
                var radial_dir = perp_a * cos(angle) + perp_b * sin(angle)



                var cone_spread = randf_range(0.1, 0.25)
                var total_velocity = tangent * fwd_speed + radial_dir * fwd_speed * cone_spread






                var spawn_pos = hit_point + tangent * 3.0
                debris.setup(
                    spawn_pos, 
                    container.global_transform.basis * local_trans.basis, 
                    color, 
                    Vector3.ONE * cube_step, 
                    total_velocity, 
                    shared_obstacle_mat_opaque
                )
                var dc3 = Time.get_ticks_usec()
                debris_create_us += (dc1 - dc0)
                debris_addchild_us += (dc2 - dc1)
                debris_setup_us += (dc3 - dc2)
                shatter_count += 1


    container.queue_free()
    var st2 = Time.get_ticks_usec()
    print("[SHATTER TIMING] prep=%dus debris(x%d): create=%dus add_child=%dus setup=%dus TOTAL=%dus" % [st1 - st0, shatter_count, debris_create_us, debris_addchild_us, debris_setup_us, st2 - st0])




func _warm_up_debris_shader() -> void :

    debris_material_template = StandardMaterial3D.new()
    debris_material_template.albedo_color = Color.WHITE
    debris_material_template.emission_enabled = true
    debris_material_template.emission = Color.WHITE
    debris_material_template.emission_energy_multiplier = 4.0
    debris_material_template.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA



    debris_shard_mesh = _build_bipyramid_shard()


    var mi = MeshInstance3D.new()
    mi.mesh = debris_shard_mesh
    mi.material_override = debris_material_template
    mi.position = Vector3(0, 50, 0)
    add_child(mi)

    get_tree().process_frame.connect( func():
        get_tree().process_frame.connect( func():
            mi.queue_free()
        , CONNECT_ONE_SHOT)
    , CONNECT_ONE_SHOT)




func _build_bipyramid_shard() -> ArrayMesh:
    var st: = SurfaceTool.new()
    st.begin(Mesh.PRIMITIVE_TRIANGLES)

    var tip_f: = Vector3(0, 0, 1.1)
    var tip_b: = Vector3(0, 0, -1.1)

    var b0: = Vector3(0, 0.5, 0)
    var b1: = Vector3(-0.433, -0.25, 0)
    var b2: = Vector3(0.433, -0.25, 0)


    _add_shard_face(st, tip_f, b0, b1)
    _add_shard_face(st, tip_f, b1, b2)
    _add_shard_face(st, tip_f, b2, b0)

    _add_shard_face(st, tip_b, b1, b0)
    _add_shard_face(st, tip_b, b2, b1)
    _add_shard_face(st, tip_b, b0, b2)

    return st.commit()


func _add_shard_face(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void :
    var normal: = (b - a).cross(c - a).normalized()
    st.set_normal(normal)
    st.add_vertex(a)
    st.set_normal(normal)
    st.add_vertex(b)
    st.set_normal(normal)
    st.add_vertex(c)











func trigger_destruction_vfx(immediate: bool = false) -> void :

    if _destruction_tween and _destruction_tween.is_valid():
        _destruction_tween.kill()
    _destruction_tween = null


    _cleanup_destruction()




    _destruction_obstacles = active_obstacles.duplicate()

    if _destruction_obstacles.is_empty():
        return






    var body_snapshot: ShaderMaterial = shared_obstacle_mat_opaque.duplicate()
    var edge_snapshot: ShaderMaterial = shared_edge_mat.duplicate()
    for snap in [body_snapshot, edge_snapshot]:
        snap.set_shader_parameter("destruction_progress", 0.0)
        if immediate:



            snap.set_shader_parameter("dissolve_delay", 0.0)
            snap.set_shader_parameter("dissolve_stagger", 0.0)
    _destruction_mats = [body_snapshot, edge_snapshot]



    for obs in _destruction_obstacles:
        if not is_instance_valid(obs):
            continue
        _reassign_destruction_materials(obs, body_snapshot, edge_snapshot)
        _disable_obstacle_collision(obs)

        obs.remove_meta("pool_type_id")


    var duration: float = 0.7 if immediate else DESTRUCTION_DURATION
    _destruction_tween = get_tree().create_tween()
    if immediate:
        _destruction_tween.tween_method(_set_destruction_progress, 0.0, 1.0, duration)
    else:
        _destruction_tween.tween_method(_set_destruction_progress, 0.0, 1.0, duration)\
.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
    _destruction_tween.tween_callback(_cleanup_destruction)






func _reassign_destruction_materials(obs: Node3D, body_snap: ShaderMaterial, edge_snap: ShaderMaterial) -> void :
    for child in obs.get_children():
        if child is MultiMeshInstance3D:
            child.material_override = edge_snap if child.material_override == shared_edge_mat else body_snap

        for grandchild in child.get_children():
            if grandchild is MultiMeshInstance3D:
                grandchild.material_override = edge_snap if grandchild.material_override == shared_edge_mat else body_snap








func _disable_obstacle_collision(obs: Node3D) -> void :
    for child in obs.get_children():
        if child is Area3D:
            child.collision_layer = 0
            child.collision_mask = 0
            child.set_deferred("monitorable", false)
            child.set_deferred("monitoring", false)



func _set_destruction_progress(value: float) -> void :
    for mat in _destruction_mats:
        mat.set_shader_parameter("destruction_progress", value)



func _cleanup_destruction() -> void :
    for obs in _destruction_obstacles:
        if is_instance_valid(obs):
            active_obstacles.erase(obs)
            obs.queue_free()
    _destruction_obstacles.clear()
    _destruction_mats.clear()









func _ghost_destroy_obstacle(obs: Node3D) -> void :
    if _ghost_destroying.has(obs) or not is_instance_valid(obs):
        return



    var body_snapshot: ShaderMaterial = shared_obstacle_mat_opaque.duplicate()
    var edge_snapshot: ShaderMaterial = shared_edge_mat.duplicate()
    for snap in [body_snapshot, edge_snapshot]:
        snap.set_shader_parameter("destruction_progress", 0.0)


    _reassign_destruction_materials(obs, body_snapshot, edge_snapshot)

    obs.remove_meta("pool_type_id")


    var mats: = [body_snapshot, edge_snapshot]
    var tween: Tween = get_tree().create_tween()
    tween.tween_method( func(v: float):
        for m in mats:
            m.set_shader_parameter("destruction_progress", v)
    , 0.0, 1.0, GHOST_DESTROY_DURATION)
    tween.tween_callback(_ghost_cleanup_single.bind(obs))

    _ghost_destroying[obs] = {"mats": mats, "tween": tween}



func _ghost_cleanup_single(obs: Node3D) -> void :
    _ghost_destroying.erase(obs)
    active_obstacles.erase(obs)
    if is_instance_valid(obs):
        obs.queue_free()




func cleanup_ghost_destruction() -> void :
    for obs in _ghost_destroying:
        var entry: Dictionary = _ghost_destroying[obs]
        var tween: Tween = entry.get("tween")
        if tween and tween.is_valid():
            tween.kill()
        if is_instance_valid(obs):
            active_obstacles.erase(obs)
            obs.queue_free()
    _ghost_destroying.clear()










func get_state() -> Dictionary:
    var data: = {}
    data["schema_version"] = 1

    data["ring_origin_offset"] = ring_origin_offset
    data["current_speed"] = current_speed
    data["last_checked_ring"] = last_checked_ring
    data["rings_since_obstacle"] = rings_since_obstacle





    data["next_obstacle_interval"] = next_obstacle_interval
    data["safe_path_angle"] = safe_path_angle

    data["last_obstacle_color"] = last_obstacle_color

    var obstacles: Array = []
    for obs in active_obstacles:
        if not is_instance_valid(obs):
            continue
        var entry: = {}
        entry["transform"] = obs.transform


        var type_id: String = obs.pool_type_id
        if type_id == "":
            type_id = obs.obstacle_type_id
        entry["type_id"] = type_id



        entry["color"] = obs.pool_last_color

        var meta: = {}
        for key in obs.get_meta_list():
            if key == "pool_type_id" or key == "pool_last_color":
                continue
            meta[key] = obs.get_meta(key)
        entry["meta"] = meta
        obstacles.append(entry)
    data["active_obstacles"] = obstacles
    return data






func apply_state(state: Dictionary) -> void :
    var version: int = state.get("schema_version", 0)
    if version != 1:
        push_warning("ObstacleManager.apply_state: unsupported schema_version %d" % version)
        return



    rings_since_obstacle = 0
    last_checked_ring = state.get("last_checked_ring", 0)






    for i in range(active_obstacles.size() - 1, -1, -1):
        var obs: Node3D = active_obstacles[i]
        active_obstacles.remove_at(i)
        if is_instance_valid(obs) and not _release_to_pool(obs):
            obs.queue_free()


    _ghost_destroying.clear()
    _clear_obstacle_pool()

    ring_origin_offset = state.get("ring_origin_offset", ring_origin_offset)
    current_speed = state.get("current_speed", current_speed)
    rings_since_obstacle = state.get("rings_since_obstacle", 0)



    next_obstacle_interval = state.get("next_obstacle_interval", -1)
    safe_path_angle = state.get("safe_path_angle", safe_path_angle)
    last_obstacle_color = state.get("last_obstacle_color", last_obstacle_color)

    var obstacles: Array = state.get("active_obstacles", [])
    for entry in obstacles:
        _rebuild_obstacle_from_dict(entry)






func _rebuild_obstacle_from_dict(entry: Dictionary) -> void :
    var type_id: String = entry.get("type_id", "")
    if type_id == "":
        push_warning("ObstacleManager._rebuild_obstacle_from_dict: missing type_id")
        return
    var meta: Dictionary = entry.get("meta", {})



    var captured_color: Variant = entry.get("color", last_obstacle_color)
    var color: Color = captured_color if captured_color is Color else last_obstacle_color

    var container: Node3D = _try_acquire_pooled_obstacle(type_id, color)
    if container == null:

        var cube_mesh: = BoxMesh.new()
        cube_mesh.size = Vector3(1, 1, 1) * config.cube_size
        var instances_data: Array = []
        var captured_xform: Transform3D = entry.get("transform", Transform3D.IDENTITY)
        if type_configs.has(type_id):
            var conf: ObstacleTypeConfig = type_configs[type_id]
            var ring_index: int = int(((50.0 - captured_xform.origin.y) / config.ring_spacing) + ring_origin_offset)
            _generate_shape_data(conf, captured_xform.origin.y, color, instances_data, ring_index)
        else:
            var def: = obstacle_library.get_definition(type_id)
            if def and not def.filled_cells.is_empty():
                instances_data = def.get_cell_data(config.base_radius, config.cube_size, color, 0.0)
        if instances_data.is_empty():
            push_warning("ObstacleManager._rebuild_obstacle_from_dict: empty shape data for type_id=%s" % type_id)
            return
        container = _build_multimesh(instances_data, cube_mesh, _get_body_material())
        container.pool_type_id = type_id
        container.pool_last_color = color

    container.transform = entry.get("transform", Transform3D.IDENTITY)











    var params: Dictionary = meta.duplicate()
    params["type_id"] = type_id
    params["starting_angle_rad"] = meta.get("current_rot_val", 0.0)
    _apply_spawn_behavior(container, params)






    if meta.get("swap_enabled", false):
        var sw_targets_v: Variant = meta.get("swap_targets", PackedStringArray())
        var sw_targets: PackedStringArray = sw_targets_v if sw_targets_v is PackedStringArray else PackedStringArray(sw_targets_v)
        var sw_host_id: String = meta.get("swap_host_type_id", type_id)
        var sw_period: float = meta.get("swap_period_sec", 0.0)
        var sw_phase: float = meta.get("swap_phase_sec", 0.0)
        if not sw_targets.is_empty() and sw_period > 0.001:
            setup_mesh_swap(container, sw_host_id, sw_targets, sw_period, sw_phase, color)
            var sw_time: float = meta.get("swap_time", 0.0)
            container.swap_time = sw_time


            var sw_count: int = container.swap_variant_count
            var sw_idx: int = _compute_swap_variant_index(sw_time, sw_phase, sw_period, sw_count)
            _set_active_swap_variant(container, sw_idx)





    for key in meta:
        if container.has_meta(key):
            continue
        if String(key).begins_with("swap_"):
            continue
        container.set_meta(key, meta[key])
    active_obstacles.append(container)
    add_child(container)

extends Node3D
class_name TunnelManager









@export var config: Resource
@export var chunk_length: int = 100
@export var chunk_count: int = 3
@export var shadow_cutoff_dist: float = 40.0
@export var max_shadow_casters: int = 6

var wall_light_energy: float = 4.5
var wall_light_range: float = 41.58
var beat_light_energy_boost: float = 1.0
var beat_light_flash_color: Color = Color.WHITE
var beat_light_flash_amount: float = 0.0

var chunks: Array[Node3D] = []
var cached_lights: Array[OmniLight3D] = []
var _active_lights: Array[Dictionary] = []
var total_chunk_height: float
var ring_origin_offset: float = 0.0
var last_cam_y: float = 0.0

var color_manager: ColorManager


var integrator: EffectTimeIntegrator = EffectTimeIntegrator.new()

var current_theme: LevelTheme




var current_substage: SubStageDef = null


var _blend_controller: ThemeBlendController = ThemeBlendController.new()
var _was_blending: bool = false



var _effect_overrides: Dictionary = {}



var _cb_pal_img: Image
var _cb_pal_tex: ImageTexture
var _cb_pattern_map_img: Image
var _cb_pattern_map_tex: ImageTexture
var _cb_blend_flag_img: Image
var _cb_blend_flag_tex: ImageTexture


var shared_wall_mat: ShaderMaterial
var shared_strip_mat: ShaderMaterial
var player_controller: Node3D
var effect_manager: EffectManager = null
var obstacle_manager: Node = null

func _ready():
    _setup_materials()

    if not config:
        config = load("res://resources/tunnel_config.tres")
        if not config:
            push_error("TunnelManager: No TunnelConfig found!")
            return

    total_chunk_height = float(chunk_length) * config.ring_spacing

    _setup_chunks()
    _cache_lights()
    if RenderingQualityManager:
        RenderingQualityManager.apply_shadow_settings()


    effect_manager = get_parent().get_node_or_null("EffectManager")
    obstacle_manager = get_parent().get_node_or_null("ObstacleManager")


    if effect_manager:
        effect_manager.set_param(&"use_instance_color", false)
        if config:
            effect_manager.set_param(&"ring_spacing", config.ring_spacing)


    player_controller = get_parent().get_parent().get_node_or_null("PlayerController")
    if not player_controller:
        player_controller = get_tree().current_scene.find_child("PlayerController", true, false)


    integrator.reset()


    EventBus.origin_shifted.connect(_on_origin_shifted)
    EventBus.player_moved.connect( func(data): update_tunnel(data.x, data.y, data.z))
    EventBus.level_started.connect(_on_level_started)

func _process(delta):
    if not current_theme: return
    var theme = current_theme






    if player_controller and effect_manager:
        last_cam_y = player_controller.get_global_transform_interpolated().origin.y
        effect_manager.set_param(&"camera_y", last_cam_y)


    _blend_controller.advance(delta)
    var theme_data: = _blend_controller.get_blended_theme_data()




    if not _blend_controller.is_blending() and not _effect_overrides.is_empty():
        for k in _effect_overrides:
            theme_data[k] = _effect_overrides[k]




    if effect_manager:
        effect_manager.current_world_tilt_amount = theme_data.get("world_tilt_amount", 0.0)
        effect_manager.current_world_tilt_speed = theme_data.get("world_tilt_speed", 0.1)
        effect_manager.current_fov_pulse_amount = theme_data.get("fov_pulse_amount", 0.0)
        effect_manager.current_fov_pulse_speed = theme_data.get("fov_pulse_speed", 0.0)
        if effect_manager.chroma_mat:
            effect_manager.chroma_mat.set_shader_parameter("aberration_amount", theme_data.get("chroma_amount", 0.0))
    if color_manager:
        color_manager.hue_shift_speed = theme_data.get("hue_shift_speed", 0.0)
        color_manager.scroll_speed = theme_data.get("scroll_speed", 0.0)
        color_manager.scroll_relative_to_speed = theme_data.get("scroll_relative_to_speed", false)
        color_manager.scroll_additive = theme_data.get("scroll_additive", false)
        color_manager.current_texture_reverse = theme_data.get("texture_reverse_direction", false)
        color_manager.color_spin = theme_data.get("color_spin", 0.0)

        color_manager.braking_enabled = theme_data.get("braking_enabled", false)
        color_manager.braking_delay_min = theme_data.get("braking_delay_min", 3.0)
        color_manager.braking_delay_max = theme_data.get("braking_delay_max", 8.0)
        color_manager.braking_duration = theme_data.get("braking_duration", 1.5)
        color_manager.braking_accel_duration = theme_data.get("braking_accel_duration", 1.5)
        color_manager.braking_hold_time = theme_data.get("braking_hold_time", 2.0)
        color_manager.braking_move_lights = theme_data.get("braking_move_lights", false)
    if player_controller:
        player_controller.move_split_base = theme_data.get("move_split_base", 0.0)
        player_controller.move_split_osc_amount = theme_data.get("move_split_osc_amount", 0.0)
        player_controller.move_split_osc_frequency = theme_data.get("move_split_osc_frequency", 0.0)
        player_controller.move_split_smoothing = theme_data.get("move_split_smoothing", 0.0)



    var effect_speeds: Dictionary = {}
    effect_speeds["twist"] = theme_data.get("twist_speed", 0.0)
    effect_speeds["wobble"] = theme_data.get("wobble_frequency", 0.0)
    effect_speeds["helix"] = theme_data.get("helix_speed", 0.0)
    effect_speeds["pinch"] = theme_data.get("pinch_speed", 0.0)
    effect_speeds["mobius"] = theme_data.get("mobius_speed", 0.0)
    effect_speeds["breathing"] = theme_data.get("breathing_frequency", 0.0)
    effect_speeds["ripple"] = theme_data.get("ripple_frequency", 0.0)
    effect_speeds["tide"] = theme_data.get("tide_frequency", 0.0)
    effect_speeds["shear"] = theme_data.get("shear_frequency", 0.0)
    var section_spin_speed: float = theme_data.get("section_spin", 0.0)




    if _blend_controller.is_blending():
        var src_ss: float = _blend_controller._source_data.get("section_spin", 0.0)
        var tgt_ss: float = _blend_controller._target_data.get("section_spin", 0.0)
        if absf(tgt_ss) < 0.001:
            section_spin_speed = 0.0
        elif absf(src_ss) < 0.001:
            section_spin_speed = tgt_ss
    effect_speeds["section_spin"] = section_spin_speed
    var surface_anims_spd: float = theme_data.get("surface_anims_speed", 0.0)
    if abs(surface_anims_spd) > 0.001:
        effect_speeds["surface_anims"] = surface_anims_spd
    if theme_data.get("emission_wave_amount", 0.0) > 0.001:
        effect_speeds["emission_wave"] = theme_data.get("emission_wave_speed", 0.0)
    if theme_data.get("cube_scale_wave_amount", 0.0) > 0.001:
        effect_speeds["cube_scale_wave"] = theme_data.get("cube_scale_wave_speed", 0.0)









    var spin_sync: bool = theme_data.get("sync_rotation", false)
    var spin_step: bool = theme_data.get("step_rotation", false)
    if _blend_controller.is_blending():
        var src_ss_cfg: float = _blend_controller._source_data.get("section_spin", 0.0)
        var tgt_ss_cfg: float = _blend_controller._target_data.get("section_spin", 0.0)
        var deactivating: bool = absf(src_ss_cfg) > 0.001 and absf(tgt_ss_cfg) < 0.001
        if deactivating:
            spin_sync = _blend_controller._source_data.get("sync_rotation", spin_sync)
            spin_step = _blend_controller._source_data.get("step_rotation", spin_step)
        else:
            spin_sync = _blend_controller._target_data.get("sync_rotation", spin_sync)
            spin_step = _blend_controller._target_data.get("step_rotation", spin_step)
    elif integrator.section_spin_fade > 0.0 and absf(section_spin_speed) < 0.001:




        spin_sync = integrator._section_spin_sync_rotation
        spin_step = integrator._section_spin_step_rotation
    integrator.update_section_spin_config(spin_sync, spin_step)








    theme_data["sync_rotation"] = spin_sync
    theme_data["step_rotation"] = spin_step
    theme_data["section_spin"] = section_spin_speed

    integrator.advance(delta, effect_speeds)




    var rr_speed: float = theme_data.get("ring_rotation_speed", 0.0)
    var rr_decay: float = theme_data.get("ring_rotation_decay", 0.02)




    if _blend_controller.is_blending():
        var src_rr_speed: float = _blend_controller._source_data.get("ring_rotation_speed", 0.0)
        var tgt_rr_speed: float = _blend_controller._target_data.get("ring_rotation_speed", 0.0)
        if absf(tgt_rr_speed) < 0.001:
            rr_speed = 0.0





            rr_decay = _blend_controller._source_data.get("ring_rotation_decay", rr_decay)
        elif absf(src_rr_speed) < 0.001:
            rr_speed = tgt_rr_speed




            rr_decay = _blend_controller._target_data.get("ring_rotation_decay", 0.02)
    elif absf(rr_speed) < 0.001 and integrator.ring_rotation_fade > 0.0:



        rr_decay = integrator.ring_rotation_active_decay
    var camera_ring: float = (50.0 - last_cam_y) / config.ring_spacing + ring_origin_offset
    integrator.advance_ring_rotation(delta, rr_speed, rr_decay, camera_ring)





    var timer_data: = integrator.build_timer_data()


    timer_data["ring_rotation_decay"] = rr_decay

    if color_manager:
        timer_data["color_time"] = color_manager.current_time
        timer_data["scroll_offset"] = color_manager.scroll_offset
        timer_data["color_spin_angle"] = color_manager.color_spin_angle
        timer_data["hue_shift"] = color_manager.current_hue_shift


    if player_controller:
        timer_data["player_offset_x"] = player_controller.position.x
        timer_data["player_offset_z"] = player_controller.position.z


    if _blend_controller.is_blending():

        if _cb_pattern_map_img and _cb_pattern_map_tex:
            var px: = _cb_pattern_map_img.get_pixel(0, 0)
            px.b = _blend_controller._blend_t
            _cb_pattern_map_img.set_pixel(0, 0, px)
            _cb_pattern_map_tex.update(_cb_pattern_map_img)

        var env: = get_viewport().find_child("WorldEnvironment", true, false) as WorldEnvironment
        if env and env.environment:
            env.environment.background_color = _blend_controller.get_blended_background_color()

        if color_manager:
            var cm_props: = _blend_controller.get_blended_color_manager_props()
            color_manager.hue_shift_speed = cm_props.get("hue_shift_speed", 0.0)
            color_manager.scroll_speed = cm_props.get("scroll_speed", 0.0)
            color_manager.color_spin = cm_props.get("color_spin", 0.0)

        if effect_manager:
            effect_manager.set_param(&"metallic", theme_data.get("metallic_intensity", 0.0))
            effect_manager.set_param(&"roughness", theme_data.get("wall_roughness", 1.0))
            effect_manager.set_param(&"surface_roughness", theme_data.get("surface_roughness", 0.0))
            effect_manager.set_param(&"surface_anims_amount", theme_data.get("surface_anims_amount", 0.0))
            effect_manager.set_param(&"spiral_frequency", theme_data.get("spiral_frequency", 6.0))
            effect_manager.set_param(&"tunnel_twist", theme_data.get("tunnel_twist", 0.0))
            effect_manager.set_param(&"section_length", theme_data.get("section_length", 25.0))



            effect_manager.set_param(&"wobble_amount", theme_data.get("wobble_amount", 0.0))
            effect_manager.set_param(&"breathing_amount", theme_data.get("breathing_amount", 0.0))
            effect_manager.set_param(&"glitch_intensity", theme_data.get("glitch_intensity", 0.0))
            effect_manager.set_param(&"ripple_amount", theme_data.get("ripple_amount", 0.0))
            effect_manager.set_param(&"ring_stagger", theme_data.get("ring_stagger", 0.0))
            effect_manager.set_param(&"spaghettify_amount", theme_data.get("spaghettify_amount", 0.0))
            effect_manager.set_param(&"reverse_perspective", theme_data.get("reverse_perspective", 0.0))
            effect_manager.set_param(&"player_reactive_curve", theme_data.get("player_reactive_curve", 0.0))
            effect_manager.set_param(&"player_reactive_start", theme_data.get("player_reactive_start", 0.0))
        _was_blending = true
    elif _was_blending:

        if shared_wall_mat:
            shared_wall_mat.set_shader_parameter("color_blend_enabled", false)
        _apply_theme_to_shader(current_theme)



        if effect_manager and not _effect_overrides.is_empty():
            for k in _effect_overrides:
                effect_manager.set_param(StringName(k), _effect_overrides[k])
        if color_manager:
            color_manager.set_theme(current_theme, current_substage)
        _was_blending = false


    if beat_light_energy_boost != 1.0:
        theme_data["beat_light_energy_boost"] = beat_light_energy_boost
    if beat_light_flash_amount > 0.0:
        theme_data["beat_light_flash_color"] = beat_light_flash_color
        theme_data["beat_light_flash_amount"] = beat_light_flash_amount


    EffectLightSync.update_lights(
        cached_lights, _active_lights, timer_data, theme_data, 
        last_cam_y, config.ring_spacing, ring_origin_offset, 
        player_controller, delta
    )






    _update_chunk_shadow_casting()




    if obstacle_manager:
        obstacle_manager.twist_time = timer_data.get("twist_time", 0.0)
        obstacle_manager.section_rotation_time = timer_data.get("section_rotation_time", 0.0)
        obstacle_manager.wobble_time = timer_data.get("wobble_time", 0.0)
        obstacle_manager.breathing_time = timer_data.get("breathing_time", 0.0)
        obstacle_manager.ripple_time = timer_data.get("ripple_time", 0.0)
        obstacle_manager.tide_time = timer_data.get("tide_time", 0.0)
        obstacle_manager.shear_time = timer_data.get("shear_time", 0.0)
        obstacle_manager.helix_time = timer_data.get("helix_time", 0.0)
        obstacle_manager.pinch_time = timer_data.get("pinch_time", 0.0)
        obstacle_manager.mobius_time = timer_data.get("mobius_time", 0.0)
        obstacle_manager._time_externally_synced = true
        obstacle_manager.ring_origin_offset = ring_origin_offset
        obstacle_manager._cached_theme_overrides = theme_data


    if effect_manager:
        EffectShaderPusher.push_all(
            shared_wall_mat, shared_strip_mat, effect_manager.strip_materials, 
            last_cam_y, ring_origin_offset, config.ring_spacing, 
            timer_data, theme_data
        )






        for _skey in [&"twist_speed", &"wobble_frequency", &"breathing_frequency", 
                      &"ripple_frequency", &"tide_frequency", &"shear_frequency", 
                      &"section_spin", &"sync_rotation", &"step_rotation"]:
            effect_manager._dirty_params.erase(_skey)


        effect_manager._flush_dirty()

func _setup_materials():

    var shader = load("res://materials/tunnel_wall_optimized.gdshader")
    shared_wall_mat = ShaderMaterial.new()
    shared_wall_mat.shader = shader
    shared_wall_mat.set_shader_parameter("use_instance_color", false)


    if not config:
        config = load("res://resources/tunnel_config.tres")
    if config:
        shared_wall_mat.set_shader_parameter("ring_spacing", config.ring_spacing)


    var strip_shader = load("res://materials/neon_strip.gdshader")
    if strip_shader:
        shared_strip_mat = ShaderMaterial.new()
        shared_strip_mat.shader = strip_shader
        if config:
            shared_strip_mat.set_shader_parameter("ring_spacing", config.ring_spacing)

func _setup_chunks():
    print("TunnelManager: Building %d MegaChunks..." % chunk_count)
    for i in range(chunk_count):
        var chunk = build_mega_chunk(i)
        chunks.append(chunk)
        add_child(chunk)


    var start_offset = 50.0
    for i in range(chunk_count):
        chunks[i].position.y = start_offset - (float(i) * total_chunk_height)


func _update_chunk_shadow_casting() -> void :












    var shadow_zone_half: float = shadow_cutoff_dist + wall_light_range
    var shadow_top: float = last_cam_y + shadow_zone_half
    var shadow_bottom: float = last_cam_y - shadow_zone_half
    for chunk in chunks:
        var chunk_top: float = chunk.position.y
        var chunk_bottom: float = chunk.position.y - total_chunk_height

        var overlaps: bool = chunk_bottom <= shadow_top and chunk_top >= shadow_bottom
        var setting: int = (
            GeometryInstance3D.SHADOW_CASTING_SETTING_ON if overlaps
            else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
        )




        for node in chunk.get_children():
            if node is MultiMeshInstance3D and node.is_in_group("TunnelMultiMesh"):
                if node.cast_shadow != setting:
                    node.cast_shadow = setting


func _cache_lights():
    cached_lights.clear()
    for chunk in chunks:
        for child in chunk.get_children():
            if child is OmniLight3D:
                cached_lights.append(child)

    _active_lights.resize(cached_lights.size())
    _active_lights.clear()

func update_tunnel(_logical_dist: float, camera_y: float, obs_move: float = 0.0):
    last_cam_y = camera_y


    if obs_move != 0.0:
        ring_origin_offset += (obs_move / config.ring_spacing)



    for chunk in chunks:
        if (chunk.position.y - camera_y) > 120.0:
            _recycle_chunk(chunk)


    if effect_manager:
        effect_manager.set_param(&"camera_y", camera_y)
        effect_manager.set_param(&"global_ring_offset", ring_origin_offset)

func _recycle_chunk(chunk: Node3D):

    var lowest_y = 99999.0
    var lowest_chunk = null
    for c in chunks:
        if c.position.y < lowest_y:
            lowest_y = c.position.y
            lowest_chunk = c


    var new_y = lowest_y - total_chunk_height
    chunk.position.y = new_y


    var parent_start_ring = 0
    if lowest_chunk and lowest_chunk.has_meta("start_ring"):
        parent_start_ring = lowest_chunk.get_meta("start_ring")
    else:
        parent_start_ring = int(round(lowest_y / - config.ring_spacing))

    var new_start_ring = parent_start_ring + chunk_length
    chunk.set_meta("start_ring", new_start_ring)


    _update_chunk_lights_meta(chunk, new_start_ring)


    for child in chunk.get_children():
        if child is OmniLight3D:
            child.visible = false
            child.shadow_enabled = false

    EventBus.chunk_recycled.emit(chunk)

func _update_chunk_lights_meta(chunk: Node, start_ring: int):
    for child in chunk.get_children():
        if child is OmniLight3D:
            var base_pos = child.get_meta("base_pos") as Vector3
            var local_r = int(round(abs(base_pos.y) / config.ring_spacing))
            child.set_meta("ring_index", start_ring + local_r)


func _on_origin_shifted(amount: float):
    for chunk in chunks:
        chunk.position.y += amount

    ring_origin_offset += (amount / config.ring_spacing)







func get_chunks_state() -> Dictionary:
    var positions: PackedFloat32Array = PackedFloat32Array()
    var start_rings: PackedInt32Array = PackedInt32Array()
    for chunk in chunks:
        positions.append(chunk.position.y)



        var sr: int = 0
        if chunk.has_meta("start_ring"):
            sr = chunk.get_meta("start_ring")
        start_rings.append(sr)
    return {"positions_y": positions, "start_rings": start_rings}







func apply_chunks_state(state: Dictionary) -> void :
    if state.is_empty():
        return
    var positions: PackedFloat32Array = state.get("positions_y", PackedFloat32Array())
    var start_rings: PackedInt32Array = state.get("start_rings", PackedInt32Array())
    if positions.size() != chunks.size() or start_rings.size() != chunks.size():
        push_warning("TunnelManager.apply_chunks_state: size mismatch (snap=%d/%d live=%d); skipping" % [positions.size(), start_rings.size(), chunks.size()])
        return
    for i in range(chunks.size()):
        chunks[i].position.y = positions[i]
        chunks[i].set_meta("start_ring", start_rings[i])
        _update_chunk_lights_meta(chunks[i], start_rings[i])

func _on_level_started(_idx, theme):
    current_theme = theme
    _blend_controller.set_theme_instant(theme)
    integrator.reset()



    last_cam_y = 0.0
    ring_origin_offset = 0.0
    _apply_theme_to_shader(theme)



















func reset_for_stage(_stage_def: StageDef) -> void :

    ring_origin_offset = 0.0
    integrator.reset()





    var start_offset: float = 50.0
    for i in range(chunks.size()):
        var new_y: float = last_cam_y + start_offset - (float(i) * total_chunk_height)
        chunks[i].position.y = new_y
        var new_start_ring: int = i * chunk_length
        chunks[i].set_meta("start_ring", new_start_ring)
        _update_chunk_lights_meta(chunks[i], new_start_ring)





    if effect_manager:
        effect_manager.set_param(&"global_ring_offset", ring_origin_offset)



func blend_to_theme(theme: LevelTheme, duration: float = 0.8) -> void :

    _effect_overrides.clear()


    var src_palette: Array[Color] = []
    var src_pattern: int = 0
    if current_theme:
        src_palette = current_theme.palette.duplicate()
        src_pattern = current_theme.pattern_mode

    current_theme = theme



    if duration <= 0.0:
        _blend_controller.set_theme_instant(theme)
        _was_blending = false
        if shared_wall_mat:
            shared_wall_mat.set_shader_parameter("color_blend_enabled", false)
        _apply_theme_to_shader(theme)
        if color_manager:
            color_manager.set_theme(theme, current_substage)



            if current_substage != null and not current_substage.obstacle_palette.is_empty():
                color_manager.obstacle_override = current_substage.obstacle_palette.duplicate()
            else:
                color_manager.obstacle_override = []
            color_manager.generate_obstacle_palette()
        return

    _blend_controller.blend_to(theme, duration)



    _setup_color_blend(src_palette, src_pattern, theme.palette, theme.pattern_mode)




    if color_manager:



        if current_substage != null and not current_substage.obstacle_palette.is_empty():
            color_manager.obstacle_override = current_substage.obstacle_palette.duplicate()
        else:
            color_manager.obstacle_override = []
        color_manager.generate_obstacle_palette()






func set_effect_override(key: StringName, value) -> void :
    _effect_overrides[key] = value
    _blend_controller.set_target_override(key, value)






func get_theme_data() -> Dictionary:
    return _blend_controller.get_blended_theme_data()




func clear_effect_overrides() -> void :
    _effect_overrides.clear()






func get_visual_state() -> Dictionary:
    return {
        "schema_version": 1, 
        "blend_state": _blend_controller.get_state(), 
        "effect_overrides": _effect_overrides.duplicate(true), 
        "_was_blending": _was_blending, 
    }






func apply_visual_state(state: Dictionary) -> void :
    if state.get("schema_version", 0) != 1:
        push_warning("TunnelManager.apply_visual_state: unsupported schema_version")
        return
    var blend_state: Dictionary = state.get("blend_state", {})
    if not blend_state.is_empty():
        _blend_controller.apply_state(blend_state)


        if _blend_controller._current_theme:
            current_theme = _blend_controller._current_theme
    _effect_overrides = (state.get("effect_overrides", {}) as Dictionary).duplicate(true)
    _was_blending = state.get("_was_blending", false)
























func set_active_substage(substage: SubStageDef) -> void :
    current_substage = substage

func apply_substage_visual(target_theme: LevelTheme, effects: Array, duration: float) -> Dictionary:
    var theme_changed: bool = target_theme != null and target_theme != current_theme
    if theme_changed:
        blend_to_theme(target_theme, duration)
    else:







        _effect_overrides.clear()
        if duration <= 0.0:
            _blend_controller.set_theme_instant(current_theme)
        elif current_theme:
            _blend_controller.blend_to(current_theme, duration)
    return _apply_effect_array(effects)





func _apply_effect_array(effects: Array) -> Dictionary:
    var flat: Dictionary = {}
    for effect_entry in effects:
        var effect_name: String = effect_entry.get("name", "")
        var registry_entry: Dictionary = EffectRegistry.get_effect(effect_name)
        if registry_entry.is_empty():
            continue
        var params_def: Dictionary = registry_entry.get("params", {})
        for param_key in effect_entry:
            if param_key == "name":
                continue
            var param_def: Dictionary = params_def.get(param_key, {})
            if param_def.is_empty():
                continue
            var theme_key: String = param_def.get("theme_key", "")
            if theme_key.is_empty():
                continue
            set_effect_override(StringName(theme_key), effect_entry[param_key])
            flat[theme_key] = effect_entry[param_key]
    return flat




func _setup_color_blend(from_pal: Array[Color], from_pm: int, 
        to_pal: Array[Color], to_pm: int) -> void :
    if not shared_wall_mat:
        return
    const PAL_SLOTS: = 8



    if not _cb_pal_tex:
        _cb_pal_img = Image.create(1, PAL_SLOTS * 2, false, Image.FORMAT_RGBA8)
        _cb_pal_tex = ImageTexture.create_from_image(_cb_pal_img)
        shared_wall_mat.set_shader_parameter("palette_map_tex", _cb_pal_tex)


    if not _cb_pattern_map_tex:
        _cb_pattern_map_img = Image.create(1, 2, false, Image.FORMAT_RGBAF)
        _cb_pattern_map_tex = ImageTexture.create_from_image(_cb_pattern_map_img)
        shared_wall_mat.set_shader_parameter("pattern_map_tex", _cb_pattern_map_tex)

    if not _cb_blend_flag_tex:
        _cb_blend_flag_img = Image.create(1, 1, false, Image.FORMAT_RGBAF)
        _cb_blend_flag_img.set_pixel(0, 0, Color(1.0, 0, 0, 0))
        _cb_blend_flag_tex = ImageTexture.create_from_image(_cb_blend_flag_img)
        shared_wall_mat.set_shader_parameter("color_blend_tex", _cb_blend_flag_tex)


    _cb_pal_img.fill(Color.BLACK)
    for i in range(mini(to_pal.size(), PAL_SLOTS)):
        _cb_pal_img.set_pixel(0, i, to_pal[i])
    for i in range(mini(from_pal.size(), PAL_SLOTS)):
        _cb_pal_img.set_pixel(0, PAL_SLOTS + i, from_pal[i])
    _cb_pal_tex.update(_cb_pal_img)


    _cb_pattern_map_img.set_pixel(0, 0, Color(float(to_pm), float(to_pal.size()), 0.0, 0.0))
    _cb_pattern_map_img.set_pixel(0, 1, Color(float(from_pm), float(from_pal.size()), 0.0, 0.0))
    _cb_pattern_map_tex.update(_cb_pattern_map_img)


    shared_wall_mat.set_shader_parameter("color_blend_enabled", true)
    shared_wall_mat.set_shader_parameter("blend_ring_start", 0.0)
    shared_wall_mat.set_shader_parameter("blend_ring_count", 1000000.0)


func _apply_theme_to_shader(theme: LevelTheme):
    if not effect_manager: return


    if theme.palette.size() > 0:
        var p_size = theme.palette.size()
        var img = Image.create(p_size, 1, false, Image.FORMAT_RGBA8)
        for i in range(p_size):
            img.set_pixel(i, 0, theme.palette[i])
        var tex = ImageTexture.create_from_image(img)
        effect_manager.set_param(&"palette_tex", tex)
        effect_manager.set_param(&"palette_size", p_size)

    effect_manager.set_param(&"pattern_mode", theme.pattern_mode)
    effect_manager.set_param(&"metallic", theme.metallic_intensity)
    effect_manager.set_param(&"roughness", theme.wall_roughness)
    effect_manager.set_param(&"spiral_frequency", theme.spiral_frequency)




    var base: = EffectRegistry.get_theme_data_defaults()
    effect_manager.set_param(&"surface_roughness", base.get("surface_roughness", 0.0))
    effect_manager.set_param(&"surface_anims_amount", base.get("surface_anims_amount", 0.0))
    effect_manager.set_param(&"tunnel_twist", base.get("tunnel_twist", 0.0))
    effect_manager.set_param(&"twist_speed", base.get("twist_speed", 0.3))
    effect_manager.set_param(&"section_spin", base.get("section_spin", 0.0))
    effect_manager.set_param(&"section_length", float(base.get("section_length", 25)))
    effect_manager.set_param(&"step_rotation", base.get("step_rotation", false))
    effect_manager.set_param(&"sync_rotation", base.get("sync_rotation", false))
    effect_manager.set_param(&"wobble_amount", base.get("wobble_amount", 0.0))
    effect_manager.set_param(&"wobble_frequency", base.get("wobble_frequency", 0.0))
    effect_manager.set_param(&"breathing_amount", base.get("breathing_amount", 0.0))
    effect_manager.set_param(&"breathing_frequency", base.get("breathing_frequency", 0.0))
    effect_manager.set_param(&"glitch_intensity", base.get("glitch_intensity", 0.0))
    effect_manager.set_param(&"ripple_amount", base.get("ripple_amount", 0.0))
    effect_manager.set_param(&"ring_stagger", base.get("ring_stagger", 0.0))
    effect_manager.set_param(&"spaghettify_amount", base.get("spaghettify_amount", 0.0))
    effect_manager.set_param(&"reverse_perspective", base.get("reverse_perspective", 0.0))
    effect_manager.set_param(&"player_reactive_curve", base.get("player_reactive_curve", 0.0))
    effect_manager.set_param(&"player_reactive_start", base.get("player_reactive_start", 0.0))


func build_mega_chunk(chunk_index: int) -> Node3D:
    var chunk = Node3D.new()
    chunk.name = "MegaChunk_%d" % chunk_index

    var cube_mesh = BoxMesh.new()
    cube_mesh.size = Vector3(1, 1, 1) * config.cube_size

    var all_instances = []
    var chunk_start_ring = chunk_index * chunk_length
    chunk.set_meta("start_ring", chunk_start_ring)
    var placed_positions: Dictionary = {}


    var radius = config.base_radius * config.cube_size
    var circumference = 2.0 * PI * radius
    var cubes_per_ring: int = int(ceil((circumference / config.cube_size) * 1.1))

    var neon_budget: int = 999999
    var lights_in_chunk: int = 0
    if RenderingQualityManager:
        neon_budget = NeonLightBudget.get_max_neon_lights(RenderingQualityManager.get_preset() as int)

    var light_x: = int(round(config.base_radius))
    for r in range(chunk_length):
        var local_y = - float(r) * config.ring_spacing
        var absolute_ring_index = chunk_start_ring + r
        placed_positions.clear()




        var ring_has_light: bool = (
            absolute_ring_index % 30 == 0 and lights_in_chunk + 2 <= neon_budget
        )


        for step in range(cubes_per_ring):
            var angle = (float(step) / float(cubes_per_ring)) * TAU
            var cube_angle_deg = rad_to_deg(angle)
            var raw_x = config.base_radius * cos(angle)
            var raw_z = config.base_radius * sin(angle)
            var x = round(raw_x)
            var z = round(raw_z)


            if ring_has_light and int(z) == 0 and absi(int(x)) == light_x:
                continue
            var key: = Vector2i(int(x), int(z))
            if placed_positions.has(key):
                continue
            placed_positions[key] = true

            all_instances.append({
                "pos": Vector3(float(x) * config.cube_size, local_y, float(z) * config.cube_size), 
                "custom": Color(cube_angle_deg, float(absolute_ring_index), float(x), float(z))
            })

        if ring_has_light:
            _add_light_to_chunk(chunk, local_y, absolute_ring_index)
            lights_in_chunk += 2

    var mm = MultiMeshInstance3D.new()
    var m = MultiMesh.new()
    m.transform_format = MultiMesh.TRANSFORM_3D
    m.use_colors = true
    m.use_custom_data = true
    m.mesh = cube_mesh
    m.instance_count = all_instances.size()

    mm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON

    for i in range(all_instances.size()):
        var data = all_instances[i]
        m.set_instance_transform(i, Transform3D(Basis(), data.pos))
        m.set_instance_custom_data(i, data.custom)

    mm.multimesh = m
    mm.material_override = shared_wall_mat

    mm.extra_cull_margin = 200.0
    mm.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
    mm.add_to_group("TunnelMultiMesh")

    mm.add_to_group("TunnelMultiMesh")
    chunk.add_child(mm)

    return chunk

func _add_light_to_chunk(chunk: Node, y_pos: float, ring_idx: int):
    for angle_deg in [0, 180]:
        var angle = deg_to_rad(angle_deg)




        var radius = config.base_radius * config.cube_size
        var lx = radius * cos(angle)
        var lz = radius * sin(angle)

        var light = OmniLight3D.new()
        light.position = Vector3(lx, y_pos, lz)
        light.omni_range = wall_light_range

        light.light_energy = wall_light_energy
        light.light_color = Color(1.0, 0.95, 0.9)


        light.shadow_enabled = true
        light.shadow_bias = 0.1
        light.distance_fade_enabled = true
        light.distance_fade_begin = 140.0
        light.distance_fade_shadow = 20.0
        light.distance_fade_length = 30.0

        light.light_cull_mask &= ~ (1 << 1)

        light.add_to_group("ShadowLights")

        light.set_meta("base_pos", light.position)
        light.set_meta("ring_index", ring_idx)
        light.add_to_group("ShadowLights")




        chunk.add_child(light)


        var mesh = MeshInstance3D.new()
        mesh.mesh = BoxMesh.new()
        mesh.mesh.size = Vector3(1, 1, 1) * config.cube_size
        var mat = StandardMaterial3D.new()
        mat.emission_enabled = true
        mat.emission = light.light_color
        mat.emission_energy = 5.0
        mesh.material_override = mat
        mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
        mesh.position = Vector3.ZERO
        light.add_child(mesh)

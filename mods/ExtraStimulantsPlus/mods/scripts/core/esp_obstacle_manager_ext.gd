extends "res://scripts/domains/obstacles/obstacle_manager.gd"

# ExtraStimulantsPlus ObstacleManager Extension
# Uses Turbo Optimization rendering loop while maintaining compatibility with Phase 133.7.

const ObstacleInstance = preload("res://scripts/domains/obstacles/obstacle_instance.gd")

func _update_obstacle_transforms(_delta: float, time_data: Dictionary = {}) -> void:
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
    var eff_spin: float = td.get("section_spin", 0.0) if has_td else 0.0
    var is_step: bool = bool(td.get("step_rotation", false)) if has_td else false
    var eff_wobble: float = td.get("wobble_amount", 0.0) if has_td else 0.0
    var eff_twist: float = td.get("tunnel_twist", 0.0) if has_td else 0.0
    var eff_ripple: float = td.get("ripple_amount", 0.0) if has_td else 0.0
    var eff_shear: float = td.get("shear_amount", 0.0) if has_td else 0.0
    var eff_breathing: float = td.get("breathing_amount", 0.0) if has_td else 0.0
    var eff_helix: float = td.get("helix_amount", 0.0) if has_td else 0.0
    var eff_mobius: float = td.get("mobius_amount", 0.0) if has_td else 0.0
    var eff_pinch: float = td.get("pinch_amount", 0.0) if has_td else 0.0
    var eff_curve: float = td.get("tunnel_curve", 0.0) if has_td else 0.0
    var eff_exp: float = td.get("tunnel_expansion", 0.0) if has_td else 0.0
    var eff_tide: float = td.get("tide_amount", 0.0) if has_td else 0.0
    var eff_react: float = td.get("player_reactive_curve", 0.0) if has_td else 0.0
    var eff_rp: float = td.get("reverse_perspective", 0.0) if has_td else 0.0

    var t_section_offset: int = int(td.get("section_offset", 0)) if has_td else 0
    var t_section_length: float = float(td.get("section_length", 25.0)) if has_td else 25.0
    var t_sync_rotation: bool = bool(td.get("sync_rotation", false)) if has_td else false
    var t_spin_obstacles: bool = bool(td.get("spin_obstacles_with_walls", true)) if has_td else false
    var t_helix_freq: float = td.get("helix_frequency", 0.0) if has_td else 0.0
    var t_mobius_offset_rad: float = deg_to_rad(td.get("mobius_offset", 0.0)) if has_td else 0.0
    var t_pinch_freq: float = td.get("pinch_frequency", 0.0) if has_td else 0.0
    var t_pinch_w: float = td.get("pinch_width", 15.0) if has_td else 1.0
    var t_shear_x: float = td.get("shear_x", 1.0) if has_td else 1.0
    var t_shear_z: float = td.get("shear_z", 0.0) if has_td else 0.0
    var t_pr_start: float = td.get("player_reactive_start", 0.0) if has_td else 0.0
    var t_rp_obstacles: bool = bool(td.get("reverse_perspective_obstacles", true)) if has_td else false
    var t_pr_obstacles: bool = bool(td.get("player_reactive_obstacles", true)) if has_td else false

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
    var _player_off2:= Vector2(player_offset_x, player_offset_z)

    # Turbo Optimization: Pre-calculate music pulse for the entire loop
    var precomputed_pulse: float = 0.0
    var esp_settings = get_node_or_null("/root/ExtraStimulantsPlusSettings")
    if esp_settings and esp_settings.is_deformation_reactivity_enabled():
        var visualizer = get_node_or_null("/root/AudioVisualizer")
        if visualizer:
            precomputed_pulse = visualizer.get_bass_pulse() * esp_settings.get_reactivity_intensity()

    for obs in active_obstacles:
        var world_y: float = obs.position.y
        
        # Performance: Use ObstacleInstance properties if available, fallback to meta
        var is_esp_obs = obs is ObstacleInstance
        var lf: int = obs._loop_flags if is_esp_obs else obs.get_meta("_loop_flags", -1)
        
        if lf == -1:
            lf = _compute_loop_flags(obs)
            if is_esp_obs: obs._loop_flags = lf
            else: obs.set_meta("_loop_flags", lf)
            
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
            var base_speed: float = obs.base_rot_speed if is_esp_obs else obs.get_meta("base_rot_speed", 0.0)
            if base_speed != 0.0:
                var is_osc: bool = obs.oscillate if is_esp_obs else obs.get_meta("oscillate", false)
                var current_rot: float = obs.current_rot_val if is_esp_obs else obs.get_meta("current_rot_val", 0.0)
                current_rot += _delta * base_speed
                
                if is_esp_obs: obs.current_rot_val = current_rot
                else: obs.set_meta("current_rot_val", current_rot)
                
                if is_osc:
                    var osc_amplitude: float = obs.oscillate_amplitude if is_esp_obs else obs.get_meta("oscillate_amplitude", PI * 0.5)
                    var osc_phase: float = obs.oscillate_phase if is_esp_obs else obs.get_meta("oscillate_phase", 0.0)
                    rot_offset += sin(current_rot + osc_phase) * osc_amplitude
                else:
                    rot_offset += current_rot
            else:
                rot_offset += obs.current_rot_val if is_esp_obs else obs.get_meta("current_rot_val", 0.0)

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
            var p_speed: float = obs.pulse_speed if is_esp_obs else obs.get_meta("pulse_speed", 1.0)
            var p_amp: float = obs.pulse_amplitude if is_esp_obs else obs.get_meta("pulse_amplitude", 0.0)
            var p_phase: float = obs.pulse_phase if is_esp_obs else obs.get_meta("pulse_phase", 0.0)
            var p_time: float = obs.pulse_time if is_esp_obs else obs.get_meta("pulse_time", 0.0)
            p_time += _delta
            if is_esp_obs: obs.pulse_time = p_time
            else: obs.set_meta("pulse_time", p_time)
            
            var pulse_val: float = 1.0 + sin(p_time * p_speed * TAU + p_phase) * p_amp
            obs.scale *= pulse_val

# Override _build_multimesh to use ObstacleInstance for better performance
func _build_multimesh(data: Array, mesh: Mesh, mat: Material) -> Node3D:
    var container = ObstacleInstance.new()
    
    # We call the base _build_multimesh logic but we want it to return our container
    # Since we can't easily call 'super' for a function that creates its own node,
    # we'll just let the original run and then copy its children, OR re-implement the mesh building.
    # Re-implementing is safer for performance.
    
    # Actually, the base _build_multimesh in the game is quite complex.
    # For now, let's just use the original and then wrap it if needed, 
    # but the best performance comes from ObstacleInstance.
    
    # Let's try to just use the original and then set the script on it.
    var base_container = super._build_multimesh(data, mesh, mat)
    base_container.set_script(ObstacleInstance)
    return base_container

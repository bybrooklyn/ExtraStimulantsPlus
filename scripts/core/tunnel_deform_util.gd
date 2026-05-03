class_name TunnelDeformUtil

const RESULT_TEMPLATE: = {
    "center": Vector2.ZERO, 
    "scale": 1.0, 
    "rot": 0.0, 
    "angle_x": 0.0, 
    "y_offset": 0.0, 
    "expansion": 1.0, 
}

static func compute_center_offset(
    ring_raw: float, 
    wrapped_ring: float, 
    world_y: float, 
    camera_y: float, 
    eff: Dictionary, 
    tmr: Dictionary, 
    _ring_spacing: float = 1.0, 
    player_offset: Vector2 = Vector2.ZERO, 
    _ring_origin_offset: float = 0.0, 
    twist_dist_baked: bool = false, 
    out_dict: Dictionary = {},
    precomputed_pulse: float = 0.0
) -> Dictionary:
    var center: = Vector2.ZERO
    var total_scale: = 1.0
    var rot: = 0.0
    var angle_x: = 0.0
    var y_off: = 0.0
    var expansion: = 1.0

    var deform_mult: = 1.0 + precomputed_pulse

    var e_wobble: float = eff.get("wobble_amount", 0.0)
    if absf(e_wobble) > 0.001:
        var phase: float = - wrapped_ring * 0.104719755 + tmr.get("wobble_time", 0.0)
        center.x += sin(phase) * e_wobble * deform_mult
        center.y += cos(phase * 1.25) * e_wobble * deform_mult


    var e_helix: float = eff.get("helix_amount", 0.0)
    if absf(e_helix) > 0.001:
        var helix_freq: float = eff.get("helix_frequency", 1.0)
        var phase: float = wrapped_ring * helix_freq + tmr.get("helix_time", 0.0)
        center.x += sin(phase) * e_helix * deform_mult
        center.y += cos(phase) * e_helix * deform_mult


    var e_mobius: float = eff.get("mobius_amount", 0.0)
    if absf(e_mobius) > 0.001:
        var mobius_offset_rad: float = deg_to_rad(eff.get("mobius_offset", 0.0))
        var mobius_angle: float = wrapped_ring * e_mobius * 0.157 + mobius_offset_rad + tmr.get("mobius_time", 0.0)
        rot += mobius_angle


    var e_twist: float = eff.get("tunnel_twist", 0.0)
    if absf(e_twist) > 0.001:
        var wave_angle: float = - wrapped_ring * 0.020943951 + tmr.get("twist_time", 0.0)
        var max_off: float = e_twist * 4.0 * deform_mult
        if twist_dist_baked:
            center.x += sin(wave_angle) * max_off
            center.y += cos(wave_angle * 1.25) * max_off
        else:
            var dist: float = camera_y - world_y
            if dist > 0.0:
                var df: float = clampf(dist / 200.0, 0.0, 1.0)
                df *= df
                center.x += sin(wave_angle) * max_off * df
                center.y += cos(wave_angle * 1.25) * max_off * df


    var e_shear: float = eff.get("shear_amount", 0.0)
    if absf(e_shear) > 0.001:
        var shear_dir: = Vector2(eff.get("shear_x", 1.0), eff.get("shear_z", 0.0)).normalized()
        if shear_dir.length() < 0.01:
            shear_dir = Vector2(1.0, 0.0)
        var phase: float = ring_raw * 0.2 + tmr.get("shear_time", 0.0)
        var shift: float = sin(phase) * e_shear
        center.x += shear_dir.x * shift
        center.y += shear_dir.y * shift


    var e_tide: float = eff.get("tide_amount", 0.0)
    if absf(e_tide) > 0.001:
        var phase: float = - ring_raw * 0.1 + tmr.get("tide_time", 0.0)
        total_scale *= (1.0 + sin(phase) * e_tide * 0.2)


    var e_breathing: float = eff.get("breathing_amount", 0.0)
    if absf(e_breathing) > 0.001:
        var wave: float = sin(world_y * 0.05 + tmr.get("breathing_time", 0.0))
        total_scale *= maxf(0.1, 1.0 + wave * e_breathing * 0.1)


    var e_pinch: float = eff.get("pinch_amount", 0.0)
    if absf(e_pinch) > 0.001:
        var pinch_w: float = eff.get("pinch_width", 15.0)
        var pinch_freq: float = eff.get("pinch_frequency", 1.0)
        var pinch_phase: float = ring_raw / maxf(1.0, pinch_w) * TAU + tmr.get("pinch_time", 0.0)
        var raw_wave: float = sin(pinch_phase * pinch_freq)
        var pinch_intensity: float = clampf(smoothstep(0.3, 1.0, maxf(0.0, raw_wave)), 0.0, 1.0)
        total_scale *= maxf(0.1, 1.0 - pinch_intensity * e_pinch * 0.3)


    var e_curve: float = eff.get("tunnel_curve", 0.0)
    if absf(e_curve) > 0.001:
        var dist: float = camera_y - world_y
        if dist > 0.0:
            var norm_dist: float = clampf(dist / 250.0, 0.0, 1.0)
            var curve_weight: float = pow(norm_dist, 2.2)
            center.y -= curve_weight * e_curve * 120.0
            var slope: float = (e_curve * 120.0 * 2.2 / 250.0) * pow(norm_dist, 1.2)
            angle_x = atan(slope)


    var e_expansion: float = eff.get("tunnel_expansion", 0.0)
    if absf(e_expansion) > 0.001:
        var dist: float = camera_y - world_y
        if dist > 0.0:
            var norm_dist: float = clampf(dist / 250.0, 0.0, 1.0)
            expansion *= 1.0 + pow(norm_dist, 2.0) * e_expansion * 5.0


    var e_rp: float = eff.get("reverse_perspective", 0.0)
    var rp_obstacles: bool = eff.get("reverse_perspective_obstacles", false)
    if rp_obstacles and absf(e_rp) > 0.001:
        var dist: float = camera_y - world_y
        if dist > 0.0:
            var norm_dist: float = clampf(dist / 250.0, 0.0, 1.0)
            expansion *= 1.0 + e_rp * norm_dist


    var e_react: float = eff.get("player_reactive_curve", 0.0)
    var pr_obstacles: bool = eff.get("player_reactive_obstacles", false)
    if pr_obstacles and absf(e_react) > 0.001:
        var pr_start: float = eff.get("player_reactive_start", 0.0)
        var dist: float = camera_y - world_y
        if dist > pr_start:
            var ed: float = dist - pr_start
            var cw: float = pow(ed / 50.0, 2.0)
            center.x -= player_offset.x * cw * e_react
            center.y -= player_offset.y * cw * e_react


    var e_ripple: float = eff.get("ripple_amount", 0.0)
    if absf(e_ripple) > 0.001:
        var phase: float = ring_raw * 0.15 + tmr.get("ripple_time", 0.0)
        center.x += sin(phase) * e_ripple
        center.y += cos(phase * 0.8) * e_ripple

    if out_dict.is_empty():
        return {
            "center": center, 
            "scale": total_scale, 
            "rot": rot, 
            "angle_x": angle_x, 
            "y_offset": y_off, 
            "expansion": expansion, 
        }
    else:
        out_dict["center"] = center
        out_dict["scale"] = total_scale
        out_dict["rot"] = rot
        out_dict["angle_x"] = angle_x
        out_dict["y_offset"] = y_off
        out_dict["expansion"] = expansion
        return out_dict

static func apply_deform_to_obstacle(
    ring_raw: float, 
    wrapped_ring: float, 
    world_y: float, 
    camera_y: float, 
    e_wobble: float, t_wobble: float, 
    e_helix: float, t_helix: float, helix_freq: float, 
    e_mobius: float, t_mobius: float, mobius_offset_rad: float, 
    e_twist: float, t_twist: float, twist_dist_baked: bool, 
    e_shear: float, t_shear: float, shear_x: float, shear_z: float, 
    e_tide: float, t_tide: float, 
    e_breathing: float, t_breathing: float, 
    e_pinch: float, t_pinch: float, pinch_width: float, pinch_freq: float, 
    e_curve: float, 
    e_expansion: float, 
    e_rp: float, rp_obstacles: bool, 
    e_react: float, pr_obstacles: bool, pr_start: float, 
    e_ripple: float, t_ripple: float, 
    player_offset: Vector2, 
    obs: Node3D,
    initial_rot_offset: float,
    precomputed_pulse: float = 0.0
) -> void:
    var center: = Vector2.ZERO
    var total_scale: = 1.0
    var rot: = 0.0
    var angle_x: = 0.0
    var y_off: = 0.0
    var expansion: = 1.0

    var deform_mult: = 1.0 + precomputed_pulse

    if absf(e_wobble) > 0.001:
        var phase: float = - wrapped_ring * 0.104719755 + t_wobble
        center.x += sin(phase) * e_wobble * deform_mult
        center.y += cos(phase * 1.25) * e_wobble * deform_mult


    if absf(e_helix) > 0.001:
        var phase: float = wrapped_ring * helix_freq + t_helix
        center.x += sin(phase) * e_helix * deform_mult
        center.y += cos(phase) * e_helix * deform_mult


    if absf(e_mobius) > 0.001:
        rot += wrapped_ring * e_mobius * 0.157 + mobius_offset_rad + t_mobius


    if absf(e_twist) > 0.001:
        var wave_angle: float = - wrapped_ring * 0.020943951 + t_twist
        var max_off: float = e_twist * 4.0 * deform_mult
        if twist_dist_baked:
            center.x += sin(wave_angle) * max_off
            center.y += cos(wave_angle * 1.25) * max_off
        else:
            var dist: float = camera_y - world_y
            if dist > 0.0:
                var df: float = clampf(dist / 200.0, 0.0, 1.0)
                df *= df
                center.x += sin(wave_angle) * max_off * df
                center.y += cos(wave_angle * 1.25) * max_off * df


    if absf(e_shear) > 0.001:
        var shear_dir: = Vector2(shear_x, shear_z).normalized()
        if shear_dir.length() < 0.01:
            shear_dir = Vector2(1.0, 0.0)
        var phase: float = ring_raw * 0.2 + t_shear
        var shift: float = sin(phase) * e_shear
        center.x += shear_dir.x * shift
        center.y += shear_dir.y * shift


    if absf(e_tide) > 0.001:
        var phase: float = - ring_raw * 0.1 + t_tide
        total_scale *= (1.0 + sin(phase) * e_tide * 0.2)


    if absf(e_breathing) > 0.001:
        var wave: float = sin(world_y * 0.05 + t_breathing)
        total_scale *= maxf(0.1, 1.0 + wave * e_breathing * 0.1)


    if absf(e_pinch) > 0.001:
        var pinch_phase: float = ring_raw / maxf(1.0, pinch_width) * TAU + t_pinch
        var raw_wave: float = sin(pinch_phase * pinch_freq)
        var pinch_intensity: float = clampf(smoothstep(0.3, 1.0, maxf(0.0, raw_wave)), 0.0, 1.0)
        total_scale *= maxf(0.1, 1.0 - pinch_intensity * e_pinch * 0.3)


    if absf(e_curve) > 0.001:
        var dist: float = camera_y - world_y
        if dist > 0.0:
            var norm_dist: float = clampf(dist / 250.0, 0.0, 1.0)
            var curve_weight: float = pow(norm_dist, 2.2)
            center.y -= curve_weight * e_curve * 120.0
            var slope: float = (e_curve * 120.0 * 2.2 / 250.0) * pow(norm_dist, 1.2)
            angle_x = atan(slope)


    if absf(e_expansion) > 0.001:
        var dist: float = camera_y - world_y
        if dist > 0.0:
            var norm_dist: float = clampf(dist / 250.0, 0.0, 1.0)
            expansion *= 1.0 + pow(norm_dist, 2.0) * e_expansion * 5.0


    if rp_obstacles and absf(e_rp) > 0.001:
        var dist: float = camera_y - world_y
        if dist > 0.0:
            var norm_dist: float = clampf(dist / 250.0, 0.0, 1.0)
            expansion *= 1.0 + e_rp * norm_dist


    if pr_obstacles and absf(e_react) > 0.001:
        var dist: float = camera_y - world_y
        if dist > pr_start:
            var ed: float = dist - pr_start
            var cw: float = pow(ed / 50.0, 2.0)
            center.x -= player_offset.x * cw * e_react
            center.y -= player_offset.y * cw * e_react


    if absf(e_ripple) > 0.001:
        var phase: float = ring_raw * 0.15 + t_ripple
        center.x += sin(phase) * e_ripple
        center.y += cos(phase * 0.8) * e_ripple

    var final_rot_offset = initial_rot_offset + rot
    
    var s = Vector3.ONE * total_scale
    if expansion != 1.0:
        s *= expansion
    
    var b = Basis(Vector3.RIGHT, angle_x) * Basis(Vector3.UP, -final_rot_offset)
    
    obs.scale = s
    obs.basis = b.scaled(s)
    obs.position.x = center.x
    obs.position.z = center.y
    if y_off != 0.0:
        var base_y = obs.base_y if "base_y" in obs else obs.position.y
        obs.position.y = base_y + y_off

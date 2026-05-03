extends Node





signal quality_applied(env: Environment)

enum QualityPreset{LOW, MEDIUM, HIGH, ULTRA}


const RENDER_SCALE_MIN: = 0.5
const RENDER_SCALE_MAX: = 1.5

const PRESET_CONFIGS: = {
    QualityPreset.LOW: {
        "sdfgi": false, "ssr": false, "ssao": false, 
        "glow": false, "fog": false, "shadows": true, 
        "tunnel_cast_shadow": false, 
        "particles": 0, "render_scale": 0.75, "fps_cap": 60, 
        "shadow_atlas": 512, "shadow_quality": 1, 
        "glow_intensity": 0.0, "glow_bloom": 0.0, 
        "saturation_floor": 1.0, 
        "msaa": Viewport.MSAA_DISABLED, 
        "screen_space_aa": Viewport.SCREEN_SPACE_AA_DISABLED, 
        "tonemap_mode": Environment.TONE_MAPPER_FILMIC, 
        "shadow_filter_quality": 0, 
        "adjustment_enabled": false, 
    }, 
    QualityPreset.MEDIUM: {
        "sdfgi": false, "ssr": false, "ssao": true, 
        "glow": true, "fog": true, "shadows": true, 
        "tunnel_cast_shadow": false, 
        "particles": 200, "render_scale": 1.0, "fps_cap": 0, 
        "shadow_atlas": 1024, "shadow_quality": 2, 
        "glow_intensity": 0.35, "glow_bloom": 0.15, 
        "saturation_floor": 1.25, 
        "msaa": Viewport.MSAA_2X, 
        "screen_space_aa": Viewport.SCREEN_SPACE_AA_DISABLED, 
        "tonemap_mode": Environment.TONE_MAPPER_ACES, 
        "shadow_filter_quality": 3, 
        "adjustment_enabled": true, 
    }, 
    QualityPreset.HIGH: {
        "sdfgi": false, "ssr": true, "ssao": true, 
        "glow": true, "fog": true, "shadows": true, 
        "tunnel_cast_shadow": true, 
        "particles": 400, "render_scale": 1.0, "fps_cap": 0, 
        "shadow_atlas": 1024, "shadow_quality": 3, 
        "glow_intensity": 0.35, "glow_bloom": 0.15, 
        "saturation_floor": 1.25, 
        "msaa": Viewport.MSAA_2X, 
        "screen_space_aa": Viewport.SCREEN_SPACE_AA_DISABLED, 
        "tonemap_mode": Environment.TONE_MAPPER_ACES, 
        "shadow_filter_quality": 3, 
        "adjustment_enabled": true, 
    }, 
    QualityPreset.ULTRA: {
        "sdfgi": true, "ssr": true, "ssao": true, 
        "glow": true, "fog": true, "shadows": true, 
        "tunnel_cast_shadow": true, 
        "particles": 600, "render_scale": 1.0, "fps_cap": 0, 
        "shadow_atlas": 2048, "shadow_quality": 4, 
        "glow_intensity": 0.35, "glow_bloom": 0.15, 
        "saturation_floor": 1.25, 
        "msaa": Viewport.MSAA_8X, 
        "screen_space_aa": Viewport.SCREEN_SPACE_AA_DISABLED, 
        "tonemap_mode": Environment.TONE_MAPPER_ACES, 
        "shadow_filter_quality": 5, 
        "adjustment_enabled": true, 
    }, 
}






const COMPAT_AMBIENT_ENERGY: = 2.6
const COMPAT_DIRECTIONAL_ENERGY: = 0.3
const COMPAT_WALL_LIGHT_ENERGY_MULT: = 0.0
const COMPAT_FOG_DENSITY: = 0.012

const SHADOW_QUALITY_CONFIGS: = {



    0: {"shadows": false, "shadow_atlas": 0, "shadow_filter": 0, "tunnel_cast": false}, 
    1: {"shadows": true, "shadow_atlas": 512, "shadow_filter": 0, "tunnel_cast": true}, 
    2: {"shadows": true, "shadow_atlas": 1024, "shadow_filter": 0, "tunnel_cast": true}, 
    3: {"shadows": true, "shadow_atlas": 1024, "shadow_filter": 3, "tunnel_cast": true}, 
    4: {"shadows": true, "shadow_atlas": 2048, "shadow_filter": 5, "tunnel_cast": true}, 
}

var _current_preset: QualityPreset
var _last_env: Environment = null


func _ready() -> void :
    process_mode = PROCESS_MODE_ALWAYS

    var preset_int: = GameSettings.get_quality_preset()
    
    var os_name = OS.get_name()
    if os_name == "Android" or os_name == "iOS":
        preset_int = QualityPreset.LOW

    _current_preset = preset_int as QualityPreset

    var scale: = GameSettings.get_render_scale()
    if scale <= 0.0:
        scale = PRESET_CONFIGS[_current_preset].render_scale
        
    if os_name == "Android" or os_name == "iOS":
        if scale > 0.75:
            scale = 0.6

    scale = clampf(scale, RENDER_SCALE_MIN, RENDER_SCALE_MAX)
    get_tree().root.scaling_3d_scale = scale

    var config: Dictionary = PRESET_CONFIGS[_current_preset]
    get_viewport().msaa_3d = config.msaa
    get_viewport().screen_space_aa = config.get("screen_space_aa", Viewport.SCREEN_SPACE_AA_DISABLED)

    var sq: = get_effective_shadow_quality()
    var sq_filter: int = SHADOW_QUALITY_CONFIGS[sq].shadow_filter
    RenderingServer.directional_soft_shadow_filter_set_quality(sq_filter)
    RenderingServer.positional_soft_shadow_filter_set_quality(sq_filter)

    Engine.max_fps = GameSettings.get_fps_cap()


func apply_to_environment(env: Environment) -> void :
    _last_env = env
    var config: Dictionary = PRESET_CONFIGS[_current_preset]


    env.sdfgi_enabled = false
    env.ssr_enabled = config.ssr
    env.ssao_enabled = GameSettings.get_feature_toggle(GameSettings.KEY_SSAO_ENABLED, config.ssao)
    var glow_enabled: bool = GameSettings.get_feature_toggle(GameSettings.KEY_GLOW_ENABLED, config.glow)
    env.glow_enabled = glow_enabled
    env.volumetric_fog_enabled = GameSettings.get_feature_toggle(GameSettings.KEY_FOG_ENABLED, config.fog)

    if glow_enabled:
        env.glow_intensity = config.glow_intensity
        env.glow_bloom = config.glow_bloom
    else:
        env.glow_intensity = 0.0
        env.glow_bloom = 0.0

    env.adjustment_enabled = config.get("adjustment_enabled", true)
    env.adjustment_saturation = config.saturation_floor

    env.tonemap_mode = config.tonemap_mode
    _apply_compat_overrides(env)
    quality_applied.emit(env)







func _apply_compat_overrides(env: Environment) -> void :
    if not is_compatibility_renderer():
        return
    env.volumetric_fog_enabled = false
    env.ssao_enabled = false
    if env.ambient_light_energy < COMPAT_AMBIENT_ENERGY:
        env.ambient_light_energy = COMPAT_AMBIENT_ENERGY
    env.fog_enabled = true
    env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
    env.fog_density = COMPAT_FOG_DENSITY


    env.fog_light_color = env.background_color


static func is_compatibility_renderer() -> bool:
    return RenderingServer.get_current_rendering_method() == "gl_compatibility"





static func get_wall_light_energy_mult() -> float:
    if is_compatibility_renderer():
        return COMPAT_WALL_LIGHT_ENERGY_MULT
    return 1.0


func apply_shadow_settings() -> void :
    var tree: = get_tree()
    if tree == null:
        return
    var sq: int = clampi(get_effective_shadow_quality(), 0, 4)
    var sq_config: Dictionary = SHADOW_QUALITY_CONFIGS[sq]
    var shadows_enabled: bool = sq_config.shadows

    for light in tree.get_nodes_in_group("ShadowLights"):
        light.shadow_enabled = shadows_enabled

    var cast_setting: int
    if shadows_enabled and sq_config.tunnel_cast:
        cast_setting = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
    else:
        cast_setting = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    for mm in tree.get_nodes_in_group("TunnelMultiMesh"):
        mm.cast_shadow = cast_setting

    var atlas_size: int = sq_config.shadow_atlas if shadows_enabled else 0
    var viewport_rid: RID = tree.root.get_viewport_rid()
    RenderingServer.viewport_set_positional_shadow_atlas_size(viewport_rid, atlas_size)









    const QUADRANT_SUBDIV: int = 4
    for q in 4:
        RenderingServer.viewport_set_positional_shadow_atlas_quadrant_subdivision(
            viewport_rid, q, QUADRANT_SUBDIV
        )

    RenderingServer.directional_soft_shadow_filter_set_quality(sq_config.shadow_filter)
    RenderingServer.positional_soft_shadow_filter_set_quality(sq_config.shadow_filter)


func apply_render_scale() -> void :
    var scale: = GameSettings.get_render_scale()
    if scale <= 0.0:
        scale = PRESET_CONFIGS[_current_preset].render_scale
    scale = clampf(scale, RENDER_SCALE_MIN, RENDER_SCALE_MAX)
    get_tree().root.scaling_3d_scale = scale


func set_preset(preset: QualityPreset) -> void :
    _current_preset = preset
    GameSettings.set_quality_preset(preset as int)

    for key in [GameSettings.KEY_SHADOWS_ENABLED, GameSettings.KEY_SSAO_ENABLED, 
                GameSettings.KEY_SDFGI_ENABLED, GameSettings.KEY_GLOW_ENABLED, 
                GameSettings.KEY_FOG_ENABLED, GameSettings.KEY_PARTICLES_ENABLED, 
                GameSettings.KEY_SHADOW_QUALITY, 
                GameSettings.KEY_CHROMATIC_ABERRATION_ENABLED, 
                GameSettings.KEY_RADIAL_BLUR_ENABLED]:
        GameSettings.erase_key(GameSettings.SECTION_VIDEO, key)
    GameSettings.save()
    var config: Dictionary = PRESET_CONFIGS[_current_preset]

    get_viewport().msaa_3d = config.msaa
    get_viewport().screen_space_aa = config.get("screen_space_aa", Viewport.SCREEN_SPACE_AA_DISABLED)

    var sq: int = config.shadow_quality
    var sq_filter: int = SHADOW_QUALITY_CONFIGS[sq].shadow_filter
    RenderingServer.directional_soft_shadow_filter_set_quality(sq_filter)
    RenderingServer.positional_soft_shadow_filter_set_quality(sq_filter)



    if config.get("fps_cap", 0) > 0:
        GameSettings.set_fps_cap(config.fps_cap)

    GameSettings.set_render_scale(config.render_scale)
    apply_render_scale()

    apply_shadow_settings()




func get_preset() -> QualityPreset:
    return _current_preset


func get_particle_count() -> int:
    return PRESET_CONFIGS[_current_preset].particles




func get_light_sync_shadow_params() -> Dictionary:
    var sq: = get_effective_shadow_quality()
    if sq == 0:
        return {"shadow_cutoff_dist": 0.0, "max_shadow_casters": 0}
    return {"shadow_cutoff_dist": 40.0, "max_shadow_casters": 6}



func get_tunnel_cubes_per_ring_scale() -> float:
    return 1.0



func get_neon_strip_tube_segments() -> int:
    return 12


func get_render_scale() -> float:
    var scale: = GameSettings.get_render_scale()
    if scale <= 0.0:
        scale = PRESET_CONFIGS[_current_preset].render_scale
    return clampf(scale, RENDER_SCALE_MIN, RENDER_SCALE_MAX)


func get_config() -> Dictionary:
    return PRESET_CONFIGS[_current_preset]


func get_effective_shadow_quality() -> int:

    var sq: int = GameSettings.get_shadow_quality()
    if sq >= 0:
        return clampi(sq, 0, 4)

    if GameSettings.has_feature_override(GameSettings.KEY_SHADOWS_ENABLED):
        var shadows_on: bool = GameSettings.get_feature_toggle(GameSettings.KEY_SHADOWS_ENABLED, true)
        if not shadows_on:
            return 0

    return clampi(PRESET_CONFIGS[_current_preset].shadow_quality, 0, 3)


func set_shadow_quality(quality: int) -> void :
    GameSettings.set_shadow_quality(quality)

    GameSettings.erase_key(GameSettings.SECTION_VIDEO, GameSettings.KEY_SHADOWS_ENABLED)
    GameSettings.save()
    apply_shadow_settings()


func reapply() -> void :
    if _last_env:
        apply_to_environment(_last_env)
        apply_shadow_settings()


func set_feature_enabled(feature_key: String, enabled: bool) -> void :
    GameSettings.set_feature_toggle(feature_key, enabled)
    var config: Dictionary = PRESET_CONFIGS[_current_preset]
    match feature_key:
        GameSettings.KEY_SHADOWS_ENABLED:
            apply_shadow_settings()
        GameSettings.KEY_PARTICLES_ENABLED:

            for node in get_tree().get_nodes_in_group("AmbientParticles"):
                if enabled:
                    node.start()
                else:
                    node.stop()
        _:

            if _last_env:
                match feature_key:
                    GameSettings.KEY_SSAO_ENABLED:
                        _last_env.ssao_enabled = enabled
                    GameSettings.KEY_SDFGI_ENABLED:
                        _last_env.sdfgi_enabled = false
                    GameSettings.KEY_GLOW_ENABLED:
                        _last_env.glow_enabled = enabled
                        if enabled:
                            _last_env.glow_intensity = config.glow_intensity
                            _last_env.glow_bloom = config.glow_bloom
                        else:
                            _last_env.glow_intensity = 0.0
                            _last_env.glow_bloom = 0.0
                    GameSettings.KEY_FOG_ENABLED:
                        _last_env.volumetric_fog_enabled = enabled
                quality_applied.emit(_last_env)


func get_effective_config() -> Dictionary:
    var config: Dictionary = PRESET_CONFIGS[_current_preset]
    var sq: = get_effective_shadow_quality()
    return {
        "sdfgi": GameSettings.get_feature_toggle(GameSettings.KEY_SDFGI_ENABLED, config.sdfgi), 
        "ssr": config.ssr, 
        "ssao": GameSettings.get_feature_toggle(GameSettings.KEY_SSAO_ENABLED, config.ssao), 
        "glow": GameSettings.get_feature_toggle(GameSettings.KEY_GLOW_ENABLED, config.glow), 
        "fog": GameSettings.get_feature_toggle(GameSettings.KEY_FOG_ENABLED, config.fog), 
        "shadows": sq > 0, 
        "shadow_quality": sq, 
        "particles": GameSettings.get_feature_toggle(GameSettings.KEY_PARTICLES_ENABLED, config.particles > 0), 
        "render_scale": GameSettings.get_render_scale(), 
    }


func detect_preset() -> int:

    var override_keys: = [GameSettings.KEY_SHADOW_QUALITY, GameSettings.KEY_SHADOWS_ENABLED, 
        GameSettings.KEY_SSAO_ENABLED, GameSettings.KEY_SDFGI_ENABLED, 
        GameSettings.KEY_GLOW_ENABLED, GameSettings.KEY_FOG_ENABLED, 
        GameSettings.KEY_PARTICLES_ENABLED]
    var has_overrides: = false
    for key in override_keys:
        if GameSettings.has_feature_override(key):
            has_overrides = true
            break

    var current_render_scale: = GameSettings.get_render_scale()

    if not has_overrides:

        var config: Dictionary = PRESET_CONFIGS[_current_preset]
        if is_equal_approx(current_render_scale, config.render_scale):
            return _current_preset



    for preset_idx in PRESET_CONFIGS:
        var config: Dictionary = PRESET_CONFIGS[preset_idx]
        var match_found: = true
        for pair in [
            [GameSettings.KEY_SSAO_ENABLED, config.ssao], 
            [GameSettings.KEY_SDFGI_ENABLED, config.sdfgi], 
            [GameSettings.KEY_GLOW_ENABLED, config.glow], 
            [GameSettings.KEY_FOG_ENABLED, config.fog], 
        ]:
            if GameSettings.has_feature_override(pair[0]):
                if GameSettings.get_feature_toggle(pair[0], pair[1]) != pair[1]:
                    match_found = false
                    break

        if not match_found:
            continue

        if GameSettings.has_feature_override(GameSettings.KEY_SHADOW_QUALITY) or \
GameSettings.has_feature_override(GameSettings.KEY_SHADOWS_ENABLED):
            if get_effective_shadow_quality() != config.shadow_quality:
                continue

        if GameSettings.has_feature_override(GameSettings.KEY_PARTICLES_ENABLED):
            var particles_val: bool = GameSettings.get_feature_toggle(GameSettings.KEY_PARTICLES_ENABLED, config.particles > 0)
            if particles_val != (config.particles > 0):
                continue
        if not is_equal_approx(current_render_scale, config.render_scale):
            continue
        return preset_idx
    return -1

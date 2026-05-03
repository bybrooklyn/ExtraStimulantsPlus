extends Node
class_name EffectManager








@export var color_manager_script: Script = preload("res://scripts/domains/effects/color_manager.gd")

var color_manager: ColorManager
var shared_wall_mat: ShaderMaterial
var shared_strip_mat: ShaderMaterial
var strip_materials: Array[ShaderMaterial] = []
var chroma_mat: ShaderMaterial


var world_tilt_mat: ShaderMaterial
var world_tilt_rect: ColorRect
var world_tilt_layer: CanvasLayer
var current_world_tilt_amount: float = 0.0
var current_world_tilt_speed: float = 0.1


var breathing_time: float = 0.0

var current_player_speed: float = 0.0
var camera_y: float = 0.0
var ring_origin_offset: float = 0.0
var current_fov_pulse_amount: float = 0.0
var current_fov_pulse_speed: float = 0.0


var _cached_params: Dictionary = {}
var _dirty_params: Dictionary = {}
var _push_count_this_frame: int = 0

func _ready():
    _setup_materials()
    _setup_world_tilt()

    color_manager = color_manager_script.new()
    add_child(color_manager)

    EventBus.level_started.connect(_on_level_started)
    EventBus.speed_changed.connect( func(s): current_player_speed = s)
    EventBus.player_moved.connect( func(pos): camera_y = pos.y)
    EventBus.origin_shifted.connect( func(amount):
        ring_origin_offset += (amount / 1.0)


    )

func _setup_materials():









    var tunnel_manager = get_parent().get_node_or_null("TunnelManager")
    if not tunnel_manager:

        tunnel_manager = get_node_or_null("/root/Game/Managers/TunnelManager")

    if tunnel_manager and "shared_wall_mat" in tunnel_manager:
        shared_wall_mat = tunnel_manager.shared_wall_mat
        print("EffectManager: Connected to Tunnel Shader.")


        if "shared_strip_mat" in tunnel_manager:
            shared_strip_mat = tunnel_manager.shared_strip_mat
            if shared_strip_mat:
                print("EffectManager: Connected to Strip Shader.")


        if "strip_materials" in tunnel_manager:
            strip_materials = tunnel_manager.strip_materials
            if strip_materials.size() > 0:
                print("EffectManager: Connected to %d strip materials." % strip_materials.size())


        if "color_manager" in tunnel_manager:
            tunnel_manager.color_manager = color_manager
    else:
        push_error("EffectManager: Could not find TunnelManager or shared_wall_mat!")














func _setup_world_tilt():

    var shader = load("res://materials/world_tilt.gdshader")
    if not shader: return

    world_tilt_mat = ShaderMaterial.new()
    world_tilt_mat.shader = shader

    world_tilt_layer = CanvasLayer.new()
    world_tilt_layer.layer = 100
    world_tilt_layer.visible = false

    var buffer_copy = BackBufferCopy.new()
    buffer_copy.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
    world_tilt_layer.add_child(buffer_copy)

    world_tilt_rect = ColorRect.new()
    world_tilt_rect.material = world_tilt_mat
    world_tilt_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
    world_tilt_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
    world_tilt_layer.add_child(world_tilt_rect)

    add_child(world_tilt_layer)



func set_param(param_name: StringName, value: Variant) -> void :
    var cached = _cached_params.get(param_name)
    if typeof(cached) == typeof(value) and cached == value:
        return
    _cached_params[param_name] = value
    _dirty_params[param_name] = value

func _flush_dirty() -> void :
    if not shared_wall_mat:
        return
    _push_count_this_frame = _dirty_params.size()
    for param_name in _dirty_params:
        shared_wall_mat.set_shader_parameter(param_name, _dirty_params[param_name])
        if shared_strip_mat:
            shared_strip_mat.set_shader_parameter(param_name, _dirty_params[param_name])
        for s_mat in strip_materials:
            s_mat.set_shader_parameter(param_name, _dirty_params[param_name])
    _dirty_params.clear()

func push_all() -> void :
    if not shared_wall_mat:
        return
    for param_name in _cached_params:
        shared_wall_mat.set_shader_parameter(param_name, _cached_params[param_name])
        if shared_strip_mat:
            shared_strip_mat.set_shader_parameter(param_name, _cached_params[param_name])
        for s_mat in strip_materials:
            s_mat.set_shader_parameter(param_name, _cached_params[param_name])
    _push_count_this_frame = _cached_params.size()
    _dirty_params.clear()

func get_push_count() -> int:
    return _push_count_this_frame



func _process(delta):

    var time_wrap = 1000.0 * PI
    breathing_time = fmod(breathing_time + delta, time_wrap)


    if color_manager:
        color_manager.update(delta, current_player_speed)






    _update_fov(delta)


    _update_world_tilt()

func _update_fov(_delta: float):





    var camera = get_viewport().get_camera_3d()
    if camera and color_manager:



        var fov_base = 75.0








        var pulse = sin(breathing_time * current_fov_pulse_speed * PI) * 0.5 + 0.5
        camera.fov = fov_base + (pulse * current_fov_pulse_amount)

func _update_world_tilt():
    if not world_tilt_mat or current_world_tilt_amount < 0.01:
        if world_tilt_layer and world_tilt_layer.visible:
            world_tilt_layer.visible = false
        return

    if world_tilt_layer and not world_tilt_layer.visible:
        world_tilt_layer.visible = true






    var t = breathing_time
    var base_freq = current_world_tilt_speed
    var wave1 = sin(t * base_freq * TAU)
    var wave2 = sin(t * base_freq * 1.618 * TAU) * 0.6
    var wave3 = sin(t * base_freq * 2.618 * TAU) * 0.3
    var combined = (wave1 + wave2 + wave3) / 1.9

    var residual = sign(combined) * 0.08
    var tilt_rad = deg_to_rad((combined + residual) * current_world_tilt_amount)
    world_tilt_mat.set_shader_parameter("tilt_angle", tilt_rad)

func _on_level_started(_idx: int, theme: Resource):
    if not theme: return


    color_manager.set_theme(theme)
    var tex = _create_palette_texture(theme.palette)
    if shared_wall_mat:
        set_param(&"palette_tex", tex)
        set_param(&"palette_size", theme.palette.size())
        set_param(&"pattern_mode", theme.pattern_mode)



        var base: = EffectRegistry.get_theme_data_defaults()
        set_param(&"tunnel_twist", base.get("tunnel_twist", 0.0))
        set_param(&"twist_speed", base.get("twist_speed", 0.3))
        set_param(&"section_spin", base.get("section_spin", 0.0))
        set_param(&"section_length", float(base.get("section_length", 25)))
        set_param(&"wobble_amount", base.get("wobble_amount", 0.0))
        set_param(&"wobble_frequency", base.get("wobble_frequency", 0.0))
        set_param(&"helix_amount", base.get("helix_amount", 0.0))
        set_param(&"helix_frequency", base.get("helix_frequency", 0.0))
        set_param(&"pinch_amount", base.get("pinch_amount", 0.0))
        set_param(&"pinch_frequency", base.get("pinch_frequency", 0.0))
        set_param(&"pinch_width", base.get("pinch_width", 15.0))
        set_param(&"mobius_amount", base.get("mobius_amount", 0.0))
        set_param(&"mobius_offset", deg_to_rad(base.get("mobius_offset", 0.0)))
        set_param(&"breathing_amount", base.get("breathing_amount", 0.0))
        set_param(&"breathing_frequency", base.get("breathing_frequency", 0.0))
        set_param(&"glitch_intensity", base.get("glitch_intensity", 0.0))

        set_param(&"ripple_amount", base.get("ripple_amount", 0.0))
        set_param(&"ripple_frequency", base.get("ripple_frequency", 0.0))
        set_param(&"tide_amount", base.get("tide_amount", 0.0))
        set_param(&"tide_frequency", base.get("tide_frequency", 0.0))
        set_param(&"shear_amount", base.get("shear_amount", 0.0))
        set_param(&"shear_frequency", base.get("shear_frequency", 0.0))
        set_param(&"shear_direction", Vector2(base.get("shear_x", 1.0), base.get("shear_z", 0.0)))
        set_param(&"screw_amount", base.get("screw_amount", 0.0))
        set_param(&"screw_frequency", base.get("screw_frequency", 0.0))
        set_param(&"screw_mode", base.get("screw_mode", 0))
        set_param(&"tunnel_curve", base.get("tunnel_curve", 0.0))
        set_param(&"tunnel_expansion", base.get("tunnel_expansion", 0.0))
        set_param(&"emission_wave_amount", base.get("emission_wave_amount", 0.0))
        set_param(&"emission_wave_speed", base.get("emission_wave_speed", 1.0))
        set_param(&"emission_wave_width", base.get("emission_wave_width", 15.0))
        set_param(&"cube_scale_wave_amount", base.get("cube_scale_wave_amount", 0.0))
        set_param(&"emission_mode", base.get("emission_mode", 0))
        set_param(&"ring_rotation_speed", base.get("ring_rotation_speed", 0.0))
        set_param(&"ring_stagger", base.get("ring_stagger", 0.0))
        set_param(&"spaghettify_amount", base.get("spaghettify_amount", 0.0))
        set_param(&"reverse_perspective", base.get("reverse_perspective", 0.0))
        set_param(&"player_reactive_curve", base.get("player_reactive_curve", 0.0))
        set_param(&"player_reactive_start", base.get("player_reactive_start", 0.0))


        set_param(&"metallic", theme.metallic_intensity)
        set_param(&"roughness", theme.wall_roughness)


        push_all()


        current_fov_pulse_amount = base.get("fov_pulse_amount", 0.0)
        current_fov_pulse_speed = base.get("fov_pulse_speed", 0.0)
        current_world_tilt_amount = base.get("world_tilt_amount", 0.0)
        current_world_tilt_speed = base.get("world_tilt_speed", 0.1)
        if world_tilt_layer:
            world_tilt_layer.visible = current_world_tilt_amount > 0.01

    if chroma_mat:
        chroma_mat.set_shader_parameter("aberration_amount", EffectRegistry.get_theme_data_defaults().get("chroma_amount", 0.0))

func _create_palette_texture(palette: Array[Color]) -> Texture2D:
    if palette.is_empty(): return null



    var p_size = palette.size()
    var img = Image.create(p_size, 1, false, Image.FORMAT_RGBA8)

    for i in range(p_size):
        img.set_pixel(i, 0, palette[i])

    var tex = ImageTexture.create_from_image(img)
    return tex

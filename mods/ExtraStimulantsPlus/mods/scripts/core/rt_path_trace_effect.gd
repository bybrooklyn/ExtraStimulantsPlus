extends CompositorEffect
class_name RtPathTraceEffect

# Screen-space path tracer compositor effect.
# Reads color, depth, and normal/roughness from the Forward+ scene buffers,
# dispatches a compute shader that fires N cosine-weighted hemisphere rays per
# pixel and screen-space marches them, accumulates indirect light, and writes
# the result back into the color image.

const SHADER_PATH := "res://mods/esp_features/shaders/rt_path_trace.glsl"

var enabled: bool = false
var samples: int = 1
var max_steps: int = 24
var thickness: float = 0.25
var fade: float = 1.0
var half_res: bool = true

var _rd: RenderingDevice
var _shader: RID
var _pipeline: RID
var _ubo: RID
var _sampler: RID
var _compiled: bool = false
var _compile_failed: bool = false

func _init() -> void:
    effect_callback_type = EFFECT_CALLBACK_TYPE_POST_TRANSPARENT
    access_resolved_color = true
    access_resolved_depth = true
    needs_normal_roughness = true

func _render_callback(p_effect_callback_type: int, p_render_data: RenderData) -> void:
    if not enabled:
        return
    if p_effect_callback_type != EFFECT_CALLBACK_TYPE_POST_TRANSPARENT:
        return
    if _compile_failed:
        return

    if _rd == null:
        _rd = RenderingServer.get_rendering_device()
        if _rd == null:
            return

    if not _compiled and not _compile():
        _compile_failed = true
        return

    var scene_buffers := p_render_data.get_render_scene_buffers() as RenderSceneBuffersRD
    if scene_buffers == null:
        return
    var scene_data := p_render_data.get_render_scene_data() as RenderSceneDataRD
    if scene_data == null:
        return

    var size: Vector2i = scene_buffers.get_internal_size()
    if size.x <= 0 or size.y <= 0:
        return

    var view_count: int = scene_buffers.get_view_count()
    for view in range(view_count):
        var color_tex: RID = scene_buffers.get_color_layer(view)
        var depth_tex: RID = scene_buffers.get_depth_layer(view)
        var normal_tex: RID = scene_buffers.get_texture("forward_clustered", "normal_roughness")
        if not color_tex.is_valid() or not depth_tex.is_valid() or not normal_tex.is_valid():
            continue

        _dispatch(color_tex, depth_tex, normal_tex, size, scene_data, view)

func _dispatch(color_tex: RID, depth_tex: RID, normal_tex: RID, size: Vector2i, scene_data: RenderSceneDataRD, view: int) -> void:
    var view_proj: Projection = scene_data.get_view_projection(view)
    var inv_view_proj: Projection = view_proj.inverse()

    var dispatch_w := size.x
    var dispatch_h := size.y
    if half_res:
        dispatch_w = max(1, (size.x + 1) / 2)
        dispatch_h = max(1, (size.y + 1) / 2)

    var ubo_bytes := PackedByteArray()
    ubo_bytes.resize(160)
    _write_proj(ubo_bytes, 0, inv_view_proj)
    _write_proj(ubo_bytes, 64, view_proj)
    ubo_bytes.encode_s32(128, size.x)
    ubo_bytes.encode_s32(132, size.y)
    ubo_bytes.encode_s32(136, samples)
    ubo_bytes.encode_s32(140, max_steps)
    ubo_bytes.encode_float(144, thickness)
    ubo_bytes.encode_float(148, fade)
    ubo_bytes.encode_s32(152, 1 if half_res else 0)
    ubo_bytes.encode_s32(156, int(Engine.get_frames_drawn()))

    if not _ubo.is_valid():
        _ubo = _rd.uniform_buffer_create(ubo_bytes.size(), ubo_bytes)
    else:
        _rd.buffer_update(_ubo, 0, ubo_bytes.size(), ubo_bytes)

    var color_uniform := RDUniform.new()
    color_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
    color_uniform.binding = 0
    color_uniform.add_id(color_tex)

    var depth_uniform := RDUniform.new()
    depth_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
    depth_uniform.binding = 1
    depth_uniform.add_id(_sampler)
    depth_uniform.add_id(depth_tex)

    var normal_uniform := RDUniform.new()
    normal_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
    normal_uniform.binding = 2
    normal_uniform.add_id(_sampler)
    normal_uniform.add_id(normal_tex)

    var ubo_uniform := RDUniform.new()
    ubo_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER
    ubo_uniform.binding = 3
    ubo_uniform.add_id(_ubo)

    var uniform_set: RID = UniformSetCacheRD.get_cache(_shader, 0, [color_uniform, depth_uniform, normal_uniform, ubo_uniform])

    var compute_list := _rd.compute_list_begin()
    _rd.compute_list_bind_compute_pipeline(compute_list, _pipeline)
    _rd.compute_list_bind_uniform_set(compute_list, uniform_set, 0)
    var groups_x := int((dispatch_w + 7) / 8)
    var groups_y := int((dispatch_h + 7) / 8)
    _rd.compute_list_dispatch(compute_list, groups_x, groups_y, 1)
    _rd.compute_list_end()

func _compile() -> bool:
    if not FileAccess.file_exists(SHADER_PATH):
        push_error("[RtPathTraceEffect] shader file missing: %s" % SHADER_PATH)
        return false
    var f := FileAccess.open(SHADER_PATH, FileAccess.READ)
    if f == null:
        push_error("[RtPathTraceEffect] cannot open shader: %s" % SHADER_PATH)
        return false
    var src_text := f.get_as_text()
    f.close()

    # Strip the Godot-specific "#[compute]" stage marker; RDShaderSource takes
    # raw GLSL and the stage is selected by setting source_compute.
    var glsl_src := src_text.replace("#[compute]", "")

    var src := RDShaderSource.new()
    src.source_compute = glsl_src
    src.language = RenderingDevice.SHADER_LANGUAGE_GLSL

    var spirv: RDShaderSPIRV = _rd.shader_compile_spirv_from_source(src)
    if spirv == null:
        push_error("[RtPathTraceEffect] shader compile returned null SPIR-V")
        return false
    var compute_err := spirv.compile_error_compute
    if compute_err != "":
        push_error("[RtPathTraceEffect] shader compile error:\n%s" % compute_err)
        return false

    _shader = _rd.shader_create_from_spirv(spirv)
    if not _shader.is_valid():
        push_error("[RtPathTraceEffect] shader_create_from_spirv returned invalid RID")
        return false
    _pipeline = _rd.compute_pipeline_create(_shader)
    if not _pipeline.is_valid():
        push_error("[RtPathTraceEffect] compute_pipeline_create returned invalid RID")
        return false

    var sstate := RDSamplerState.new()
    sstate.min_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
    sstate.mag_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
    sstate.repeat_u = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
    sstate.repeat_v = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
    sstate.repeat_w = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
    _sampler = _rd.sampler_create(sstate)

    _compiled = true
    return true

func _write_proj(buf: PackedByteArray, offset: int, p: Projection) -> void:
    var cols := [p.x, p.y, p.z, p.w]
    var idx := 0
    for c in cols:
        buf.encode_float(offset + idx * 4, c.x); idx += 1
        buf.encode_float(offset + idx * 4, c.y); idx += 1
        buf.encode_float(offset + idx * 4, c.z); idx += 1
        buf.encode_float(offset + idx * 4, c.w); idx += 1

func _notification(what: int) -> void:
    if what == NOTIFICATION_PREDELETE:
        if _rd:
            if _ubo.is_valid():
                _rd.free_rid(_ubo)
            if _sampler.is_valid():
                _rd.free_rid(_sampler)
            if _pipeline.is_valid():
                _rd.free_rid(_pipeline)
            if _shader.is_valid():
                _rd.free_rid(_shader)

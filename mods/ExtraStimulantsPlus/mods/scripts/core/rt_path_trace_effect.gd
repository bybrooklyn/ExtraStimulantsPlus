extends CompositorEffect
class_name RtPathTraceEffect

# Screen-space path tracer compositor effect.
# 4-pass pipeline:
#   1. trace      half-res, fires N rays per pixel, writes indirect_curr
#   2. temporal   reprojects + EMA-blends indirect_curr with prev history
#   3. atrous     edge-aware spatial denoise (N ping-pong iterations)
#   4. composite  full-res depth-aware bilateral upsample, additive into color

const TRACE_SHADER_REL := "shaders/pt_trace.glsl"
const TEMPORAL_SHADER_REL := "shaders/pt_temporal.glsl"
const ATROUS_SHADER_REL := "shaders/pt_atrous.glsl"
const COMPOSITE_SHADER_REL := "shaders/pt_composite.glsl"

var enabled: bool = false
var samples: int = 1
var max_steps: int = 24
var thickness: float = 0.25
var fade: float = 1.0

var sky_color: Color = Color(0.4, 0.5, 0.6)
var sky_intensity: float = 0.3
var temporal_alpha_max: int = 32
var atrous_iterations: int = 3

var _api: Node
var _meta: Dictionary

var _rd: RenderingDevice
var _sampler_nearest: RID
var _sampler_linear: RID

var _shader_trace: RID
var _shader_temporal: RID
var _shader_atrous: RID
var _shader_composite: RID

var _pipeline_trace: RID
var _pipeline_temporal: RID
var _pipeline_atrous: RID
var _pipeline_composite: RID

var _ubo_trace: RID
var _ubo_temporal: RID
var _ubo_atrous: RID
var _ubo_composite: RID

# Full-res
var _color_history: RID
var _color_history_size: Vector2i = Vector2i.ZERO

# Half-res
var _indirect_curr: RID
var _history_a: RID
var _history_b: RID
var _atrous_a: RID
var _atrous_b: RID
var _half_buf_size: Vector2i = Vector2i.ZERO

var _prev_view_proj: Projection
var _prev_view_proj_valid: bool = false
var _history_ping: int = 0
var _compiled: bool = false
var _compile_failed: bool = false
var _uniform_set_cache: Dictionary = {}

func _init() -> void:
    effect_callback_type = EFFECT_CALLBACK_TYPE_POST_TRANSPARENT
    access_resolved_color = true
    access_resolved_depth = true
    needs_normal_roughness = true

func configure(api: Node, meta: Dictionary) -> void:
    _api = api
    _meta = meta

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

    if not _compiled and not _compile_all():
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

    var half_size := Vector2i(max(1, (size.x + 1) / 2), max(1, (size.y + 1) / 2))
    _ensure_color_history(size)
    _ensure_half_buffers(half_size)
    if not _color_history.is_valid() or not _indirect_curr.is_valid():
        return

    var view_count: int = scene_buffers.get_view_count()
    for view in range(view_count):
        var color_tex: RID = scene_buffers.get_color_layer(view)
        var depth_tex: RID = scene_buffers.get_depth_layer(view)
        var normal_tex: RID = scene_buffers.get_texture("forward_clustered", "normal_roughness")
        if not color_tex.is_valid() or not depth_tex.is_valid() or not normal_tex.is_valid():
            continue

        # Snapshot the pre-pass color for hit lookups.
        _rd.texture_copy(color_tex, _color_history, Vector3.ZERO, Vector3.ZERO,
                         Vector3(size.x, size.y, 1), 0, 0, 0, 0)

        var view_proj: Projection = scene_data.get_view_projection(view)
        var inv_view_proj: Projection = view_proj.inverse()

        var history_prev := _history_a if _history_ping == 0 else _history_b
        var history_curr := _history_b if _history_ping == 0 else _history_a

        _dispatch_trace(depth_tex, normal_tex, size, half_size, view_proj, inv_view_proj)
        _dispatch_temporal(depth_tex, history_prev, history_curr, size, half_size, inv_view_proj)
        var denoised := _dispatch_atrous(history_curr, depth_tex, normal_tex, size, half_size)
        _dispatch_composite(denoised, depth_tex, color_tex, size, half_size)

        _prev_view_proj = view_proj
        _prev_view_proj_valid = true
        _history_ping = 1 - _history_ping

# --- Pass 1: trace ---------------------------------------------------------

func _dispatch_trace(depth_tex: RID, normal_tex: RID, size: Vector2i, half_size: Vector2i,
                     view_proj: Projection, inv_view_proj: Projection) -> void:
    var ubo := PackedByteArray()
    ubo.resize(192)
    _write_proj(ubo, 0, inv_view_proj)
    _write_proj(ubo, 64, view_proj)
    ubo.encode_s32(128, size.x)
    ubo.encode_s32(132, size.y)
    ubo.encode_s32(136, half_size.x)
    ubo.encode_s32(140, half_size.y)
    ubo.encode_s32(144, samples)
    ubo.encode_s32(148, max_steps)
    ubo.encode_float(152, thickness)
    ubo.encode_float(156, fade)
    ubo.encode_float(160, sky_color.r)
    ubo.encode_float(164, sky_color.g)
    ubo.encode_float(168, sky_color.b)
    ubo.encode_float(172, sky_intensity)
    ubo.encode_s32(176, int(Engine.get_frames_drawn()))
    _update_or_create_ubo(_ubo_trace.is_valid(), "trace", ubo)

    var u_depth := _sampler_uniform(0, _sampler_nearest, depth_tex)
    var u_normal := _sampler_uniform(1, _sampler_nearest, normal_tex)
    var u_history := _sampler_uniform(2, _sampler_nearest, _color_history)
    var u_out := _image_uniform(3, _indirect_curr)
    var u_ubo := _ubo_uniform(4, _ubo_trace)

    var uniform_set := _get_or_create_uniform_set(
        "trace",
        _shader_trace,
        [u_depth, u_normal, u_history, u_out, u_ubo],
        _uniform_key_from_ids([_shader_trace, _sampler_nearest, depth_tex, normal_tex, _color_history, _indirect_curr, _ubo_trace])
    )

    var compute_list := _rd.compute_list_begin()
    _rd.compute_list_bind_compute_pipeline(compute_list, _pipeline_trace)
    _rd.compute_list_bind_uniform_set(compute_list, uniform_set, 0)
    _rd.compute_list_dispatch(compute_list,
        int((half_size.x + 7) / 8), int((half_size.y + 7) / 8), 1)
    _rd.compute_list_end()

# --- Pass 2: temporal -----------------------------------------------------

func _dispatch_temporal(depth_tex: RID, history_prev: RID, history_curr: RID,
                        size: Vector2i, half_size: Vector2i, inv_view_proj: Projection) -> void:
    var ubo := PackedByteArray()
    ubo.resize(160)
    _write_proj(ubo, 0, inv_view_proj)
    var prev_vp: Projection = _prev_view_proj if _prev_view_proj_valid else Projection()
    _write_proj(ubo, 64, prev_vp)
    ubo.encode_s32(128, size.x)
    ubo.encode_s32(132, size.y)
    ubo.encode_s32(136, half_size.x)
    ubo.encode_s32(140, half_size.y)
    ubo.encode_s32(144, max(1, temporal_alpha_max))
    ubo.encode_s32(148, 0 if _prev_view_proj_valid else 1)
    ubo.encode_float(152, 0.05)  # depth_tol
    ubo.encode_float(156, 0.0)   # _pad0
    _update_or_create_ubo(_ubo_temporal.is_valid(), "temporal", ubo)

    var u_curr := _sampler_uniform(0, _sampler_linear, _indirect_curr)
    var u_hist := _sampler_uniform(1, _sampler_linear, history_prev)
    var u_depth := _sampler_uniform(2, _sampler_linear, depth_tex)
    var u_out := _image_uniform(3, history_curr)
    var u_ubo := _ubo_uniform(4, _ubo_temporal)

    var uniform_set := _get_or_create_uniform_set(
        "temporal",
        _shader_temporal,
        [u_curr, u_hist, u_depth, u_out, u_ubo],
        _uniform_key_from_ids([_shader_temporal, _sampler_linear, _sampler_nearest, _indirect_curr, history_prev, depth_tex, history_curr, _ubo_temporal])
    )

    var compute_list := _rd.compute_list_begin()
    _rd.compute_list_bind_compute_pipeline(compute_list, _pipeline_temporal)
    _rd.compute_list_bind_uniform_set(compute_list, uniform_set, 0)
    _rd.compute_list_dispatch(compute_list,
        int((half_size.x + 7) / 8), int((half_size.y + 7) / 8), 1)
    _rd.compute_list_end()

# --- Pass 3: atrous (N ping-pong iterations) ------------------------------

func _dispatch_atrous(input_tex: RID, depth_tex: RID, normal_tex: RID,
                      size: Vector2i, half_size: Vector2i) -> RID:
    var iters := clampi(atrous_iterations, 0, 5)
    if iters == 0:
        return input_tex

    var src := input_tex
    var dst: RID
    for i in range(iters):
        var step_size := 1 << i  # 1, 2, 4, 8, 16
        dst = _atrous_a if (i % 2 == 0) else _atrous_b

        var ubo := PackedByteArray()
        ubo.resize(32)
        ubo.encode_s32(0, size.x)
        ubo.encode_s32(4, size.y)
        ubo.encode_s32(8, half_size.x)
        ubo.encode_s32(12, half_size.y)
        ubo.encode_s32(16, step_size)
        ubo.encode_float(20, 0.02)  # sigma_z
        ubo.encode_float(24, 32.0)  # sigma_n exponent
        ubo.encode_s32(28, 0)
        _update_or_create_ubo(_ubo_atrous.is_valid(), "atrous", ubo)

        var u_in := _sampler_uniform(0, _sampler_nearest, src)
        var u_depth := _sampler_uniform(1, _sampler_nearest, depth_tex)
        var u_normal := _sampler_uniform(2, _sampler_nearest, normal_tex)
        var u_out := _image_uniform(3, dst)
        var u_ubo := _ubo_uniform(4, _ubo_atrous)

        var uniform_set := _get_or_create_uniform_set(
            "atrous",
            _shader_atrous,
            [u_in, u_depth, u_normal, u_out, u_ubo],
            _uniform_key_from_ids([_shader_atrous, _sampler_nearest, src, depth_tex, normal_tex, dst, _ubo_atrous])
        )

        var compute_list := _rd.compute_list_begin()
        _rd.compute_list_bind_compute_pipeline(compute_list, _pipeline_atrous)
        _rd.compute_list_bind_uniform_set(compute_list, uniform_set, 0)
        _rd.compute_list_dispatch(compute_list,
            int((half_size.x + 7) / 8), int((half_size.y + 7) / 8), 1)
        _rd.compute_list_end()

        src = dst
    return src

# --- Pass 4: composite -----------------------------------------------------

func _dispatch_composite(indirect_tex: RID, depth_tex: RID, color_tex: RID,
                         size: Vector2i, half_size: Vector2i) -> void:
    var ubo := PackedByteArray()
    ubo.resize(32)
    ubo.encode_s32(0, size.x)
    ubo.encode_s32(4, size.y)
    ubo.encode_s32(8, half_size.x)
    ubo.encode_s32(12, half_size.y)
    ubo.encode_float(16, 0.05)  # depth_sigma
    ubo.encode_float(20, 1.0)   # intensity (final mul; fade already applied in trace)
    ubo.encode_s32(24, 0)
    ubo.encode_s32(28, 0)
    _update_or_create_ubo(_ubo_composite.is_valid(), "composite", ubo)

    var u_indirect := _sampler_uniform(0, _sampler_linear, indirect_tex)
    var u_depth := _sampler_uniform(1, _sampler_nearest, depth_tex)
    var u_color := _image_uniform(2, color_tex)
    var u_ubo := _ubo_uniform(3, _ubo_composite)

    var uniform_set := _get_or_create_uniform_set(
        "composite",
        _shader_composite,
        [u_indirect, u_depth, u_color, u_ubo],
        _uniform_key_from_ids([_shader_composite, _sampler_linear, _sampler_nearest, indirect_tex, depth_tex, color_tex, _ubo_composite])
    )

    var compute_list := _rd.compute_list_begin()
    _rd.compute_list_bind_compute_pipeline(compute_list, _pipeline_composite)
    _rd.compute_list_bind_uniform_set(compute_list, uniform_set, 0)
    _rd.compute_list_dispatch(compute_list,
        int((size.x + 7) / 8), int((size.y + 7) / 8), 1)
    _rd.compute_list_end()

# --- Compilation -----------------------------------------------------------

func _compile_all() -> bool:
    if not _compile_one(TRACE_SHADER_REL, "trace"): return false
    if not _compile_one(TEMPORAL_SHADER_REL, "temporal"): return false
    if not _compile_one(ATROUS_SHADER_REL, "atrous"): return false
    if not _compile_one(COMPOSITE_SHADER_REL, "composite"): return false

    var nearest := RDSamplerState.new()
    nearest.min_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
    nearest.mag_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
    nearest.repeat_u = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
    nearest.repeat_v = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
    nearest.repeat_w = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
    _sampler_nearest = _rd.sampler_create(nearest)

    var linear := RDSamplerState.new()
    linear.min_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
    linear.mag_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
    linear.repeat_u = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
    linear.repeat_v = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
    linear.repeat_w = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
    _sampler_linear = _rd.sampler_create(linear)

    _compiled = true
    return true

func _compile_one(rel_path: String, label: String) -> bool:
    var src_text := ""
    if _api and _api.assets and not _meta.is_empty():
        src_text = _api.assets.load_text(_meta, rel_path)
    if src_text.is_empty():
        var fallback := "res://mods/esp_features/" + rel_path
        if FileAccess.file_exists(fallback):
            var f := FileAccess.open(fallback, FileAccess.READ)
            if f != null:
                src_text = f.get_as_text()
                f.close()
    if src_text.is_empty():
        push_error("[RtPathTraceEffect] shader source missing: %s" % rel_path)
        return false

    var glsl := src_text.replace("#[compute]", "")
    var src := RDShaderSource.new()
    src.source_compute = glsl
    src.language = RenderingDevice.SHADER_LANGUAGE_GLSL

    var spirv: RDShaderSPIRV = _rd.shader_compile_spirv_from_source(src)
    if spirv == null or spirv.compile_error_compute != "":
        push_error("[RtPathTraceEffect] %s compile error:\n%s"
            % [label, spirv.compile_error_compute if spirv else "<null>"])
        return false

    var shader_rid: RID = _rd.shader_create_from_spirv(spirv)
    if not shader_rid.is_valid():
        push_error("[RtPathTraceEffect] %s shader_create returned invalid RID" % label)
        return false
    var pipeline_rid: RID = _rd.compute_pipeline_create(shader_rid)
    if not pipeline_rid.is_valid():
        push_error("[RtPathTraceEffect] %s compute_pipeline_create failed" % label)
        return false

    match label:
        "trace":
            _shader_trace = shader_rid
            _pipeline_trace = pipeline_rid
        "temporal":
            _shader_temporal = shader_rid
            _pipeline_temporal = pipeline_rid
        "atrous":
            _shader_atrous = shader_rid
            _pipeline_atrous = pipeline_rid
        "composite":
            _shader_composite = shader_rid
            _pipeline_composite = pipeline_rid
    return true

# --- Buffer lifecycle ------------------------------------------------------

func _ensure_color_history(size: Vector2i) -> void:
    if _color_history.is_valid() and _color_history_size == size:
        return
    _clear_uniform_set_cache()
    if _color_history.is_valid():
        _rd.free_rid(_color_history)
        _color_history = RID()
    _color_history = _make_rgba16f(size, true)
    if _color_history.is_valid():
        _color_history_size = size

func _ensure_half_buffers(half_size: Vector2i) -> void:
    if _half_buf_size == half_size and _indirect_curr.is_valid():
        return
    _free_half_buffers()
    _indirect_curr = _make_rgba16f(half_size, false)
    _history_a = _make_rgba16f(half_size, false)
    _history_b = _make_rgba16f(half_size, false)
    _atrous_a = _make_rgba16f(half_size, false)
    _atrous_b = _make_rgba16f(half_size, false)
    _half_buf_size = half_size
    _prev_view_proj_valid = false  # disocclude on resize

func _free_half_buffers() -> void:
    _clear_uniform_set_cache()
    for r in [_indirect_curr, _history_a, _history_b, _atrous_a, _atrous_b]:
        if r.is_valid():
            _rd.free_rid(r)
    _indirect_curr = RID()
    _history_a = RID()
    _history_b = RID()
    _atrous_a = RID()
    _atrous_b = RID()
    _half_buf_size = Vector2i.ZERO

func _make_rgba16f(size: Vector2i, copy_target: bool) -> RID:
    var fmt := RDTextureFormat.new()
    fmt.format = RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT
    fmt.width = size.x
    fmt.height = size.y
    fmt.depth = 1
    fmt.array_layers = 1
    fmt.mipmaps = 1
    fmt.texture_type = RenderingDevice.TEXTURE_TYPE_2D
    var bits := (
        RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
        | RenderingDevice.TEXTURE_USAGE_STORAGE_BIT
    )
    if copy_target:
        bits |= RenderingDevice.TEXTURE_USAGE_COPY_TO_BIT
        bits |= RenderingDevice.TEXTURE_USAGE_CAN_COPY_TO_BIT
    fmt.usage_bits = bits
    return _rd.texture_create(fmt, RDTextureView.new(), [])

# --- Uniform helpers -------------------------------------------------------

func _sampler_uniform(binding: int, sampler: RID, tex: RID) -> RDUniform:
    var u := RDUniform.new()
    u.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
    u.binding = binding
    u.add_id(sampler)
    u.add_id(tex)
    return u

func _image_uniform(binding: int, tex: RID) -> RDUniform:
    var u := RDUniform.new()
    u.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
    u.binding = binding
    u.add_id(tex)
    return u

func _ubo_uniform(binding: int, ubo: RID) -> RDUniform:
    var u := RDUniform.new()
    u.uniform_type = RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER
    u.binding = binding
    u.add_id(ubo)
    return u

func _get_or_create_uniform_set(label: String, shader: RID, uniforms: Array, key: String) -> RID:
    var cache: Dictionary = _uniform_set_cache.get(label, {})
    if cache.has(key):
        var cached: RID = cache.get(key, RID())
        if cached.is_valid():
            return cached

    var rid := _rd.uniform_set_create(uniforms, shader, 0)
    cache[key] = rid
    _uniform_set_cache[label] = cache
    return rid

func _uniform_key_from_ids(ids: Array) -> String:
    var parts: Array[String] = []
    for id_value in ids:
        parts.append(str(id_value))
    return "|".join(parts)

func _clear_uniform_set_cache() -> void:
    for cache in _uniform_set_cache.values():
        if not (cache is Dictionary):
            continue
        for rid in cache.values():
            if rid is RID and rid.is_valid():
                _rd.free_rid(rid)
    _uniform_set_cache.clear()

func _update_or_create_ubo(_exists: bool, label: String, bytes: PackedByteArray) -> void:
    var rid: RID
    match label:
        "trace": rid = _ubo_trace
        "temporal": rid = _ubo_temporal
        "atrous": rid = _ubo_atrous
        "composite": rid = _ubo_composite
    if rid.is_valid():
        _rd.buffer_update(rid, 0, bytes.size(), bytes)
        return
    rid = _rd.uniform_buffer_create(bytes.size(), bytes)
    match label:
        "trace": _ubo_trace = rid
        "temporal": _ubo_temporal = rid
        "atrous": _ubo_atrous = rid
        "composite": _ubo_composite = rid

func _write_proj(buf: PackedByteArray, offset: int, p: Projection) -> void:
    var cols := [p.x, p.y, p.z, p.w]
    var idx := 0
    for c in cols:
        buf.encode_float(offset + idx * 4, c.x); idx += 1
        buf.encode_float(offset + idx * 4, c.y); idx += 1
        buf.encode_float(offset + idx * 4, c.z); idx += 1
        buf.encode_float(offset + idx * 4, c.w); idx += 1

func _notification(what: int) -> void:
    if what == NOTIFICATION_PREDELETE and _rd:
        cleanup()


# Frees every owned RD resource and resets compile state so the next render
# call re-creates them. Safe to call multiple times. Used both on
# NOTIFICATION_PREDELETE and from rt_effects.gd::_detach() when the user
# disables RT — without this, GPU memory stays held even though we stopped
# rendering with it.
func cleanup() -> void:
    if _rd == null:
        return
    _clear_uniform_set_cache()
    _free_half_buffers()
    var rids: Array[RID] = [
        _color_history,
        _ubo_trace, _ubo_temporal, _ubo_atrous, _ubo_composite,
        _sampler_nearest, _sampler_linear,
        _pipeline_trace, _pipeline_temporal, _pipeline_atrous, _pipeline_composite,
        _shader_trace, _shader_temporal, _shader_atrous, _shader_composite,
    ]
    for r in rids:
        if r.is_valid():
            _rd.free_rid(r)
    # Reset all RID handles to invalid so re-entry creates fresh resources.
    _color_history = RID()
    _ubo_trace = RID(); _ubo_temporal = RID(); _ubo_atrous = RID(); _ubo_composite = RID()
    _sampler_nearest = RID(); _sampler_linear = RID()
    _pipeline_trace = RID(); _pipeline_temporal = RID()
    _pipeline_atrous = RID(); _pipeline_composite = RID()
    _shader_trace = RID(); _shader_temporal = RID()
    _shader_atrous = RID(); _shader_composite = RID()
    _compiled = false

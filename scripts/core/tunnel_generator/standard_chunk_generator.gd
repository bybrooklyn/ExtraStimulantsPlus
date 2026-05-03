class_name StandardChunkGenerator
extends ChunkGenerator










func get_lane_info(_local_y: float, config: Resource) -> Array[LaneInfo]:
    var r = config.base_radius * config.cube_size
    return [LaneInfo.new(Vector3.ZERO, r, 0)]

func generate_chunk(index: int, config: Resource, mesh: Mesh, material: ShaderMaterial, strip_materials: Array = [], theme: Resource = null) -> Node3D:
    var chunk = Node3D.new()
    chunk.name = "Chunk_%d" % index

    var rings_per_chunk = config.chunk_length
    var radius = config.base_radius * config.cube_size


    var circumference = 2.0 * PI * radius
    var cubes_per_ring: int = int(ceil((circumference / config.cube_size) * 1.1))

    var num_instances = rings_per_chunk * cubes_per_ring

    var angle_step = TAU / float(cubes_per_ring)
    var ring_spacing = config.ring_spacing

    var neon_budget: int = 999999
    var lights_in_chunk: int = 0
    if RenderingQualityManager:
        neon_budget = NeonLightBudget.get_max_neon_lights(RenderingQualityManager.get_preset() as int)



    var light_slot_x: float = round(config.base_radius) * config.cube_size

    var mm = MultiMeshInstance3D.new()
    var m = MultiMesh.new()
    m.transform_format = MultiMesh.TRANSFORM_3D
    m.use_colors = false
    m.use_custom_data = true
    m.mesh = mesh
    m.instance_count = num_instances

    var idx = 0
    for r in range(rings_per_chunk):

        var local_y = - float(r) * ring_spacing


        var absolute_ring_index = (index * config.chunk_length) + r

        var ring_has_light: bool = absolute_ring_index % 30 == 0 and lights_in_chunk + 2 <= neon_budget

        for c in range(cubes_per_ring):
            var angle = c * angle_step
            var raw_x = config.base_radius * cos(angle)
            var raw_z = config.base_radius * sin(angle)


            var x = round(raw_x) * config.cube_size
            var z = round(raw_z) * config.cube_size


            if ring_has_light and z == 0.0 and absf(x) == light_slot_x:
                continue

            var cube_angle_deg = rad_to_deg(angle)
            m.set_instance_transform(idx, Transform3D(Basis(), Vector3(x, local_y, z)))
            m.set_instance_custom_data(idx, Color(cube_angle_deg, float(absolute_ring_index), float(x), float(z)))
            idx += 1


        if ring_has_light:
            _add_light_ring(chunk, local_y, absolute_ring_index, config, radius)
            lights_in_chunk += 2
    m.instance_count = idx

    mm.multimesh = m
    mm.material_override = material



    mm.extra_cull_margin = 120.0

    mm.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
    mm.add_to_group("TunnelMultiMesh")
    chunk.add_child(mm)





    return chunk

func _add_light_ring(parent: Node, local_y: float, ring_idx: int, config: Resource, radius: float):
    for angle_deg in [0, 180]:
        var angle = deg_to_rad(angle_deg)

        var light_radius = radius
        var lx = light_radius * cos(angle)
        var lz = light_radius * sin(angle)

        var light = OmniLight3D.new()
        light.position = Vector3(lx, local_y, lz)


        light.omni_range = 41.58
        light.light_energy = 4.5
        light.light_color = Color(1.0, 0.95, 0.9)

        light.shadow_enabled = true
        light.shadow_bias = 0.02
        light.distance_fade_enabled = true
        light.distance_fade_shadow = 20.0
        light.distance_fade_begin = 140.0
        light.distance_fade_length = 30.0

        light.light_cull_mask &= ~ (1 << 1)


        light.set_meta("base_pos", light.position)
        light.set_meta("ring_index", ring_idx)

        light.add_to_group("ShadowLights")
        parent.add_child(light)


        var mesh_inst = MeshInstance3D.new()
        mesh_inst.mesh = BoxMesh.new()
        mesh_inst.mesh.size = Vector3(1, 1, 1) * config.cube_size
        var mat = StandardMaterial3D.new()
        mat.emission_enabled = true
        mat.emission = light.light_color
        mat.emission_energy = 5.0
        mesh_inst.material_override = mat
        mesh_inst.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
        light.add_child(mesh_inst)

class_name ObstacleInstance
extends Node3D

var base_y: float = 0.0
var passed: bool = false

var _loop_flags: int = -1
var base_rot_speed: float = 0.0
var current_rot_val: float = 0.0
var oscillate: bool = false
var oscillate_amplitude: float = PI * 0.5
var oscillate_phase: float = 0.0

var animation_type: String = ""
var animation_speed: float = 40.0
var animation_phase: float = 0.0
var slide_amplitude: float = 8.0
var slide_axis: int = 1 # 0: x, 1: z
var slide_position_offset: float = 0.0

var pulse_enabled: bool = false
var pulse_axis: int = 0
var pulse_speed: float = 1.0
var pulse_amplitude: float = 0.0
var pulse_phase: float = 0.0
var pulse_time: float = 0.0

var random_orientation: bool = false
var gap_angle_deg: float = 0.0
var gap_width_world: float = 5.0
var obstacle_type_id: String = ""

var swap_enabled: bool = false
var swap_cycle: PackedStringArray = []
var swap_variant_count: int = 1
var swap_variant_gap_meta: Array = []
var swap_period_sec: float = 0.0
var swap_phase_sec: float = 0.0
var swap_time: float = 0.0
var swap_active_index: int = -1
var swap_targets: PackedStringArray = []
var swap_host_type_id: String = ""
var _swap_flashing: bool = false
var _swap_preview_idx: int = -1

var pool_type_id: String = ""
var pool_last_color: Color = Color.BLACK

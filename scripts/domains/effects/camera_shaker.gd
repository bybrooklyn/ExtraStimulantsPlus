extends Node















var trauma: float = 0.0



var offset: Vector2 = Vector2.ZERO




var decay_rate: float = 1.8


var max_offset: Vector2 = Vector2(0.08, 0.08)


var noise_speed: float = 30.0


var _noise: FastNoiseLite
var _noise_y: float = 0.0


func _ready() -> void :
    _noise = FastNoiseLite.new()
    _noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
    _noise.seed = randi()
    _noise.frequency = 2.0
    _noise.fractal_octaves = 2
    _noise.fractal_lacunarity = 2.0
    _noise.fractal_gain = 0.5


func add_trauma(amount: float) -> void :
    trauma = minf(trauma + amount, 1.0)


func _process(delta: float) -> void :

    trauma = move_toward(trauma, 0.0, decay_rate * delta)


    if trauma <= 0.001:
        offset = Vector2.ZERO
        return


    var shake_amount: float = trauma * trauma


    _noise_y += delta * noise_speed


    offset.x = _noise.get_noise_2d(1.0, _noise_y) * max_offset.x * shake_amount
    offset.y = _noise.get_noise_2d(100.0, _noise_y) * max_offset.y * shake_amount

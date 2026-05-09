extends Node

# AudioVisualizer handles real-time spectrum analysis of the "Music" bus.
# It provides smoothed frequency band data for reactive effects.

const MOD_ID := "esp_features"
const NUM_BANDS = 16
const BANDS = [
    60, 125, 250, 400, 600, 800, 1200, 1800,
    3000, 5000, 7000, 9000, 11000, 13000, 16000, 20000
]

var _api: Node
var _meta: Dictionary

var _spectrum_analyzer: AudioEffectSpectrumAnalyzerInstance
var _freq_bands: Array[float] = []
var _smoothed_freq_bands: Array[float] = []
var _level_active: bool = false
# Track whether *we* installed the analyzer (vs reusing one the game put there).
# Without this, toggling the visualizer off would either leave our analyzer
# orphaned on the bus (leak) or remove the game's own analyzer (regression).
var _analyzer_owned: bool = false
var _analyzer_bus_idx: int = -1

func configure(api: Node, meta: Dictionary) -> void:
    _api = api
    _meta = meta

func _ready():
    if _api == null:
        _api = get_node_or_null("/root/ESP")

    _freq_bands.resize(NUM_BANDS)
    _smoothed_freq_bands.resize(NUM_BANDS)
    _freq_bands.fill(0.0)
    _smoothed_freq_bands.fill(0.0)
    _setup_analyzer()

    if _api and _api.events:
        _api.events.on("level_started", Callable(self, "_on_level_started"), {"owner_id": MOD_ID})
        _api.events.on("level_completed", Callable(self, "_on_level_finished"), {"owner_id": MOD_ID})
        _api.events.on("player_died", Callable(self, "_on_level_finished"), {"owner_id": MOD_ID})

func _on_level_started(_a = null, _b = null) -> void:
    _level_active = true

func _on_level_finished(_a = null, _b = null) -> void:
    _level_active = false

func _process(delta):
    if not _get_bool("audio.visualizer.enabled", true):
        return
    if not _level_active:
        return
    if not _spectrum_analyzer:
        _setup_analyzer()
        return

    var smoothing := clampf(_get_float("audio.visualizer.smoothing", 0.5), 0.0, 1.0)
    # Map 0..1 smoothing into existing attack/decay lerp speeds.
    var attack_speed := lerp(40.0, 4.0, smoothing)
    var decay_speed := lerp(12.0, 1.0, smoothing)

    var prev_hz = 20
    for i in range(NUM_BANDS):
        var hz = BANDS[i]
        var magnitude: float = _spectrum_analyzer.get_magnitude_for_frequency_range(prev_hz, hz).length()
        var energy = clampf(magnitude * 70.0, 0.0, 1.0)

        _freq_bands[i] = energy
        var lerp_val = attack_speed if energy > _smoothed_freq_bands[i] else decay_speed
        _smoothed_freq_bands[i] = lerp(_smoothed_freq_bands[i], energy, lerp_val * delta)

        prev_hz = hz

    var gain := clampf(_get_float("audio.visualizer.gain", 1.0), 0.0, 4.0)
    RenderingServer.global_shader_parameter_set("mod_music_pulse", get_bass_pulse() * gain)

func _setup_analyzer():
    var bus_idx = AudioServer.get_bus_index("Music")
    if bus_idx < 0: return

    var effect_idx = -1
    for i in range(AudioServer.get_bus_effect_count(bus_idx)):
        if AudioServer.get_bus_effect(bus_idx, i) is AudioEffectSpectrumAnalyzer:
            effect_idx = i
            break

    if effect_idx == -1:
        var analyzer = AudioEffectSpectrumAnalyzer.new()
        analyzer.resource_name = "SpectrumAnalyzer"
        AudioServer.add_bus_effect(bus_idx, analyzer)
        effect_idx = AudioServer.get_bus_effect_count(bus_idx) - 1
        _analyzer_owned = true
        _analyzer_bus_idx = bus_idx

    _spectrum_analyzer = AudioServer.get_bus_effect_instance(bus_idx, effect_idx)


func _teardown_analyzer():
    # Remove the SpectrumAnalyzer only if we installed it; never touch one the
    # game added itself.
    if not _analyzer_owned or _analyzer_bus_idx < 0:
        _spectrum_analyzer = null
        return
    if _analyzer_bus_idx >= AudioServer.bus_count:
        _spectrum_analyzer = null
        _analyzer_owned = false
        _analyzer_bus_idx = -1
        return
    for i in range(AudioServer.get_bus_effect_count(_analyzer_bus_idx) - 1, -1, -1):
        if AudioServer.get_bus_effect(_analyzer_bus_idx, i) is AudioEffectSpectrumAnalyzer:
            AudioServer.remove_bus_effect(_analyzer_bus_idx, i)
            break
    _spectrum_analyzer = null
    _analyzer_owned = false
    _analyzer_bus_idx = -1


func _exit_tree() -> void:
    _teardown_analyzer()

func get_band_intensity(index: int) -> float:
    if index < 0 or index >= NUM_BANDS: return 0.0
    return _smoothed_freq_bands[index]

func get_bass_pulse() -> float:
    return (_smoothed_freq_bands[0] * 0.5 + _smoothed_freq_bands[1] * 0.3 + _smoothed_freq_bands[2] * 0.2)

func _get_bool(key: String, fallback: bool) -> bool:
    if _api == null or _api.settings == null:
        return fallback
    var v = _api.settings.get(MOD_ID, key, fallback)
    return bool(v) if v != null else fallback

func _get_float(key: String, fallback: float) -> float:
    if _api == null or _api.settings == null:
        return fallback
    var v = _api.settings.get(MOD_ID, key, fallback)
    return float(v) if v != null else fallback

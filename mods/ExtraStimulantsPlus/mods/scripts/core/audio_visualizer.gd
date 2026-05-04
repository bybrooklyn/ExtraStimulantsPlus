extends Node

# AudioVisualizer handles real-time spectrum analysis of the "Music" bus.
# It provides smoothed frequency band data for reactive effects.

var _spectrum_analyzer: AudioEffectSpectrumAnalyzerInstance
var _freq_bands: Array[float] = []
var _smoothed_freq_bands: Array[float] = []

const NUM_BANDS = 16
const BANDS = [
    60, 125, 250, 400, 600, 800, 1200, 1800,
    3000, 5000, 7000, 9000, 11000, 13000, 16000, 20000
]

func _ready():
    _freq_bands.resize(NUM_BANDS)
    _smoothed_freq_bands.resize(NUM_BANDS)
    _freq_bands.fill(0.0)
    _smoothed_freq_bands.fill(0.0)
    _setup_analyzer()

func _process(delta):
    if not _spectrum_analyzer:
        _setup_analyzer()
        return
        
    var prev_hz = 20
    for i in range(NUM_BANDS):
        var hz = BANDS[i]
        var magnitude: float = _spectrum_analyzer.get_magnitude_for_frequency_range(prev_hz, hz).length()
        
        # Scale magnitude for normalized 0.0-1.0 range
        var energy = clampf(magnitude * 70.0, 0.0, 1.0)
        
        _freq_bands[i] = energy
        
        # Smoother lerp for decay than for attack
        var lerp_val = 20.0 if energy > _smoothed_freq_bands[i] else 6.0
        _smoothed_freq_bands[i] = lerp(_smoothed_freq_bands[i], energy, lerp_val * delta)
        
        prev_hz = hz
    
    # Update Shader Global
    var settings = get_node_or_null("/root/ExtraStimulantsPlusSettings")
    var intensity = settings.get_reactivity_intensity() if settings else 1.0
    RenderingServer.global_shader_parameter_set("mod_music_pulse", get_bass_pulse() * intensity)

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
        
    _spectrum_analyzer = AudioServer.get_bus_effect_instance(bus_idx, effect_idx)

func get_band_intensity(index: int) -> float:
    if index < 0 or index >= NUM_BANDS: return 0.0
    return _smoothed_freq_bands[index]

func get_bass_pulse() -> float:
    # Bass is typically bands 0-2 (20Hz - 250Hz)
    return (_smoothed_freq_bands[0] * 0.5 + _smoothed_freq_bands[1] * 0.3 + _smoothed_freq_bands[2] * 0.2)

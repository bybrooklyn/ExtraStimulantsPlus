extends Node

static func load_external_audio(path: String) -> AudioStream:
    if not FileAccess.file_exists(path):
        push_error("ExternalAudioLoader: File not found: " + path)
        return null
        
    var ext = path.get_extension().to_lower()
    match ext:
        "ogg":
            return AudioStreamOggVorbis.load_from_file(path)
        "mp3":
            var stream = AudioStreamMP3.new()
            stream.data = FileAccess.get_file_as_bytes(path)
            return stream
        "wav":
            # Very basic WAV loading (might not work for all wav types)
            var file = FileAccess.open(path, FileAccess.READ)
            if not file: return null
            
            var bytes = file.get_buffer(file.get_length())
            file.close()
            
            var stream = AudioStreamWAV.new()
            # WAV header is 44 bytes typically.
            # This is a hack and might not work if the WAV isn't 44.1khz 16bit stereo
            stream.data = bytes.slice(44)
            stream.format = AudioStreamWAV.FORMAT_16_BITS
            stream.mix_rate = 44100
            stream.stereo = true
            return stream
            
    return null

static func get_custom_music_list() -> Array[String]:
    var result: Array[String] = []
    var dir = DirAccess.open("user://")
    if dir:
        if not dir.dir_exists("custom_music"):
            dir.make_dir("custom_music")
            
        var music_dir = DirAccess.open("user://custom_music")
        if music_dir:
            music_dir.list_dir_begin()
            var file_name = music_dir.get_next()
            while file_name != "":
                if not music_dir.current_is_dir() and (file_name.ends_with(".ogg") or file_name.ends_with(".mp3") or file_name.ends_with(".wav")):
                    result.append("user://custom_music/" + file_name)
                file_name = music_dir.get_next()
            music_dir.list_dir_end()
    return result

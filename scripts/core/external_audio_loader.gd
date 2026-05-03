extends Node

static func load_external_audio(path: String) -> AudioStream:
    if not FileAccess.file_exists(path):
        push_error("ExternalAudioLoader: File not found: " + path)
        return null
        
    var ext = path.get_extension().to_lower()
    match ext:
        "ogg", "vorbis", "oga":
            # AudioStreamOggVorbis.load_from_file was added in Godot 4.3
            if "load_from_file" in AudioStreamOggVorbis:
                return AudioStreamOggVorbis.load_from_file(path)
            else:
                # Fallback for Godot 4.0 - 4.2
                var file = FileAccess.open(path, FileAccess.READ)
                if not file: return null
                var buffer = file.get_buffer(file.get_length())
                file.close()
                return AudioStreamOggVorbis.load_from_buffer(buffer)
        "mp3":
            var stream = AudioStreamMP3.new()
            stream.data = FileAccess.get_file_as_bytes(path)
            return stream
        "wav":
            var file = FileAccess.open(path, FileAccess.READ)
            if not file: return null
            
            # RIFF Header
            var riff_tag = file.get_buffer(4).get_string_from_ascii()
            if riff_tag != "RIFF":
                push_error("ExternalAudioLoader: Invalid WAV (missing RIFF)")
                return null
            
            file.get_32() # Skip file size
            
            var wave_tag = file.get_buffer(4).get_string_from_ascii()
            if wave_tag != "WAVE":
                push_error("ExternalAudioLoader: Invalid WAV (missing WAVE)")
                return null
            
            var stream = AudioStreamWAV.new()
            var data_found = false
            
            while file.get_position() < file.get_length():
                var chunk_id = file.get_buffer(4).get_string_from_ascii()
                var chunk_size = file.get_32()
                var next_chunk_pos = file.get_position() + chunk_size
                
                if chunk_id == "fmt ":
                    var compression_code = file.get_16()
                    var channels = file.get_16()
                    var sample_rate = file.get_32()
                    file.get_32() # byte_rate
                    file.get_16() # block_align
                    var bits_per_sample = file.get_16()
                    
                    stream.stereo = (channels >= 2)
                    stream.mix_rate = sample_rate
                    
                    if bits_per_sample == 8:
                        stream.format = AudioStreamWAV.FORMAT_8_BITS
                    elif bits_per_sample == 16:
                        stream.format = AudioStreamWAV.FORMAT_16_BITS
                    else:
                        # Fallback to 16-bit if unknown, though might sound like noise
                        stream.format = AudioStreamWAV.FORMAT_16_BITS
                
                elif chunk_id == "data":
                    stream.data = file.get_buffer(chunk_size)
                    data_found = true
                    # We found the data, can stop or continue if there are loops (smpl chunk)
                
                file.seek(next_chunk_pos)
                if data_found: break
            
            file.close()
            return stream if data_found else null
            
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
                var f_ext = file_name.get_extension().to_lower()
                if not music_dir.current_is_dir() and f_ext in ["ogg", "vorbis", "oga", "mp3", "wav"]:
                    result.append("user://custom_music/" + file_name)
                file_name = music_dir.get_next()
            music_dir.list_dir_end()
    return result

extends Node




var steam_available: bool = false


func _steam() -> Object:
    return Engine.get_singleton("Steam") if Engine.has_singleton("Steam") else null


func file_exists_cloud(filename: String) -> bool:
    var steam: Object = _steam()
    if not steam_available or steam == null:
        return false
    if not steam.has_method("fileExists"):
        return false
    return steam.fileExists(filename)


func file_write_cloud(filename: String, data: PackedByteArray) -> bool:
    var steam: Object = _steam()
    if not steam_available or steam == null:
        return false
    if not steam.has_method("fileWrite"):
        return false
    var byte_count: int = data.size()
    return steam.fileWrite(filename, data, byte_count)


func file_read_cloud(filename: String) -> PackedByteArray:
    var empty: PackedByteArray = PackedByteArray()
    var steam: Object = _steam()
    if not steam_available or steam == null:
        return empty
    if not steam.has_method("getFileSize") or not steam.has_method("fileRead"):
        return empty
    var file_size: int = steam.getFileSize(filename)
    if file_size <= 0:
        return empty
    var result = steam.fileRead(filename, file_size)
    if result is Dictionary and result.has("buf"):
        var buf = result["buf"]
        if buf is PackedByteArray:
            return buf
    return empty

extends Node

const LOG_DIR := "user://esp/logs"
const LATEST_LOG := "user://esp/logs/latest.log"
const PREVIOUS_LOG := "user://esp/logs/previous.log"

var mirror_to_console := true


func _enter_tree() -> void:
    _prepare_log_file()
    info("logger ready")


func info(message: String) -> void:
    _write("INFO", message)


func warn(message: String) -> void:
    _write("WARN", message)
    push_warning("[ESP] " + message)


func error(message: String) -> void:
    _write("ERROR", message)
    push_error("[ESP] " + message)


func _prepare_log_file() -> void:
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(LOG_DIR))
    if FileAccess.file_exists(LATEST_LOG):
        var latest := FileAccess.open(LATEST_LOG, FileAccess.READ)
        var previous := FileAccess.open(PREVIOUS_LOG, FileAccess.WRITE)
        if latest and previous:
            previous.store_string(latest.get_as_text())
        if latest:
            latest.close()
        if previous:
            previous.close()
    var file := FileAccess.open(LATEST_LOG, FileAccess.WRITE)
    if file:
        file.store_line("ExtraStimulantsPlus log start")
        file.close()


func _write(level: String, message: String) -> void:
    var line := "[%s] %s" % [level, message]
    if mirror_to_console:
        print("[ESP] ", line)
    var file := FileAccess.open(LATEST_LOG, FileAccess.READ_WRITE)
    if file:
        file.seek_end()
        file.store_line(line)
        file.close()

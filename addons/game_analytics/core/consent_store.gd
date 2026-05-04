extends RefCounted
class_name GameAnalyticsConsentStore

const PATH:= "user://game_analytics_privacy.cfg"
const SECTION:= "privacy"

var analytics_consented: bool = false
var consent_prompt_completed: bool = false
var session_id: String = ""

var install_id: String = ""
var last_session_end_timestamp: String = ""
var total_sessions: int = 0

func load_from_disk() -> void :
    var cfg:= ConfigFile.new()
    if cfg.load(PATH) != OK:
        return
    analytics_consented = cfg.get_value(SECTION, "analytics_consented", false)
    consent_prompt_completed = cfg.get_value(SECTION, "consent_prompt_completed", false)
    session_id = str(cfg.get_value(SECTION, "session_id", ""))
    install_id = str(cfg.get_value(SECTION, "install_id", ""))
    last_session_end_timestamp = str(cfg.get_value(SECTION, "last_session_end_timestamp", ""))
    total_sessions = int(cfg.get_value(SECTION, "total_sessions", 0))

func save_to_disk() -> void :
    var cfg:= ConfigFile.new()
    cfg.load(PATH)
    cfg.set_value(SECTION, "analytics_consented", analytics_consented)
    cfg.set_value(SECTION, "consent_prompt_completed", consent_prompt_completed)
    cfg.set_value(SECTION, "session_id", session_id)
    cfg.set_value(SECTION, "install_id", install_id)
    cfg.set_value(SECTION, "last_session_end_timestamp", last_session_end_timestamp)
    cfg.set_value(SECTION, "total_sessions", total_sessions)
    cfg.save(PATH)

extends Node



const _SETTING_PREFIX:= "game_analytics/"



const _GLOBAL_EVENT_TYPES:= {
    "session_start": true, "session_end": true, "app_focus_change": true, 
    "music_change": true, "settings_change": true, "pause_event": true, 
    "funnel_milestone": true, "level_browsed": true, "multiplier_milestone": true, 
    "tutorial_abandon": true, "tutorial_section_start": true, "tutorial_section_complete": true, 
    "tutorial_complete": true, "tutorial_section_fail": true, 
    "unclean_shutdown": true, "stage_graze_summary": true, 
}

const _MAP_ID_PATTERN:= "^[a-zA-Z0-9_-]{1,64}$"
static var _map_id_re: RegEx = null

static func _is_valid_map_id(map_id: String) -> bool:
    if _map_id_re == null:
        _map_id_re = RegEx.create_from_string(_MAP_ID_PATTERN)
    return _map_id_re.search(map_id) != null

var _consent:= GameAnalyticsConsentStore.new()
var _http: HTTPRequest
var _queue: Array[Dictionary] = []
var _busy: bool = false
var _last_request_meta: Dictionary = {}


var _session_start_time_msec: int = 0


const _DISK_QUEUE_PATH:= "user://analytics_queue.cfg"
const _SESSION_STATE_PATH:= "user://analytics_session.cfg"
const _BREADCRUMB_PATH:= "user://analytics_breadcrumbs.cfg"
const MAX_BREADCRUMBS:= 10
const DISK_FLUSH_INTERVAL:= 10
var _breadcrumbs: Array[String] = []
var _breadcrumb_counter: int = 0


var _perf_timer: Timer
var _perf_fps_min: float = 9999.0
var _perf_fps_samples: int = 0
var _perf_fps_sum: float = 0.0
var _perf_active_map_id: String = ""
var _perf_active_run_id: String = ""
var _perf_stage_index: int = -1
var _perf_attempt_number: int = -1

func _ready() -> void :
    _consent.load_from_disk()
    _check_previous_crash()
    _http = HTTPRequest.new()
    add_child(_http)
    _http.request_completed.connect(_on_http_completed)
    _load_disk_queue()
    _write_session_active(true)
    var tr:= preload("res://addons/game_analytics/core/ui_session_tracker.gd").new()
    tr.name = "UiSessionTracker"
    add_child(tr)
    _session_start_time_msec = Time.get_ticks_msec()
    _setup_perf_timer()

    EventBus.setting_changed.connect(_on_setting_changed)
    if OS.is_debug_build() and not is_transport_configured():
        push_warning(
            "GameAnalytics: HTTP transport is off or incomplete. Turn on game_analytics/enabled and set base_url plus api_key in Project Settings."
        )

static func make_uuid_v4() -> String:
    var rng:= RandomNumberGenerator.new()
    rng.randomize()
    var b:= PackedByteArray()
    b.resize(16)
    for i in 16:
        b[i] = rng.randi_range(0, 255)
    b[6] = (b[6] & 15) | 64
    b[8] = (b[8] & 63) | 128
    var hex:= "0123456789abcdef"
    var s:= ""
    for i in 16:
        s += hex[b[i] >> 4] + hex[b[i] & 15]
    return s.substr(0, 8) + "-" + s.substr(8, 4) + "-" + s.substr(12, 4) + "-" + s.substr(16, 4) + "-" + s.substr(20, 12)

func _setting(key: String, default_val: Variant) -> Variant:
    var p:= _SETTING_PREFIX + key
    if ProjectSettings.has_setting(p):
        return ProjectSettings.get_setting(p)
    return default_val


func _debug_enabled() -> bool:
    return bool(_setting("debug_logging", false))

func _log_debug(message: String) -> void :
    if _debug_enabled():
        print("GameAnalytics: " + message)

func _fmt_dbg_num(v: Variant) -> String:
    if v == null:
        return ""
    match typeof(v):
        TYPE_INT:
            return str(v)
        TYPE_FLOAT:
            var f:= float(v)
            if is_nan(f) or is_inf(f):
                return ""
            if absf(f - roundf(f)) < 0.0001:
                return str(int(roundf(f)))
            return str(snappedf(f, 0.01))
        _:
            return str(v).strip_edges()


func _extract_event_meta_from_body(body_utf8: String) -> Dictionary:
    var parsed:= JSON.parse_string(body_utf8)
    if typeof(parsed) != TYPE_DICTIONARY:
        return {}
    var d: Dictionary = parsed
    var events: Variant = d.get("events", [])
    if typeof(events) != TYPE_ARRAY or events.is_empty():
        return {}
    var ev: Variant = events[0]
    if typeof(ev) != TYPE_DICTIONARY:
        return {}
    var e: Dictionary = ev
    var map_id:= str(e.get("map_id", ""))
    if map_id.is_empty():
        map_id = str(e.get("level_id", ""))
    var obstacle:= str(e.get("obstacle_type_id", ""))
    if obstacle.is_empty():
        obstacle = str(e.get("death_obstacle_type", ""))
    if obstacle.is_empty() and e.has("death_obstacle") and e["death_obstacle"] is Dictionary:
        obstacle = str((e["death_obstacle"] as Dictionary).get("obstacle_type_id", ""))
    if obstacle.is_empty() or obstacle == "unknown":
        var oname:= str(e.get("obstacle_name", "")).strip_edges()
        if not oname.is_empty():
            obstacle = oname
    if (obstacle.is_empty() or obstacle == "unknown") and e.has("death_obstacle") and e["death_obstacle"] is Dictionary:
        var dob0: Dictionary = e["death_obstacle"]
        var on2:= str(dob0.get("obstacle_name", "")).strip_edges()
        if not on2.is_empty():
            obstacle = on2

    var stage_v:= e.get("stage_index", null)
    var attempt_v:= e.get("attempt_number", null)
    var stage_s:= ""
    if stage_v != null:
        stage_s = _fmt_dbg_num(stage_v)
    var attempt_s:= ""
    if attempt_v != null:
        attempt_s = _fmt_dbg_num(attempt_v)

    var score_s:= ""
    if e.has("high_score"):
        score_s = _fmt_dbg_num(e["high_score"])
    elif e.has("score"):
        score_s = _fmt_dbg_num(e["score"])
    elif e.has("score_at_death"):
        score_s = _fmt_dbg_num(e["score_at_death"])
    elif e.has("score_at_transition"):
        score_s = _fmt_dbg_num(e["score_at_transition"])
    elif e.has("score_at_pause"):
        score_s = _fmt_dbg_num(e["score_at_pause"])

    var extras_parts: PackedStringArray = []
    if e.has("fps_avg"):
        extras_parts.append("fps=" + _fmt_dbg_num(e["fps_avg"]))
    if e.has("fps_min"):
        extras_parts.append("fps_min=" + _fmt_dbg_num(e["fps_min"]))
    if e.has("multiplier_level"):
        extras_parts.append("mult=" + _fmt_dbg_num(e["multiplier_level"]))
    if e.has("time_into_run_sec"):
        extras_parts.append("t_run=" + _fmt_dbg_num(e["time_into_run_sec"]))
    if e.has("chain_count"):
        extras_parts.append("chain=" + _fmt_dbg_num(e["chain_count"]))
    if e.has("quality_preset"):
        extras_parts.append("qp=" + str(e["quality_preset"]).strip_edges())
    if e.has("milestone"):
        extras_parts.append("mile=" + str(e["milestone"]))
    if e.has("action"):
        extras_parts.append("action=" + str(e["action"]))
    if e.has("gained"):
        extras_parts.append("focus=" + ("in" if bool(e["gained"]) else "out"))
    if e.has("previous_session_duration_sec"):
        extras_parts.append("prev_sess_s=" + _fmt_dbg_num(e["previous_session_duration_sec"]))
    if e.has("screen_id"):
        extras_parts.append("scr=" + str(e["screen_id"]))
    var ev_type:= str(e.get("type", ""))
    if ev_type == "ui_screen_time" and e.has("session_time_seconds"):
        extras_parts.append("seg_s=" + _fmt_dbg_num(e["session_time_seconds"]))
    if typeof(e.get("breadcrumbs", null)) == TYPE_ARRAY:
        extras_parts.append("bc_n=" + str((e["breadcrumbs"] as Array).size()))
    if e.has("gpu_time_ms"):
        extras_parts.append("gpu_ms=" + _fmt_dbg_num(e["gpu_time_ms"]))
    if e.has("cpu_time_ms"):
        extras_parts.append("cpu_ms=" + _fmt_dbg_num(e["cpu_time_ms"]))
    if e.has("contact_kind"):
        extras_parts.append("contact=" + str(e["contact_kind"]))
    if e.has("duration_seconds"):
        extras_parts.append("dur_s=" + _fmt_dbg_num(e["duration_seconds"]))
    if e.has("stage_id"):
        extras_parts.append("stage_id=" + str(e["stage_id"]).strip_edges())

    return {
        "type": str(e.get("type", "")), 
        "map_id": map_id, 
        "run_id": str(e.get("run_id", "")), 
        "game_version": str(e.get("game_version", "")), 
        "stage_index": stage_s, 
        "attempt_number": attempt_s, 
        "score": score_s, 
        "obstacle_type_id": obstacle, 
        "debug_extras": " ".join(extras_parts), 
    }


func _debug_log_suffix(meta: Dictionary) -> String:
    var x:= str(meta.get("debug_extras", "")).strip_edges()
    if x.is_empty():
        return ""
    return " " + x



func _debug_kv(label: String, meta: Dictionary, key: String) -> String:
    var v:= str(meta.get(key, "")).strip_edges()
    if v.is_empty():
        return ""
    return " " + label + "=" + v


func _debug_transport_line(meta: Dictionary, prefix: String) -> String:


    var s:= prefix
    s += _debug_kv("type", meta, "type")
    s += _debug_kv("map_id", meta, "map_id")
    s += _debug_kv("run_id", meta, "run_id")
    s += _debug_kv("game_version", meta, "game_version")
    s += _debug_kv("stage_index", meta, "stage_index")
    s += _debug_kv("attempt", meta, "attempt_number")
    s += _debug_kv("score", meta, "score")
    s += _debug_kv("obstacle", meta, "obstacle_type_id")
    s += _debug_log_suffix(meta)
    return s

func is_transport_configured() -> bool:
    return bool(_setting("enabled", false)) and not str(_setting("base_url", "")).is_empty()

func consent_prompt_completed() -> bool:
    return _consent.consent_prompt_completed

func analytics_consented() -> bool:
    return _consent.analytics_consented

func should_show_privacy_prompt() -> bool:
    return not _consent.consent_prompt_completed

func set_privacy_choice(accept_analytics: bool) -> void :
    _consent.analytics_consented = accept_analytics
    _consent.consent_prompt_completed = true
    if accept_analytics and _consent.session_id.is_empty():
        _consent.session_id = make_uuid_v4()
    _consent.save_to_disk()



func _game_api_key() -> String:
    var k:= String(OS.get_environment("SENSORY_GAME_API_KEY")).strip_edges()
    if k.is_empty():
        k = String(OS.get_environment("GAME_API_KEY")).strip_edges()
    if k.is_empty():
        k = str(_setting("api_key", "")).strip_edges()
    return k


func _hmac_secret() -> String:
    var s:= String(OS.get_environment("SENSORY_HMAC_SECRET")).strip_edges()
    if not s.is_empty():
        return s
    s = String(OS.get_environment("HMAC_SECRET")).strip_edges()
    if not s.is_empty():
        return s
    s = str(_setting("hmac_secret", "")).strip_edges()
    if not s.is_empty():
        return s
    return _game_api_key()

func _canonical_string(method: String, path: String, ts_ms: String, body_utf8: String) -> String:
    var body_bytes:= body_utf8.to_utf8_buffer()
    var hc:= HashingContext.new()
    hc.start(HashingContext.HASH_SHA256)
    hc.update(body_bytes)
    var digest:= hc.finish()
    var body_hex:= digest.hex_encode()
    return method.to_upper() + "\n" + path + "\n" + ts_ms + "\n" + body_hex

func _sign(method: String, path: String, body_utf8: String) -> Dictionary:
    var ts_ms:= str(int(Time.get_unix_time_from_system() * 1000.0))
    var canonical:= _canonical_string(method, path, ts_ms, body_utf8)
    var secret:= _hmac_secret().to_utf8_buffer()
    var msg:= canonical.to_utf8_buffer()
    var hctx:= HMACContext.new()
    hctx.start(HashingContext.HASH_SHA256, secret)
    hctx.update(msg)
    var mac:= hctx.finish()
    return {"ts": ts_ms, "sig": mac.hex_encode()}

func _enqueue(path: String, body_utf8: String, idempotency_key: String) -> void :
    if not is_transport_configured():
        return
    var api_key:= _game_api_key()
    if api_key.is_empty():
        return
    _queue.append({"path": path, "body": body_utf8, "idem": idempotency_key})
    _save_disk_queue()
    _pump_queue()

func _pump_queue() -> void :
    if _busy or _queue.is_empty():
        return
    var item: Dictionary = _queue[0]
    var path: String = item["path"]
    var body_utf8: String = item["body"]
    var idem: String = item.get("idem", "")
    var base:= str(_setting("base_url", "")).trim_suffix("/")
    var url:= base + path
    var sig_data:= _sign("POST", path, body_utf8)
    var headers:= PackedStringArray([
        "Content-Type: application/json", 
        "X-Game-Key: " + _game_api_key(), 
        "X-Timestamp: " + str(sig_data["ts"]), 
        "X-Signature: " + str(sig_data["sig"]), 


        "X-Forwarded-Proto: https", 
    ])
    if not idem.is_empty():
        headers.append("Idempotency-Key: " + idem)
    _last_request_meta = _extract_event_meta_from_body(body_utf8)
    _last_request_meta["path"] = path
    _last_request_meta["idem"] = idem
    var idem_s:= str(idem).strip_edges()
    var post_line:= _debug_transport_line(_last_request_meta, "POST " + path)
    if not idem_s.is_empty():
        post_line += " idem=" + idem_s
    _log_debug(post_line)
    _busy = true
    var err:= _http.request(url, headers, HTTPClient.METHOD_POST, body_utf8)
    if err != OK:
        push_warning("GameAnalytics: request failed to start (HTTPRequest error %s) url=%s" % [str(err), url])
        _busy = false

        _retry_after_sec(5.0)

func _on_http_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void :
    _busy = false
    var success:= result == HTTPRequest.RESULT_SUCCESS and response_code >= 200 and response_code < 300
    if result != HTTPRequest.RESULT_SUCCESS:
        push_warning("GameAnalytics: transport error result=%d (see HTTPRequest.Result)" % result)
    elif response_code < 200 or response_code >= 300:
        var snippet:= body.get_string_from_utf8()
        if snippet.length() > 220:
            snippet = snippet.substr(0, 220) + "..."
        push_warning("GameAnalytics: HTTP %d %s" % [response_code, snippet])
        var err_line:= _debug_transport_line(
            _last_request_meta, 
            "response code=" + str(response_code) + " path=" + str(_last_request_meta.get("path", ""))
        )
        err_line += " reason_body=" + snippet
        _log_debug(err_line)
    if success:
        _log_debug(
            _debug_transport_line(
                _last_request_meta, 
                "response code=200 path=" + str(_last_request_meta.get("path", ""))
            )
        )

        if not _queue.is_empty():
            _queue.pop_front()
            _save_disk_queue()
        _pump_queue()
    else:
        var retryable_http:= response_code == 0 or response_code == 408 or response_code == 409 or response_code == 425 or response_code == 429 or response_code >= 500
        if retryable_http:

            _retry_after_sec(5.0)
        else:

            if not _queue.is_empty():
                _queue.pop_front()
                _save_disk_queue()
            _pump_queue()

func _retry_after_sec(delay: float) -> void :
    var timer:= get_tree().create_timer(delay)
    timer.timeout.connect(_pump_queue, CONNECT_ONE_SHOT)

func game_version_string() -> String:
    var v:= str(_setting("game_version", "")).strip_edges()
    if not v.is_empty():
        return v
    if ProjectSettings.has_setting("application/config/version"):
        v = str(ProjectSettings.get_setting("application/config/version", "")).strip_edges()
        if not v.is_empty():
            return v
    return "dev"

func platform_string() -> String:
    match OS.get_name():
        "Windows":
            return "windows"
        "Linux":
            return "linux"
        "macOS", "OSX":
            return "macos"
        _:
            return OS.get_name().to_lower()

func _ensure_client_install_id() -> void :
    if not _consent.install_id.is_empty():
        return
    _consent.install_id = make_uuid_v4()
    _consent.save_to_disk()


func record_anonymous_event(event_type: String, map_id: String, occurred_at_iso: String = "") -> void :
    var clean_id:= map_id.strip_edges()
    if clean_id.is_empty() or not _is_valid_map_id(clean_id):

        push_warning("GameAnalytics: anonymous '%s' event had invalid map_id '%s' -- using 'unknown'" % [event_type, map_id])
        clean_id = "unknown"
    var ev:= {
        "type": event_type, 
        "map_id": clean_id, 
        "game_version": game_version_string(), 
        "platform": platform_string(), 
    }
    if not occurred_at_iso.is_empty():
        ev["occurred_at"] = occurred_at_iso
    var body:= {"events": [ev]}
    var json:= JSON.stringify(body)
    _enqueue("/v1/anonymous/events", json, make_uuid_v4())

func record_analytics_events(events: Array, idempotency_key: String = "") -> void :
    if not analytics_consented():
        return
    if not is_transport_configured():
        return
    if _consent.session_id.is_empty():
        _consent.session_id = make_uuid_v4()
        _consent.save_to_disk()
    _ensure_client_install_id()
    var mv: int = int(_setting("manifest_version", 1))
    var normalized: Array = []
    for e in events:
        if e is Dictionary:
            var ev: Dictionary = (e as Dictionary).duplicate(true)
            if not ev.has("game_version"):
                ev["game_version"] = game_version_string()
            if not ev.has("platform"):
                ev["platform"] = platform_string()
            var ev_type:= str(ev.get("type", ""))
            var map_id_s:= str(ev.get("map_id", "")).strip_edges()
            if map_id_s.is_empty():
                if _GLOBAL_EVENT_TYPES.has(ev_type):
                    ev["map_id"] = "global"
                else:
                    push_warning("GameAnalytics: dropping '%s' event with empty map_id" % ev_type)
                    continue
            elif not _is_valid_map_id(map_id_s):
                push_warning("GameAnalytics: dropping '%s' event with invalid map_id '%s'" % [ev_type, map_id_s])
                continue
            else:
                ev["map_id"] = map_id_s
            normalized.append(ev)
        else:
            normalized.append(e)
    if normalized.is_empty():
        return
    var body:= {
        "session_id": _consent.session_id, 
        "manifest_version": mv, 
        "events": normalized, 
        "client_install_id": _consent.install_id, 
    }
    var pk:= player_key_for_leaderboards().strip_edges()
    if not pk.is_empty():
        body["client_player_key"] = pk.to_lower()
    var json:= JSON.stringify(body)
    _save_breadcrumb(json)
    var idem:= idempotency_key
    if idem.is_empty():
        idem = make_uuid_v4()
    _enqueue("/v1/analytics/events", json, idem)

func build_context_dict() -> Dictionary:
    var vi:= Engine.get_version_info()
    var gw:= get_window()
    return {
        "godot_version": "%d.%d.%d" % [vi.major, vi.minor, vi.patch], 
        "os_name": OS.get_name(), 
        "cpu_name": OS.get_processor_name(), 
        "locale": TranslationServer.get_locale(), 
        "window_w": gw.size.x if gw else 0, 
        "window_h": gw.size.y if gw else 0, 
        "fullscreen": (gw.mode == Window.MODE_FULLSCREEN or gw.mode == Window.MODE_EXCLUSIVE_FULLSCREEN) if gw else false, 
        "vsync": DisplayServer.window_get_vsync_mode() if gw else 0, 
    }


func build_performance_dict() -> Dictionary:
    var d:= {"fps_avg": float(Engine.get_frames_per_second())}
    var gpu:= RenderingServer.get_video_adapter_name()
    if not gpu.is_empty():
        d["gpu_name"] = gpu
    var drv:= RenderingServer.get_current_rendering_driver_name()
    if not drv.is_empty():
        d["renderer"] = drv
    if RenderingQualityManager:
        match RenderingQualityManager.get_preset():
            RenderingQualityManager.QualityPreset.LOW:
                d["quality_preset"] = "low"
            RenderingQualityManager.QualityPreset.MEDIUM:
                d["quality_preset"] = "medium"
            RenderingQualityManager.QualityPreset.HIGH:
                d["quality_preset"] = "high"
            RenderingQualityManager.QualityPreset.ULTRA:
                d["quality_preset"] = "ultra"
            _:
                d["quality_preset"] = "unknown"
    return d



func record_stage_transition(map_id: String, run_id: String, stage_index: int, stage_id: String, score_at_transition: float) -> void :
    if not analytics_consented():
        return
    if not is_transport_configured():
        return
    var ev:= {
        "type": "stage_transition", 
        "map_id": map_id, 
        "run_id": run_id, 
        "stage_index": stage_index, 
        "stage_id": stage_id, 
        "score_at_transition": score_at_transition, 
    }
    ev.merge(build_context_dict(), true)
    ev.merge(build_performance_dict(), true)
    record_analytics_events([ev], run_id + "_st_" + str(stage_index))



func record_performance_snapshot(map_id: String, run_id: String) -> void :
    if not analytics_consented():
        return
    if not is_transport_configured():
        return
    var ev:= {
        "type": "performance_snapshot", 
        "map_id": map_id, 
        "run_id": run_id, 
    }
    ev.merge(build_context_dict(), true)
    ev.merge(build_performance_dict(), true)
    record_analytics_events([ev], make_uuid_v4() + "_perf_" + map_id)



func record_obstacle_contact(map_id: String, run_id: String, obstacle_type_id: String, contact_kind: String) -> void :
    if not analytics_consented():
        return
    if not is_transport_configured():
        return
    var ev:= {
        "type": "obstacle_contact", 
        "map_id": map_id, 
        "run_id": run_id, 
        "obstacle_type_id": obstacle_type_id, 
        "contact_kind": contact_kind, 
    }
    ev.merge(build_context_dict(), true)
    record_analytics_events([ev], make_uuid_v4() + "_oc_" + obstacle_type_id)

func notify_ui_settings(visible: bool) -> void :
    var t:= get_node_or_null("UiSessionTracker")
    if t and t.has_method("notify_settings_visibility"):
        t.notify_settings_visibility(visible)

func steam_id_hash_opt_in() -> String:
    if not Engine.has_singleton("Steam"):
        return ""
    var steam: Object = Engine.get_singleton("Steam")
    var sid: Variant = null
    if steam.has_method("getSteamID64"):
        sid = steam.call("getSteamID64")
    elif steam.has_method("getSteamID"):
        sid = steam.call("getSteamID")
    if sid == null:
        return ""
    var salt:= str(_setting("steam_hash_salt", "sensory_analytics"))
    var hc:= HashingContext.new()
    hc.start(HashingContext.HASH_SHA256)
    hc.update((str(sid) + salt).to_utf8_buffer())
    return hc.finish().hex_encode()

func player_key_for_leaderboards() -> String:
    var h:= steam_id_hash_opt_in()
    if not h.is_empty():
        return h
    if not analytics_consented() or _consent.session_id.is_empty():
        return ""
    var salt:= str(_setting("steam_hash_salt", "sensory_analytics"))
    var hc:= HashingContext.new()
    hc.start(HashingContext.HASH_SHA256)
    hc.update(("session:" + _consent.session_id + ":" + salt).to_utf8_buffer())
    return hc.finish().hex_encode()

func submit_campaign_leaderboards(map_id: String, score: float, time_seconds: float, deaths: float, grazes: float) -> void :
    if not analytics_consented():
        return
    if not is_transport_configured():
        return
    var pk:= player_key_for_leaderboards()
    if pk.is_empty():
        return
    var mv: int = int(_setting("manifest_version", 1))
    var body:= {
        "map_id": map_id, 
        "manifest_version": mv, 
        "player_key": pk, 
        "game_version": game_version_string(), 
        "score": score, 
        "time_seconds": time_seconds, 
        "deaths": deaths, 
        "grazes": grazes, 
    }
    _enqueue("/v1/leaderboards/submit", JSON.stringify(body), make_uuid_v4())






func build_hardware_dict() -> Dictionary:
    var d:= {
        "os_name": OS.get_name(), 
        "os_version": OS.get_version(), 
        "locale": TranslationServer.get_locale(), 
        "cpu_name": OS.get_processor_name(), 
        "cpu_count": OS.get_processor_count(), 
        "gpu_name": RenderingServer.get_video_adapter_name(), 
        "gpu_driver": RenderingServer.get_current_rendering_driver_name(), 
        "gpu_api_version": RenderingServer.get_video_adapter_api_version(), 
    }
    var gw:= get_window()
    if gw:
        d["display_w"] = DisplayServer.screen_get_size().x
        d["display_h"] = DisplayServer.screen_get_size().y
        d["window_w"] = gw.size.x
        d["window_h"] = gw.size.y
    return d


func build_settings_snapshot_dict() -> Dictionary:
    var gs:= get_node_or_null("/root/GameSettings")
    if gs == null:
        return {}
    var d:= {}
    if gs.has_method("get_quality_preset"):
        d["quality_preset"] = gs.get_quality_preset()
    if gs.has_method("get_render_scale"):
        d["render_scale"] = gs.get_render_scale()
    if gs.has_method("get_fps_cap"):
        d["fps_cap"] = gs.get_fps_cap()
    if gs.has_method("get_fullscreen_mode"):
        d["fullscreen_mode"] = gs.get_fullscreen_mode()
    if gs.has_method("get_vsync_mode"):
        d["vsync_mode"] = gs.get_vsync_mode()
    if gs.has_method("is_shadows_enabled"):
        d["shadows_enabled"] = gs.is_shadows_enabled()
    if gs.has_method("is_ssao_enabled"):
        d["ssao_enabled"] = gs.is_ssao_enabled()
    if gs.has_method("is_glow_enabled"):
        d["glow_enabled"] = gs.is_glow_enabled()
    if gs.has_method("is_fog_enabled"):
        d["fog_enabled"] = gs.is_fog_enabled()
    if gs.has_method("is_particles_enabled"):
        d["particles_enabled"] = gs.is_particles_enabled()
    if gs.has_method("get_master_volume"):
        d["master_volume"] = gs.get_master_volume()
    if gs.has_method("get_music_volume"):
        d["music_volume"] = gs.get_music_volume()
    if gs.has_method("get_sfx_volume"):
        d["sfx_volume"] = gs.get_sfx_volume()
    if gs.has_method("get_mouse_sensitivity"):
        d["mouse_sensitivity"] = gs.get_mouse_sensitivity()
    if gs.has_method("get_shake_intensity"):
        d["shake_intensity"] = gs.get_shake_intensity()
    if gs.has_method("get_flash_intensity"):
        d["flash_intensity"] = gs.get_flash_intensity()
    if gs.has_method("get_chroma_intensity"):
        d["chroma_intensity"] = gs.get_chroma_intensity()
    if gs.has_method("get_screen_intensity"):
        d["screen_intensity"] = gs.get_screen_intensity()
    if gs.has_method("get_hud_glitch_intensity"):
        d["hud_glitch_intensity"] = gs.get_hud_glitch_intensity()
    return d






func record_session_start() -> void :
    if not analytics_consented():
        return

    var is_first:= _consent.total_sessions == 0
    var days_since:= 0.0
    if not _consent.last_session_end_timestamp.is_empty():
        var prev_dict:= Time.get_datetime_dict_from_datetime_string(_consent.last_session_end_timestamp, true)
        var prev_unix:= Time.get_unix_time_from_datetime_dict(prev_dict) if prev_dict.size() > 0 else 0.0
        if prev_unix > 0.0:
            days_since = (Time.get_unix_time_from_system() - prev_unix) / 86400.0
    _consent.total_sessions += 1
    _consent.save_to_disk()
    var ev:= {
        "type": "session_start", 
        "game_version": game_version_string(), 
        "platform": platform_string(), 
        "timestamp": Time.get_datetime_string_from_system(true), 
        "is_first_session": is_first, 
        "days_since_last_session": snappedf(days_since, 0.01), 
        "total_sessions": _consent.total_sessions, 
    }
    if not _consent.last_session_end_timestamp.is_empty():
        ev["last_session_timestamp"] = _consent.last_session_end_timestamp
    ev.merge(build_hardware_dict(), true)
    ev["settings"] = build_settings_snapshot_dict()
    var cm:= get_node_or_null("/root/CampaignManager")
    if cm:
        if cm.has_method("is_tutorial_completed"):
            ev["tutorial_completed"] = cm.is_tutorial_completed()
        if cm.get("save_data") and cm.save_data.get("total_deaths") != null:
            ev["total_deaths"] = cm.save_data.total_deaths
        if cm.get("save_data") and cm.save_data.get("total_levels_completed") != null:
            ev["total_levels_completed"] = cm.save_data.total_levels_completed
    var sh:= steam_id_hash_opt_in()
    if not sh.is_empty():
        ev["steam_id_sha256"] = sh
    record_analytics_events([ev], make_uuid_v4() + "_session_start")


func record_session_end() -> void :

    _write_session_active(false)
    _consent.last_session_end_timestamp = Time.get_datetime_string_from_system(true)
    _consent.save_to_disk()
    if not analytics_consented():
        return
    var total_sec:= (Time.get_ticks_msec() - _session_start_time_msec) / 1000.0
    var ev:= {
        "type": "session_end", 
        "total_session_time_seconds": total_sec, 
        "game_version": game_version_string(), 
        "timestamp": Time.get_datetime_string_from_system(true), 
    }

    var tracker:= get_node_or_null("UiSessionTracker")
    if tracker and tracker.has_method("get_navigation_path"):
        ev["screens_visited"] = tracker.get_navigation_path()
    record_analytics_events([ev], make_uuid_v4() + "_session_end")


func record_app_focus_change(gained: bool) -> void :
    if not analytics_consented():
        return
    var ev:= {
        "type": "app_focus_change", 
        "gained": gained, 
        "timestamp": Time.get_datetime_string_from_system(true), 
    }
    record_analytics_events([ev])






func record_player_death(death_data: Dictionary) -> void :
    var map_id: String = death_data.get("level_id", "unknown")
    record_anonymous_event("player_death", map_id)
    if not analytics_consented():
        return
    var ev:= {"type": "player_death"}
    ev.merge(death_data, true)
    ev["game_version"] = game_version_string()
    ev["timestamp"] = Time.get_datetime_string_from_system(true)
    ev.merge(build_performance_dict(), true)
    var sh:= steam_id_hash_opt_in()
    if not sh.is_empty():
        ev["steam_id_sha256"] = sh
    var run_id: String = death_data.get("run_id", "")
    var idem:= (run_id + "_death_" if not run_id.is_empty() else "") + make_uuid_v4()
    record_analytics_events([ev], idem)






func record_ranked_run_end(run_data: Dictionary) -> void :
    var map_id: String = run_data.get("level_id", "unknown")
    record_anonymous_event("ranked_run_end", map_id)
    if not analytics_consented():
        return
    var ev:= {"type": "ranked_run_end"}
    ev.merge(run_data, true)
    ev["game_version"] = game_version_string()
    ev["timestamp"] = Time.get_datetime_string_from_system(true)
    ev.merge(build_performance_dict(), true)
    record_analytics_events([ev], make_uuid_v4() + "_ranked_end")






func record_tutorial_event(event_type: String, data: Dictionary) -> void :
    if not analytics_consented():
        return
    var ev:= {"type": event_type}
    ev.merge(data, true)
    ev["game_version"] = game_version_string()
    ev["timestamp"] = Time.get_datetime_string_from_system(true)
    record_analytics_events([ev], make_uuid_v4() + "_tut_" + event_type)






func record_music_change(song_name: String, prev_song: String, context: String, time_with_prev: float) -> void :
    if not analytics_consented():
        return
    var ev:= {
        "type": "music_change", 
        "song_name": song_name, 
        "previous_song_name": prev_song, 
        "context": context, 
        "time_with_previous_seconds": time_with_prev, 
    }
    record_analytics_events([ev])






func record_settings_change(setting_key: String, old_value: Variant, new_value: Variant) -> void :
    if not analytics_consented():
        return
    var ev:= {
        "type": "settings_change", 
        "setting_key": setting_key, 
        "old_value": str(old_value), 
        "new_value": str(new_value), 
    }
    record_analytics_events([ev])


func _on_setting_changed(key: String, old_value: Variant, new_value: Variant) -> void :
    record_settings_change(key, old_value, new_value)






func record_pause_event(action: String, data: Dictionary) -> void :
    if not analytics_consented():
        return
    var ev:= {"type": "pause_event", "action": action}
    ev.merge(data, true)
    ev["timestamp"] = Time.get_datetime_string_from_system(true)
    record_analytics_events([ev])






func _setup_perf_timer() -> void :
    _perf_timer = Timer.new()
    _perf_timer.name = "PerfTimer"
    _perf_timer.wait_time = 30.0
    _perf_timer.one_shot = false
    _perf_timer.autostart = false
    _perf_timer.timeout.connect(_on_perf_timer_tick)
    add_child(_perf_timer)


func start_perf_tracking(map_id: String, run_id: String, stage_index: int = -1, attempt_number: int = -1) -> void :
    _perf_active_map_id = map_id
    _perf_active_run_id = run_id
    _perf_stage_index = stage_index
    _perf_attempt_number = attempt_number
    _perf_fps_min = 9999.0
    _perf_fps_samples = 0
    _perf_fps_sum = 0.0
    _perf_timer.start()

    _on_perf_timer_tick()



func set_perf_tracking_context(stage_index: int, attempt_number: int) -> void :
    _perf_stage_index = stage_index
    _perf_attempt_number = attempt_number


func stop_perf_tracking() -> void :

    if not _perf_active_map_id.is_empty():
        _on_perf_timer_tick()
    _perf_timer.stop()
    _perf_active_map_id = ""
    _perf_active_run_id = ""
    _perf_stage_index = -1
    _perf_attempt_number = -1


func _process(_delta: float) -> void :
    if not _perf_timer.is_stopped():
        var fps:= float(Engine.get_frames_per_second())
        if fps < _perf_fps_min:
            _perf_fps_min = fps
        _perf_fps_sum += fps
        _perf_fps_samples += 1


func _on_perf_timer_tick() -> void :
    if not analytics_consented():
        return
    if _perf_active_map_id.strip_edges().is_empty():
        return
    var fps_avg:= _perf_fps_sum / maxf(_perf_fps_samples, 1.0)
    var ev:= {
        "type": "performance_periodic", 
        "map_id": _perf_active_map_id, 
        "run_id": _perf_active_run_id, 
        "fps_avg": snappedf(fps_avg, 0.1), 
        "fps_min": _perf_fps_min if _perf_fps_min < 9999.0 else 0.0, 
        "memory_static_bytes": OS.get_static_memory_usage(), 
        "memory_static_max_bytes": OS.get_static_memory_peak_usage(), 
        "object_count": int(Performance.get_monitor(Performance.OBJECT_COUNT)), 
        "orphan_node_count": int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)), 
    }
    if _perf_stage_index >= 0:
        ev["stage_index"] = _perf_stage_index
    if _perf_attempt_number >= 0:
        ev["attempt_number"] = _perf_attempt_number
    var vp:= get_viewport()
    if vp:
        var gpu_time:= RenderingServer.viewport_get_measured_render_time_gpu(vp.get_viewport_rid())
        var cpu_time:= RenderingServer.viewport_get_measured_render_time_cpu(vp.get_viewport_rid())
        if gpu_time > 0.0:
            ev["gpu_time_ms"] = snappedf(gpu_time, 0.01)
        if cpu_time > 0.0:
            ev["cpu_time_ms"] = snappedf(cpu_time, 0.01)
    ev.merge(build_context_dict(), true)
    ev.merge(build_performance_dict(), true)

    if _perf_fps_samples > 0:
        ev["fps_avg"] = snappedf(_perf_fps_sum / float(_perf_fps_samples), 0.1)
        ev["fps_min"] = _perf_fps_min if _perf_fps_min < 9999.0 else 0.0
    record_analytics_events([ev])

    _perf_fps_min = 9999.0
    _perf_fps_samples = 0
    _perf_fps_sum = 0.0






func _save_disk_queue() -> void :
    var cfg:= ConfigFile.new()
    for i in _queue.size():
        cfg.set_value("queue", "item_%d_path" % i, _queue[i]["path"])
        cfg.set_value("queue", "item_%d_body" % i, _queue[i]["body"])
        cfg.set_value("queue", "item_%d_idem" % i, _queue[i]["idem"])
    cfg.set_value("queue", "count", _queue.size())
    cfg.save(_DISK_QUEUE_PATH)


func _load_disk_queue() -> void :
    var cfg:= ConfigFile.new()
    if cfg.load(_DISK_QUEUE_PATH) != OK:
        return
    var count: int = cfg.get_value("queue", "count", 0)
    for i in count:
        var path: String = cfg.get_value("queue", "item_%d_path" % i, "")
        var body: String = cfg.get_value("queue", "item_%d_body" % i, "")
        var idem: String = cfg.get_value("queue", "item_%d_idem" % i, "")
        if not path.is_empty() and not body.is_empty():
            _queue.append({"path": path, "body": body, "idem": idem})

    DirAccess.remove_absolute(ProjectSettings.globalize_path(_DISK_QUEUE_PATH))
    if not _queue.is_empty():
        call_deferred("_pump_queue")






func _write_session_active(active: bool) -> void :
    var cfg:= ConfigFile.new()
    cfg.set_value("session", "active", active)
    cfg.set_value("session", "start_time_iso", Time.get_datetime_string_from_system(true))
    cfg.set_value("session", "start_time_msec", Time.get_ticks_msec())
    cfg.save(_SESSION_STATE_PATH)


func _check_previous_crash() -> void :
    var cfg:= ConfigFile.new()
    if cfg.load(_SESSION_STATE_PATH) != OK:
        return
    var was_active: bool = cfg.get_value("session", "active", false)
    if not was_active:
        return

    var start_iso: String = cfg.get_value("session", "start_time_iso", "")
    var breadcrumbs_arr: Array = _load_breadcrumbs_from_disk()
    var crash_log_tail: String = _read_crash_log_tail(50)

    var prev_duration:= 0.0
    if not start_iso.is_empty():
        var start_dict:= Time.get_datetime_dict_from_datetime_string(start_iso, true)
        var start_unix:= Time.get_unix_time_from_datetime_dict(start_dict) if start_dict.size() > 0 else 0.0
        if start_unix > 0.0:
            prev_duration = Time.get_unix_time_from_system() - start_unix
    var ev:= {
        "type": "unclean_shutdown", 
        "breadcrumbs": breadcrumbs_arr, 
        "previous_session_duration_sec": snappedf(prev_duration, 0.1), 
        "game_version": game_version_string(), 
        "timestamp": Time.get_datetime_string_from_system(true), 
    }
    if not crash_log_tail.is_empty():
        ev["crash_log_tail"] = crash_log_tail

    DirAccess.remove_absolute(ProjectSettings.globalize_path(_SESSION_STATE_PATH))
    DirAccess.remove_absolute(ProjectSettings.globalize_path(_BREADCRUMB_PATH))

    if _consent.analytics_consented and is_transport_configured():
        if _consent.session_id.is_empty():
            _consent.session_id = make_uuid_v4()
            _consent.save_to_disk()
        var mv: int = int(_setting("manifest_version", 1))
        var body:= {
            "session_id": _consent.session_id, 
            "manifest_version": mv, 
            "events": [ev], 
        }
        var json:= JSON.stringify(body)
        _queue.append({"path": "/v1/analytics/events", "body": json, "idem": make_uuid_v4() + "_crash"})


func _save_breadcrumb(event_json: String) -> void :
    _breadcrumbs.append(event_json)
    if _breadcrumbs.size() > MAX_BREADCRUMBS:
        _breadcrumbs = _breadcrumbs.slice(_breadcrumbs.size() - MAX_BREADCRUMBS)
    _breadcrumb_counter += 1
    if _breadcrumb_counter >= DISK_FLUSH_INTERVAL:
        _breadcrumb_counter = 0
        _flush_breadcrumbs_to_disk()


func _flush_breadcrumbs_to_disk() -> void :
    var cfg:= ConfigFile.new()
    cfg.set_value("breadcrumbs", "count", _breadcrumbs.size())
    for i in _breadcrumbs.size():
        cfg.set_value("breadcrumbs", "item_%d" % i, _breadcrumbs[i])
    cfg.save(_BREADCRUMB_PATH)


func _load_breadcrumbs_from_disk() -> Array:
    var cfg:= ConfigFile.new()
    if cfg.load(_BREADCRUMB_PATH) != OK:
        return []
    var count: int = cfg.get_value("breadcrumbs", "count", 0)
    var result: Array = []
    for i in count:
        var item: String = cfg.get_value("breadcrumbs", "item_%d" % i, "")
        if not item.is_empty():
            result.append(item)
    return result


func _read_crash_log_tail(max_lines: int) -> String:
    var log_path:= "user://logs/godot.log"
    if not FileAccess.file_exists(log_path):
        return ""
    var f:= FileAccess.open(log_path, FileAccess.READ)
    if f == null:
        return ""
    var content:= f.get_as_text()
    f.close()
    var lines:= content.split("\n")
    if lines.size() <= max_lines:
        return content
    var start_idx:= lines.size() - max_lines
    var tail_lines:= lines.slice(start_idx)
    return "\n".join(tail_lines)






func record_funnel_milestone(milestone: String, extra: Dictionary = {}) -> void :
    if not analytics_consented():
        return
    var ev:= {
        "type": "funnel_milestone", 
        "milestone": milestone, 
        "is_first_session": _consent.total_sessions <= 1, 
        "time_since_boot_sec": snappedf((Time.get_ticks_msec() - _session_start_time_msec) / 1000.0, 0.01), 
    }
    ev.merge(extra, true)
    record_analytics_events([ev], make_uuid_v4() + "_funnel_" + milestone)






func record_level_browsed(data: Dictionary) -> void :
    if not analytics_consented():
        return
    var ev:= {"type": "level_browsed"}
    ev.merge(data, true)
    ev["timestamp"] = Time.get_datetime_string_from_system(true)
    record_analytics_events([ev])






func record_multiplier_milestone(data: Dictionary) -> void :
    if not analytics_consented():
        return
    var ev:= {"type": "multiplier_milestone"}
    ev.merge(data, true)
    ev["timestamp"] = Time.get_datetime_string_from_system(true)
    record_analytics_events([ev])

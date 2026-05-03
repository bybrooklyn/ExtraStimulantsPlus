extends Control

@onready var _accept: Button = %AcceptButton
@onready var _decline: Button = %DeclineButton

var _hover_tweens: Dictionary = {}

const CYAN_PALETTE: = {
    "accent": Color(0.039, 0.757, 0.808, 1.0), 
    "glow": Color(0.161, 0.937, 0.992, 1.0), 
    "box_bg": Color(0.0, 0.09, 0.1, 0.4), 
}
const MUTED_PALETTE: = {
    "accent": Color(0.45, 0.45, 0.5, 1.0), 
    "glow": Color(0.55, 0.55, 0.6, 1.0), 
    "box_bg": Color(0.05, 0.05, 0.06, 0.4), 
}

func _ready() -> void :
    if _accept:
        _accept.pressed.connect(_on_accept)
    if _decline:
        _decline.pressed.connect(_on_decline)
    call_deferred("_setup_buttons")

    modulate.a = 0.0
    var tween = create_tween()
    tween.tween_property(self, "modulate:a", 1.0, 0.4)


func _setup_buttons() -> void :
    if _accept:
        _style_button(_accept, CYAN_PALETTE)
    if _decline:
        _style_button(_decline, MUTED_PALETTE)


func _style_button(btn: Button, palette: Dictionary) -> void :
    btn.pivot_offset = btn.size / 2.0

    var accent: Color = palette["accent"]
    var glow: Color = palette["glow"]
    var box_bg: Color = palette["box_bg"]

    var normal_sb: = MainMenuButtonStyleBox.new()
    normal_sb.accent_color = accent
    normal_sb.accent_glow_color = glow
    normal_sb.box_bg_color = box_bg
    normal_sb.box_left_ratio = 0.02
    normal_sb.box_right_ratio = 0.98
    normal_sb.content_margin_left = 10.0
    normal_sb.content_margin_right = 10.0

    var hover_sb: = MainMenuButtonStyleBox.new()
    hover_sb.accent_color = accent
    hover_sb.accent_glow_color = glow
    hover_sb.box_bg_color = accent
    hover_sb.border_alpha = 0.13
    hover_sb.box_left_ratio = 0.02
    hover_sb.box_right_ratio = 0.98
    hover_sb.content_margin_left = 10.0
    hover_sb.content_margin_right = 10.0

    btn.add_theme_stylebox_override("normal", normal_sb)
    btn.add_theme_stylebox_override("hover", hover_sb)
    btn.add_theme_stylebox_override("focus", hover_sb)
    btn.add_theme_stylebox_override("pressed", hover_sb)

    btn.add_theme_color_override("font_color", Color.WHITE)
    btn.add_theme_color_override("font_hover_color", Color.BLACK)
    btn.add_theme_color_override("font_focus_color", Color.BLACK)
    btn.add_theme_color_override("font_pressed_color", Color.BLACK)
    btn.add_theme_color_override("font_hover_pressed_color", Color.BLACK)

    btn.mouse_entered.connect(_on_button_hover.bind(btn))
    btn.mouse_exited.connect(_on_button_exit.bind(btn))
    btn.focus_entered.connect(_on_button_hover.bind(btn))
    btn.focus_exited.connect(_on_button_exit.bind(btn))


func _on_button_hover(btn: Button) -> void :
    UiSfxManager.play_hover()
    if _hover_tweens.has(btn) and _hover_tweens[btn]:
        _hover_tweens[btn].kill()
    var tween = create_tween()
    _hover_tweens[btn] = tween
    tween.set_trans(Tween.TRANS_EXPO)
    tween.set_ease(Tween.EASE_OUT)
    tween.tween_property(btn, "scale", Vector2(1.0488, 1.0488), 0.1)


func _on_button_exit(btn: Button) -> void :
    if _hover_tweens.has(btn) and _hover_tweens[btn]:
        _hover_tweens[btn].kill()
    var tween = create_tween()
    _hover_tweens[btn] = tween
    tween.set_parallel(true)
    tween.set_trans(Tween.TRANS_ELASTIC)
    tween.set_ease(Tween.EASE_OUT)
    tween.tween_property(btn, "scale", Vector2.ONE, 0.4)
    tween.tween_property(btn, "rotation", 0.0, 0.4)


func _on_accept() -> void :
    UiSfxManager.play_click()
    var ga: Node = get_node_or_null("/root/GameAnalytics")
    if ga and ga.has_method("set_privacy_choice"):
        ga.set_privacy_choice(true)
    _dismiss()


func _on_decline() -> void :
    UiSfxManager.play_click()
    var ga: Node = get_node_or_null("/root/GameAnalytics")
    if ga and ga.has_method("set_privacy_choice"):
        ga.set_privacy_choice(false)
    _dismiss()


func _dismiss() -> void :
    var tween = create_tween()
    tween.tween_property(self, "modulate:a", 0.0, 0.3)
    tween.tween_callback(queue_free)

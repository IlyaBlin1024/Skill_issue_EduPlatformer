extends CanvasLayer

const MENU_ASSET_ROOT := "res://assets/generated_menu/"
const BUTTON_SMALL_IDLE := MENU_ASSET_ROOT + "buttons/button_small_idle.png"
const BUTTON_SMALL_SELECTED := MENU_ASSET_ROOT + "buttons/button_small_selected.png"
const PANEL_SETTINGS := MENU_ASSET_ROOT + "cards/panel_settings.png"
const PAUSE_FADE_DURATION := 0.5

var _panel: PanelContainer
var _message_label: Label
var _fade_rect: ColorRect
var _fade_tween: Tween
var _menu_font: Font
var _texture_cache: Dictionary = {}


func _ready() -> void:
	layer = 190
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_menu_font()
	_build()
	visible = false


func toggle_pause() -> void:
	if visible:
		close_pause()
	else:
		open_pause()


func open_pause() -> void:
	GameState.log_event("pause_opened")
	visible = true
	get_tree().paused = true


func close_pause() -> void:
	GameState.log_event("pause_closed")
	visible = false
	get_tree().paused = false


func _build() -> void:
	var shade := ColorRect.new()
	shade.color = Color(0.0, 0.0, 0.0, 0.62)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(shade)

	_panel = PanelContainer.new()
	_panel.anchor_left = 0.3
	_panel.anchor_top = 0.16
	_panel.anchor_right = 0.7
	_panel.anchor_bottom = 0.82
	_panel.add_theme_stylebox_override("panel", _panel_style())
	add_child(_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 54)
	margin.add_theme_constant_override("margin_right", 54)
	margin.add_theme_constant_override("margin_top", 42)
	margin.add_theme_constant_override("margin_bottom", 36)
	_panel.add_child(margin)

	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 14)
	margin.add_child(box)

	var title := Label.new()
	title.text = "Paused"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_apply_menu_font(title, 40)
	title.add_theme_color_override("font_color", Color(1.0, 0.76, 0.25))
	box.add_child(title)

	box.add_child(_button("Sound", Callable(self, "_toggle_sound")))
	box.add_child(_button("Save Game", Callable(self, "_save_game")))
	box.add_child(_button("Continue", Callable(self, "close_pause")))
	box.add_child(_button("Exit to Menu", Callable(self, "_exit_to_menu")))

	_message_label = Label.new()
	_message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_apply_menu_font(_message_label, 16)
	_message_label.add_theme_color_override("font_color", Color(0.9, 0.82, 0.62))
	box.add_child(_message_label)

	_fade_rect = ColorRect.new()
	_fade_rect.color = Color(0, 0, 0, 0)
	_fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	_fade_rect.visible = false
	add_child(_fade_rect)


func _button(text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(380, 66)
	button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_apply_menu_font(button, 22)
	button.add_theme_stylebox_override("normal", _button_style(false))
	button.add_theme_stylebox_override("hover", _button_style(true))
	button.add_theme_stylebox_override("pressed", _button_style(true))
	button.add_theme_color_override("font_color", Color(1.0, 0.86, 0.42))
	button.pressed.connect(action)
	return button


func _toggle_sound() -> void:
	GameState.log_event("pause_sound_toggled")
	var current := float(GameState.settings.get("volume", 0.85))
	GameState.set_volume(0.0 if current > 0.01 else 0.85)
	_message_label.text = "Sound off." if current > 0.01 else "Sound on."


func _save_game() -> void:
	GameState.save_current_game()
	GameState.log_event("pause_save_clicked")
	_message_label.text = "Game saved."


func _exit_to_menu() -> void:
	GameState.save_current_game()
	GameState.log_event("pause_exit_to_menu_clicked")
	get_tree().paused = false
	await _fade_to_black()
	GameState.go_to_main_menu()


func _fade_to_black() -> void:
	if _fade_rect == null:
		return
	if _fade_tween != null and _fade_tween.is_running():
		_fade_tween.kill()
	_fade_rect.visible = true
	_fade_rect.color = Color(0, 0, 0, 0)
	_fade_tween = create_tween()
	_fade_tween.tween_property(_fade_rect, "color:a", 1.0, PAUSE_FADE_DURATION)
	await _fade_tween.finished


func _button_style(active: bool) -> StyleBox:
	var textured := _texture_style(BUTTON_SMALL_SELECTED if active else BUTTON_SMALL_IDLE, 0)
	if textured != null:
		return textured
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.03, 0.04, 0.09, 0.94) if not active else Color(0.04, 0.18, 0.36, 0.96)
	style.border_color = Color(1.0, 0.52, 0.1) if not active else Color(0.2, 0.78, 1.0)
	style.set_border_width_all(3)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	return style


func _panel_style() -> StyleBox:
	var textured := _texture_style(PANEL_SETTINGS, 54)
	if textured != null:
		return textured
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.025, 0.025, 0.05, 0.92)
	style.border_color = Color(0.95, 0.48, 0.1)
	style.set_border_width_all(4)
	style.corner_radius_top_left = 12
	style.corner_radius_top_right = 12
	style.corner_radius_bottom_left = 12
	style.corner_radius_bottom_right = 12
	style.content_margin_left = 24
	style.content_margin_right = 24
	style.content_margin_top = 24
	style.content_margin_bottom = 24
	return style


func _menu_texture(path: String) -> Texture2D:
	if _texture_cache.has(path):
		return _texture_cache[path]
	var texture: Texture2D = null
	if ResourceLoader.exists(path):
		texture = load(path) as Texture2D
	_texture_cache[path] = texture
	return texture


func _texture_style(path: String, margin: int) -> StyleBoxTexture:
	var texture := _menu_texture(path)
	if texture == null:
		return null
	var style := StyleBoxTexture.new()
	style.texture = texture
	style.texture_margin_left = margin
	style.texture_margin_top = margin
	style.texture_margin_right = margin
	style.texture_margin_bottom = margin
	style.content_margin_left = 28
	style.content_margin_right = 28
	style.content_margin_top = 20
	style.content_margin_bottom = 20
	return style


func _load_menu_font() -> void:
	_menu_font = null


func _apply_menu_font(control: Control, size: int) -> void:
	control.add_theme_font_size_override("font_size", size)
	if _menu_font != null:
		control.add_theme_font_override("font", _menu_font)

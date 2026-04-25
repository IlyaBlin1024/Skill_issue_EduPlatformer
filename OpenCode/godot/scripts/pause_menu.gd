extends CanvasLayer

var _panel: PanelContainer
var _message_label: Label


func _ready() -> void:
	layer = 190
	process_mode = Node.PROCESS_MODE_ALWAYS
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
	_panel.anchor_left = 0.32
	_panel.anchor_top = 0.18
	_panel.anchor_right = 0.68
	_panel.anchor_bottom = 0.8
	_panel.add_theme_stylebox_override("panel", _panel_style())
	add_child(_panel)

	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 18)
	_panel.add_child(box)

	var title := Label.new()
	title.text = "Paused"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 58)
	title.add_theme_color_override("font_color", Color(1.0, 0.76, 0.25))
	box.add_child(title)

	box.add_child(_button("Sound", Callable(self, "_toggle_sound")))
	box.add_child(_button("Save Game", Callable(self, "_save_game")))
	box.add_child(_button("Continue", Callable(self, "close_pause")))
	box.add_child(_button("Exit to Menu", Callable(self, "_exit_to_menu")))

	_message_label = Label.new()
	_message_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message_label.add_theme_font_size_override("font_size", 20)
	_message_label.add_theme_color_override("font_color", Color(0.9, 0.82, 0.62))
	box.add_child(_message_label)


func _button(text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(420, 68)
	button.add_theme_font_size_override("font_size", 30)
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
	GameState.go_to_main_menu()


func _button_style(active: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.03, 0.04, 0.09, 0.94) if not active else Color(0.04, 0.18, 0.36, 0.96)
	style.border_color = Color(1.0, 0.52, 0.1) if not active else Color(0.2, 0.78, 1.0)
	style.set_border_width_all(3)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	return style


func _panel_style() -> StyleBoxFlat:
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

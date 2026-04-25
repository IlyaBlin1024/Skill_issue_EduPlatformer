extends Control

const VIEW_MAIN := "main"
const VIEW_PLAY := "play"
const VIEW_SAVES := "saves"
const VIEW_SETTINGS := "settings"
const VIEW_INVENTORY := "inventory"

var _content: Control
var _current_view := VIEW_MAIN
var _return_view := VIEW_MAIN
var _selected_inventory_index := 0
var _mode_buttons: Dictionary = {}
var _difficulty_buttons: Dictionary = {}
var _volume_slider: HSlider
var _api_key_edit: LineEdit
var _play_scroll: ScrollContainer
var _saves_scroll: ScrollContainer
var _export_status_label: Label


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = false
	GameState.load_all()
	if not CodeApiClient.logs_export_received.is_connected(_on_logs_export_received):
		CodeApiClient.logs_export_received.connect(_on_logs_export_received)
	if not CodeApiClient.logs_export_failed.is_connected(_on_logs_export_failed):
		CodeApiClient.logs_export_failed.connect(_on_logs_export_failed)
	_build_shell()
	_show_main()


func _build_shell() -> void:
	var background := ColorRect.new()
	background.color = Color(0.06, 0.035, 0.11)
	background.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(background)

	var sky := ColorRect.new()
	sky.color = Color(0.16, 0.08, 0.24, 0.95)
	sky.set_anchors_preset(Control.PRESET_FULL_RECT)
	sky.offset_left = 0.0
	sky.offset_top = 0.0
	sky.offset_right = 0.0
	sky.offset_bottom = 0.0
	add_child(sky)

	var sun := ColorRect.new()
	sun.color = Color(0.95, 0.44, 0.16, 0.28)
	sun.anchor_left = 0.55
	sun.anchor_top = 0.28
	sun.anchor_right = 0.9
	sun.anchor_bottom = 0.72
	add_child(sun)

	var castle := ColorRect.new()
	castle.color = Color(0.035, 0.03, 0.08, 0.72)
	castle.anchor_left = 0.68
	castle.anchor_top = 0.18
	castle.anchor_right = 0.98
	castle.anchor_bottom = 1.0
	add_child(castle)

	var vignette := ColorRect.new()
	vignette.color = Color(0.0, 0.0, 0.0, 0.24)
	vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(vignette)

	_content = Control.new()
	_content.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_content)


func _clear_content() -> void:
	for child in _content.get_children():
		child.queue_free()


func _show_main() -> void:
	_current_view = VIEW_MAIN
	GameState.log_event("menu_view_opened", {"view": VIEW_MAIN})
	_clear_content()
	var panel := VBoxContainer.new()
	panel.anchor_left = 0.18
	panel.anchor_top = 0.18
	panel.anchor_right = 0.56
	panel.anchor_bottom = 0.82
	panel.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_theme_constant_override("separation", 14)
	_content.add_child(panel)

	var title := _title_label("Skill Issue")
	panel.add_child(title)
	panel.add_child(_menu_button("Play", Callable(self, "_show_play")))
	panel.add_child(_menu_button("Saves", Callable(self, "_show_saves")))
	panel.add_child(_menu_button("Settings", Callable(self, "_show_settings")))
	panel.add_child(_menu_button("Exit", Callable(self, "_quit_game")))


func _show_play() -> void:
	_current_view = VIEW_PLAY
	GameState.log_event("menu_view_opened", {"view": VIEW_PLAY})
	_clear_content()
	_add_top_button("Back", Callable(self, "_show_main"), false)
	_add_top_button("Inventory", Callable(self, "_show_inventory_from_play"), true)
	_add_header("Play", "Choose a stage to continue your run")

	_play_scroll = ScrollContainer.new()
	_play_scroll.anchor_left = 0.1
	_play_scroll.anchor_top = 0.25
	_play_scroll.anchor_right = 0.94
	_play_scroll.anchor_bottom = 0.88
	_play_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_play_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_content.add_child(_play_scroll)

	var row := HBoxContainer.new()
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_theme_constant_override("separation", 18)
	row.alignment = BoxContainer.ALIGNMENT_BEGIN
	_play_scroll.add_child(row)

	row.add_child(_tutorial_card())
	var levels := GameState.get_levels()
	for index in range(levels.size()):
		row.add_child(_level_boss_card(index, levels[index]))
	_add_scroll_arrows(Callable(self, "_scroll_play").bind(-1), Callable(self, "_scroll_play").bind(1))


func _show_saves() -> void:
	_current_view = VIEW_SAVES
	GameState.log_event("menu_view_opened", {"view": VIEW_SAVES})
	_clear_content()
	_add_top_button("Back", Callable(self, "_show_main"), false)
	_add_header("Saves", "Choose a slot or create a new save")

	_saves_scroll = ScrollContainer.new()
	_saves_scroll.anchor_left = 0.08
	_saves_scroll.anchor_top = 0.27
	_saves_scroll.anchor_right = 0.95
	_saves_scroll.anchor_bottom = 0.88
	_saves_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_saves_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_content.add_child(_saves_scroll)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	row.alignment = BoxContainer.ALIGNMENT_BEGIN
	_saves_scroll.add_child(row)

	var slots := GameState.get_save_slots()
	for index in range(slots.size()):
		row.add_child(_save_card(index, slots[index]))
	_add_scroll_arrows(Callable(self, "_scroll_saves").bind(-1), Callable(self, "_scroll_saves").bind(1), true)


func _show_settings() -> void:
	_current_view = VIEW_SETTINGS
	GameState.log_event("menu_view_opened", {"view": VIEW_SETTINGS})
	_clear_content()
	_add_top_button("Back", Callable(self, "_show_main"), false)
	_add_header("Settings", "Local settings are saved separately from progress")

	var panel := VBoxContainer.new()
	panel.anchor_left = 0.2
	panel.anchor_top = 0.22
	panel.anchor_right = 0.82
	panel.anchor_bottom = 0.88
	panel.add_theme_constant_override("separation", 18)
	panel.add_theme_stylebox_override("panel", _panel_style(Color(0.025, 0.025, 0.045, 0.86), 3))
	_content.add_child(panel)

	panel.add_child(_settings_volume_row())
	panel.add_child(_settings_mode_row())
	panel.add_child(_settings_difficulty_row())
	panel.add_child(_settings_key_row())
	panel.add_child(_settings_logs_row())

	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 24)
	panel.add_child(actions)
	actions.add_child(_small_button("Apply", Callable(self, "_apply_settings"), true))
	actions.add_child(_small_button("Defaults", Callable(self, "_reset_settings"), false))


func _show_inventory_from_play() -> void:
	_return_view = VIEW_PLAY
	_show_inventory()


func _show_inventory() -> void:
	_current_view = VIEW_INVENTORY
	GameState.log_event("menu_view_opened", {"view": VIEW_INVENTORY})
	_clear_content()
	_add_top_button("Back", Callable(self, "_back_from_inventory"), false)
	_add_header("Inventory", "Hints found in chests")

	var root := HBoxContainer.new()
	root.anchor_left = 0.16
	root.anchor_top = 0.26
	root.anchor_right = 0.88
	root.anchor_bottom = 0.9
	root.add_theme_constant_override("separation", 22)
	_content.add_child(root)

	var grid := GridContainer.new()
	grid.columns = 4
	grid.custom_minimum_size = Vector2(620, 360)
	grid.add_theme_constant_override("h_separation", 14)
	grid.add_theme_constant_override("v_separation", 14)
	root.add_child(grid)

	var items := GameState.get_inventory_items()
	for index in range(8):
		var title := "Empty"
		var locked := true
		if index < items.size():
			var item: Dictionary = items[index]
			title = String(item.get("title", "Hint %d" % [index + 1]))
			locked = false
		var button := _inventory_slot(title, locked)
		button.pressed.connect(Callable(self, "_select_inventory_item").bind(index))
		grid.add_child(button)

	var description_panel := PanelContainer.new()
	description_panel.custom_minimum_size = Vector2(360, 260)
	description_panel.add_theme_stylebox_override("panel", _panel_style(Color(0.03, 0.025, 0.035, 0.9), 2))
	root.add_child(description_panel)
	var text := RichTextLabel.new()
	text.fit_content = true
	text.bbcode_enabled = true
	text.add_theme_font_size_override("normal_font_size", 24)
	text.add_theme_color_override("default_color", Color(1.0, 0.88, 0.5))
	description_panel.add_child(text)
	text.text = _inventory_description(items)


func _back_from_inventory() -> void:
	if _return_view == VIEW_PLAY:
		_show_play()
	else:
		_show_main()


func _tutorial_card() -> Control:
	var card := _card_base(Vector2(245, 430), false)
	var box := _card_vbox(card)
	box.add_child(_card_title("Tutorial"))
	box.add_child(_card_art("T", Color(0.19, 0.43, 0.73), false))
	var status: String = "Completed" if GameState.is_tutorial_completed() else "Unlocked"
	box.add_child(_card_subtitle(status))
	var start_button := _small_button("Start", Callable(GameState, "start_tutorial"), true)
	box.add_child(start_button)
	return card


func _level_boss_card(index: int, level_data: Dictionary) -> Control:
	var card := _card_base(Vector2(230, 430), false)
	var box := _card_vbox(card)
	var number := int(level_data.get("number", index + 1))
	var title := String(level_data.get("title", "Level"))
	box.add_child(_card_title("Level %d" % number))
	box.add_child(_card_art("%d" % number, Color(0.18, 0.18, 0.28), not GameState.is_level_unlocked(index)))

	var level_id := String(level_data.get("id", ""))
	var level_unlocked := GameState.is_level_unlocked(index)
	var boss_unlocked := GameState.is_boss_unlocked(index)
	box.add_child(_card_subtitle(title))

	var level_button := _small_button("Level %d" % number, Callable(self, "_start_level").bind(level_id), level_unlocked)
	var boss_button := _small_button("Boss %d" % number, Callable(self, "_start_boss").bind(level_id), boss_unlocked)
	box.add_child(level_button)
	box.add_child(boss_button)
	if GameState.is_level_completed(level_id):
		box.add_child(_card_subtitle("Level completed"))
	if GameState.is_boss_completed(level_id):
		box.add_child(_card_subtitle("Boss defeated"))
	return card


func _save_card(index: int, slot: Dictionary) -> Control:
	var card := _card_base(Vector2(215, 430), index == GameState.active_save_slot)
	var box := _card_vbox(card)
	var empty := bool(slot.get("empty", true))
	var save_title := "Empty"
	if not empty:
		save_title = "Save %d" % [index + 1]
	box.add_child(_card_title(save_title))
	box.add_child(_card_art("%d" % [index + 1], Color(0.2, 0.29, 0.38), empty))
	if empty:
		box.add_child(_card_subtitle("New save"))
	else:
		box.add_child(_card_subtitle("Progress %d%%" % int(slot.get("progress_percent", 0))))
		var stage: Dictionary = slot.get("current_stage", {})
		box.add_child(_card_subtitle(_stage_title(stage)))
	var button_text: String = "Create" if empty else "Select"
	box.add_child(_small_button(button_text, Callable(self, "_select_save").bind(index), true))
	if not empty:
		box.add_child(_small_button("Delete", Callable(self, "_delete_save").bind(index), true))
	return card


func _settings_volume_row() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 20)
	row.add_child(_settings_label("Sound"))
	_volume_slider = HSlider.new()
	_volume_slider.min_value = 0.0
	_volume_slider.max_value = 1.0
	_volume_slider.step = 0.01
	_volume_slider.value = float(GameState.settings.get("volume", 0.85))
	_volume_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(_volume_slider)
	return row


func _settings_mode_row() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	row.add_child(_settings_label("Task Mode"))
	_mode_buttons.clear()
	var patterns_button: Button = _toggle_button("Patterns", GameState.get_generation_mode() == "patterns")
	var ai_button: Button = _toggle_button("AI Generation", GameState.get_generation_mode() == "ai")
	_mode_buttons["patterns"] = patterns_button
	_mode_buttons["ai"] = ai_button
	row.add_child(patterns_button)
	row.add_child(ai_button)
	patterns_button.pressed.connect(Callable(self, "_select_mode").bind("patterns"))
	ai_button.pressed.connect(Callable(self, "_select_mode").bind("ai"))
	return row


func _settings_difficulty_row() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	row.add_child(_settings_label("Starting Difficulty"))
	_difficulty_buttons.clear()
	var difficulty_titles: Dictionary = {
		"easy": "Easy",
		"normal": "Normal",
		"hard": "Hard"
	}
	for difficulty in ["easy", "normal", "hard"]:
		var text: String = String(difficulty_titles.get(difficulty, difficulty))
		var difficulty_button: Button = _toggle_button(text, GameState.get_initial_difficulty() == difficulty)
		_difficulty_buttons[difficulty] = difficulty_button
		row.add_child(difficulty_button)
		difficulty_button.pressed.connect(Callable(self, "_select_difficulty").bind(difficulty))
	return row


func _settings_key_row() -> Control:
	var row := VBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.add_child(_settings_label("Hugging Face API Key"))
	_api_key_edit = LineEdit.new()
	_api_key_edit.placeholder_text = "hf_xxxxxxxxxxxxxxx"
	_api_key_edit.secret = true
	_api_key_edit.text = GameState.get_hf_api_key()
	_api_key_edit.custom_minimum_size = Vector2(760, 42)
	row.add_child(_api_key_edit)
	var hint := Label.new()
	hint.text = "The built-in key is used by default. If it is unavailable, the player can paste their own key."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	hint.add_theme_color_override("font_color", Color(0.86, 0.78, 0.62))
	row.add_child(hint)
	return row


func _settings_logs_row() -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 18)
	row.add_child(_settings_label("Player Logs"))
	row.add_child(_small_button("Export Excel", Callable(self, "_export_player_logs"), true))
	_export_status_label = Label.new()
	_export_status_label.text = "The Excel file will be saved to Downloads."
	_export_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_export_status_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_export_status_label.add_theme_font_size_override("font_size", 18)
	_export_status_label.add_theme_color_override("font_color", Color(0.86, 0.78, 0.62))
	row.add_child(_export_status_label)
	return row


func _add_header(title_text: String, subtitle: String) -> void:
	var header := VBoxContainer.new()
	header.anchor_left = 0.22
	header.anchor_top = 0.04
	header.anchor_right = 0.82
	header.anchor_bottom = 0.2
	header.alignment = BoxContainer.ALIGNMENT_CENTER
	_content.add_child(header)
	header.add_child(_title_label(title_text))
	var sub := Label.new()
	sub.text = subtitle
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.add_theme_font_size_override("font_size", 24)
	sub.add_theme_color_override("font_color", Color(1.0, 0.82, 0.38))
	header.add_child(sub)


func _add_top_button(text: String, action: Callable, right_side: bool) -> void:
	var button := _small_button(text, action, true)
	button.anchor_top = 0.04
	button.anchor_bottom = 0.12
	if right_side:
		button.anchor_left = 0.82
		button.anchor_right = 0.97
	else:
		button.anchor_left = 0.02
		button.anchor_right = 0.17
	_content.add_child(button)


func _add_scroll_arrows(left_action: Callable, right_action: Callable, top_right: bool = false) -> void:
	var arrows := HBoxContainer.new()
	if top_right:
		arrows.anchor_left = 0.8
		arrows.anchor_top = 0.14
		arrows.anchor_right = 0.95
		arrows.anchor_bottom = 0.22
	else:
		arrows.anchor_left = 0.43
		arrows.anchor_top = 0.9
		arrows.anchor_right = 0.57
		arrows.anchor_bottom = 0.98
	arrows.alignment = BoxContainer.ALIGNMENT_CENTER
	var arrow_separation := 28
	if top_right:
		arrow_separation = 14
	arrows.add_theme_constant_override("separation", arrow_separation)
	_content.add_child(arrows)
	arrows.add_child(_arrow_button("←", left_action))
	arrows.add_child(_arrow_button("→", right_action))


func _menu_button(text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(520, 88)
	button.add_theme_font_size_override("font_size", 40)
	button.add_theme_stylebox_override("normal", _button_style(false))
	button.add_theme_stylebox_override("hover", _button_style(true))
	button.add_theme_stylebox_override("pressed", _button_style(true))
	button.add_theme_color_override("font_color", Color(1.0, 0.86, 0.42))
	button.pressed.connect(action)
	return button


func _small_button(text: String, action: Callable, enabled: bool) -> Button:
	var button := Button.new()
	button.text = text
	button.disabled = not enabled
	button.custom_minimum_size = Vector2(126, 44)
	button.add_theme_font_size_override("font_size", 21)
	button.add_theme_stylebox_override("normal", _button_style(false))
	button.add_theme_stylebox_override("hover", _button_style(true))
	button.add_theme_stylebox_override("pressed", _button_style(true))
	button.add_theme_stylebox_override("disabled", _panel_style(Color(0.04, 0.04, 0.05, 0.62), 1))
	button.add_theme_color_override("font_color", Color(1.0, 0.86, 0.42))
	if enabled:
		button.pressed.connect(action)
	return button


func _arrow_button(text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(66, 44)
	button.add_theme_font_size_override("font_size", 24)
	button.add_theme_stylebox_override("normal", _button_style(false))
	button.add_theme_stylebox_override("hover", _button_style(true))
	button.add_theme_stylebox_override("pressed", _button_style(true))
	button.add_theme_color_override("font_color", Color(1.0, 0.86, 0.42))
	button.pressed.connect(action)
	return button


func _toggle_button(text: String, selected: bool) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(170, 54)
	button.add_theme_font_size_override("font_size", 22)
	button.add_theme_stylebox_override("normal", _button_style(selected))
	button.add_theme_stylebox_override("hover", _button_style(true))
	button.add_theme_color_override("font_color", Color(1.0, 0.86, 0.42))
	return button


func _title_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 64)
	label.add_theme_color_override("font_color", Color(1.0, 0.76, 0.25))
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.95))
	label.add_theme_constant_override("shadow_offset_x", 3)
	label.add_theme_constant_override("shadow_offset_y", 3)
	return label


func _settings_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(260, 42)
	label.add_theme_font_size_override("font_size", 24)
	label.add_theme_color_override("font_color", Color(1.0, 0.86, 0.42))
	return label


func _card_base(card_size: Vector2, highlighted: bool) -> PanelContainer:
	var card := PanelContainer.new()
	card.custom_minimum_size = card_size
	card.add_theme_stylebox_override("panel", _panel_style(Color(0.025, 0.025, 0.05, 0.88), 3 if highlighted else 2, highlighted))
	return card


func _card_vbox(card: PanelContainer) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 12)
	card.add_child(box)
	return box


func _card_title(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 30)
	label.add_theme_color_override("font_color", Color(1.0, 0.82, 0.35))
	return label


func _card_subtitle(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD
	label.add_theme_font_size_override("font_size", 21)
	label.add_theme_color_override("font_color", Color(0.95, 0.85, 0.65))
	return label


func _card_art(symbol: String, tint: Color, locked: bool) -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(175, 190)
	panel.add_theme_stylebox_override("panel", _panel_style(tint.darkened(0.2), 1))
	var label := Label.new()
	if locked:
		label.text = "LOCK"
	else:
		label.text = symbol
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override("font_size", 72)
	label.add_theme_color_override("font_color", Color(0.93, 0.82, 0.58))
	panel.add_child(label)
	return panel


func _inventory_slot(title: String, locked: bool) -> Button:
	var button := Button.new()
	if locked:
		button.text = "Empty"
	else:
		button.text = "Hint\n%s" % title
	button.custom_minimum_size = Vector2(140, 150)
	button.add_theme_font_size_override("font_size", 22)
	button.add_theme_stylebox_override("normal", _button_style(false))
	button.add_theme_stylebox_override("hover", _button_style(true))
	button.add_theme_color_override("font_color", Color(1.0, 0.86, 0.42))
	return button


func _inventory_description(items: Array) -> String:
	if items.is_empty():
		return "[b]Description:[/b]\nNo chests have been opened yet.\n\nCollected hints will be stored here."
	var index := clampi(_selected_inventory_index, 0, items.size() - 1)
	var item: Dictionary = items[index]
	return "[b]%s[/b]\n\n%s" % [String(item.get("title", "Hint")), String(item.get("description", ""))]


func _button_style(active: bool) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.03, 0.04, 0.09, 0.94) if not active else Color(0.04, 0.18, 0.36, 0.96)
	style.border_color = Color(1.0, 0.52, 0.1) if not active else Color(0.2, 0.78, 1.0)
	style.set_border_width_all(3)
	style.corner_radius_top_left = 8
	style.corner_radius_top_right = 8
	style.corner_radius_bottom_left = 8
	style.corner_radius_bottom_right = 8
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	return style


func _panel_style(color: Color, border_width: int, highlighted: bool = false) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = Color(0.2, 0.78, 1.0) if highlighted else Color(0.95, 0.48, 0.1)
	style.set_border_width_all(border_width)
	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 10
	style.corner_radius_bottom_left = 10
	style.corner_radius_bottom_right = 10
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 16
	style.content_margin_bottom = 16
	return style


func _start_level(level_id: String) -> void:
	GameState.start_level(level_id)


func _start_boss(level_id: String) -> void:
	GameState.start_boss(level_id)


func _select_save(index: int) -> void:
	GameState.select_save_slot(index)
	_show_saves()


func _delete_save(index: int) -> void:
	GameState.delete_save_slot(index)
	_show_saves()


func _scroll_play(direction: int) -> void:
	_scroll_container(_play_scroll, direction)


func _scroll_saves(direction: int) -> void:
	_scroll_container(_saves_scroll, direction)


func _scroll_container(scroll: ScrollContainer, direction: int) -> void:
	if scroll == null:
		return
	var target_scroll: int = int(scroll.scroll_horizontal) + direction * 320
	scroll.scroll_horizontal = maxi(target_scroll, 0)


func _select_inventory_item(index: int) -> void:
	_selected_inventory_index = index
	_show_inventory()


func _select_mode(mode: String) -> void:
	GameState.set_generation_mode(mode)
	_show_settings()


func _select_difficulty(difficulty: String) -> void:
	GameState.set_difficulty(difficulty)
	_show_settings()


func _apply_settings() -> void:
	GameState.set_volume(float(_volume_slider.value))
	GameState.set_hf_api_key(_api_key_edit.text)
	_show_settings()


func _reset_settings() -> void:
	GameState.reset_settings()
	_show_settings()


func _export_player_logs() -> void:
	if _export_status_label != null:
		_export_status_label.text = "Preparing Excel file..."
	GameState.log_event("settings_export_logs_requested")
	CodeApiClient.export_logs_to_downloads()


func _on_logs_export_received(file_path: String) -> void:
	if _current_view != VIEW_SETTINGS:
		return
	if _export_status_label != null:
		_export_status_label.text = "Done: %s" % file_path
	GameState.log_event("settings_export_logs_completed", {"file_path": file_path})


func _on_logs_export_failed(message: String) -> void:
	if _current_view != VIEW_SETTINGS:
		return
	if _export_status_label != null:
		_export_status_label.text = "Could not export logs: %s" % message
	GameState.log_event("settings_export_logs_failed", {"message": message})


func _stage_title(stage: Dictionary) -> String:
	var stage_type := String(stage.get("type", "tutorial"))
	var level_id := String(stage.get("level_id", ""))
	if stage_type == "tutorial":
		return "Tutorial"
	var level_data := GameState.get_level_by_id(level_id)
	var number := int(level_data.get("number", 1))
	if stage_type == "boss":
		return "Boss %d" % number
	if stage_type == "complete":
		return "Game completed"
	return "Level %d" % number


func _quit_game() -> void:
	get_tree().quit()

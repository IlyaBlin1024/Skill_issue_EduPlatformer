extends Control

const VIEW_MAIN := "main"
const VIEW_PLAY := "play"
const VIEW_SAVES := "saves"
const VIEW_SETTINGS := "settings"
const VIEW_INVENTORY := "inventory"
const VIEW_ADMIN := "admin"
const GOLD := Color(1.0, 0.76, 0.24)
const GOLD_SOFT := Color(1.0, 0.86, 0.46)
const ORANGE_BORDER := Color(1.0, 0.46, 0.06)
const BLUE_ACTIVE := Color(0.14, 0.72, 1.0)
const INK := Color(0.018, 0.021, 0.04, 0.94)
const MENU_ASSET_ROOT := "res://assets/generated_menu/"
const MENU_BACKGROUND_PATH := MENU_ASSET_ROOT + "backgrounds/main_menu_background.png"
const BUTTON_SMALL_IDLE := MENU_ASSET_ROOT + "buttons/button_small_idle.png"
const BUTTON_SMALL_SELECTED := MENU_ASSET_ROOT + "buttons/button_small_selected.png"
const CARD_LARGE_IDLE := MENU_ASSET_ROOT + "cards/card_large_idle.png"
const CARD_LARGE_SELECTED := MENU_ASSET_ROOT + "cards/card_large_selected.png"
const CARD_LARGE_LOCKED := MENU_ASSET_ROOT + "cards/card_large_locked.png"
const SAVE_CARD_IDLE := MENU_ASSET_ROOT + "cards/save_card_idle.png"
const SAVE_CARD_SELECTED := MENU_ASSET_ROOT + "cards/save_card_selected.png"
const INVENTORY_SLOT_IDLE := MENU_ASSET_ROOT + "cards/inventory_slot_idle.png"
const INVENTORY_SLOT_SELECTED := MENU_ASSET_ROOT + "cards/inventory_slot_selected.png"
const PANEL_SETTINGS := MENU_ASSET_ROOT + "cards/panel_settings.png"
const MENU_FADE_DURATION := 0.5

var _content: Control
var _fade_rect: ColorRect
var _fade_tween: Tween
var _transition_busy := false
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
var _settings_status_label: Label
var _admin_status_label: Label
var _pending_generation_mode := ""
var _pending_difficulty := ""
var _last_local_export_path := ""
var _menu_font: Font
var _texture_cache: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().paused = false
	GameState.load_all()
	_load_menu_font()
	if not CodeApiClient.logs_export_received.is_connected(_on_logs_export_received):
		CodeApiClient.logs_export_received.connect(_on_logs_export_received)
	if not CodeApiClient.logs_export_failed.is_connected(_on_logs_export_failed):
		CodeApiClient.logs_export_failed.connect(_on_logs_export_failed)
	_build_shell()
	_show_main()
	if _fade_rect != null:
		_fade_rect.visible = true
		_fade_rect.color = Color(0, 0, 0, 1)
		call_deferred("_fade_to", 0.0, MENU_FADE_DURATION)


func _build_shell() -> void:
	var background_texture := _menu_texture(MENU_BACKGROUND_PATH)
	if background_texture != null:
		var background := TextureRect.new()
		background.texture = background_texture
		background.set_anchors_preset(Control.PRESET_FULL_RECT)
		background.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		background.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		background.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(background)
		_add_rect(self, 0.0, 0.0, 1.0, 1.0, Color(0.0, 0.0, 0.0, 0.18))
		_content = Control.new()
		_content.set_anchors_preset(Control.PRESET_FULL_RECT)
		add_child(_content)
		_ensure_fade_layer()
		return
	_add_rect(self, 0.0, 0.0, 1.0, 1.0, Color(0.035, 0.018, 0.07))
	_add_rect(self, 0.0, 0.0, 1.0, 0.48, Color(0.12, 0.055, 0.22, 0.92))
	_add_rect(self, 0.0, 0.42, 1.0, 1.0, Color(0.03, 0.05, 0.1, 0.9))
	_add_rect(self, 0.44, 0.22, 0.92, 0.76, Color(1.0, 0.35, 0.1, 0.18))
	_add_rect(self, 0.0, 0.63, 1.0, 0.72, Color(0.22, 0.12, 0.22, 0.32))
	_add_rect(self, 0.0, 0.72, 1.0, 0.78, Color(0.9, 0.36, 0.12, 0.12))

	_add_castle_silhouette()
	_add_left_forest_silhouette()
	_add_star_field()
	_add_rect(self, 0.0, 0.0, 0.12, 1.0, Color(0.0, 0.0, 0.0, 0.32))
	_add_rect(self, 0.88, 0.0, 1.0, 1.0, Color(0.0, 0.0, 0.0, 0.24))
	_add_rect(self, 0.0, 0.0, 1.0, 1.0, Color(0.0, 0.0, 0.0, 0.16))

	_content = Control.new()
	_content.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(_content)
	_ensure_fade_layer()


func _clear_content() -> void:
	for child in _content.get_children():
		child.queue_free()


func _ensure_fade_layer() -> void:
	if _fade_rect != null:
		return
	_fade_rect = ColorRect.new()
	_fade_rect.color = Color(0, 0, 0, 0)
	_fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	_fade_rect.visible = false
	add_child(_fade_rect)


func _run_with_fade(action: Callable) -> void:
	if _transition_busy:
		return
	_transition_busy = true
	await _fade_to(1.0, MENU_FADE_DURATION * 0.5)
	action.call()
	if not is_inside_tree():
		return
	await get_tree().process_frame
	if not is_inside_tree():
		return
	await _fade_to(0.0, MENU_FADE_DURATION * 0.5)
	_transition_busy = false


func _fade_to(alpha: float, duration: float) -> void:
	if _fade_rect == null:
		return
	if _fade_tween != null and _fade_tween.is_running():
		_fade_tween.kill()
	_fade_rect.visible = true
	_fade_tween = create_tween()
	_fade_tween.tween_property(_fade_rect, "color:a", alpha, duration)
	await _fade_tween.finished
	if alpha <= 0.0:
		_fade_rect.visible = false


func _add_rect(parent: Node, left: float, top: float, right: float, bottom: float, color: Color) -> ColorRect:
	var rect := ColorRect.new()
	rect.color = color
	rect.anchor_left = left
	rect.anchor_top = top
	rect.anchor_right = right
	rect.anchor_bottom = bottom
	parent.add_child(rect)
	return rect


func _add_castle_silhouette() -> void:
	_add_rect(self, 0.69, 0.32, 0.98, 1.0, Color(0.018, 0.018, 0.045, 0.78))
	_add_rect(self, 0.72, 0.22, 0.77, 1.0, Color(0.016, 0.016, 0.04, 0.86))
	_add_rect(self, 0.8, 0.16, 0.86, 1.0, Color(0.014, 0.014, 0.038, 0.9))
	_add_rect(self, 0.91, 0.26, 0.95, 1.0, Color(0.014, 0.014, 0.038, 0.84))
	for window_data in [[0.735, 0.38], [0.815, 0.31], [0.84, 0.48], [0.925, 0.42], [0.77, 0.56], [0.885, 0.61]]:
		_add_rect(self, float(window_data[0]), float(window_data[1]), float(window_data[0]) + 0.01, float(window_data[1]) + 0.025, Color(1.0, 0.45, 0.1, 0.46))


func _add_left_forest_silhouette() -> void:
	_add_rect(self, 0.0, 0.0, 0.18, 1.0, Color(0.006, 0.014, 0.02, 0.74))
	for tree_data in [[0.02, 0.2, 0.06], [0.07, 0.12, 0.12], [0.13, 0.28, 0.17], [0.18, 0.38, 0.22]]:
		_add_rect(self, float(tree_data[0]), float(tree_data[1]), float(tree_data[2]), 1.0, Color(0.006, 0.018, 0.018, 0.62))


func _add_star_field() -> void:
	for star_data in [[0.3, 0.14], [0.38, 0.09], [0.47, 0.17], [0.59, 0.11], [0.66, 0.2], [0.52, 0.08]]:
		_add_rect(self, float(star_data[0]), float(star_data[1]), float(star_data[0]) + 0.004, float(star_data[1]) + 0.007, Color(1.0, 0.72, 0.35, 0.72))


func _show_main() -> void:
	_current_view = VIEW_MAIN
	GameState.log_event("menu_view_opened", {"view": VIEW_MAIN})
	_clear_content()
	var panel := VBoxContainer.new()
	panel.anchor_left = 0.17
	panel.anchor_top = 0.05
	panel.anchor_right = 0.5
	panel.anchor_bottom = 0.88
	panel.alignment = BoxContainer.ALIGNMENT_CENTER
	panel.add_theme_constant_override("separation", 4)
	_content.add_child(panel)

	var title := _title_label("Skill Issue")
	panel.add_child(title)
	panel.add_child(_menu_button("Play", Callable(self, "_show_play")))
	panel.add_child(_menu_button("Saves", Callable(self, "_show_saves")))
	panel.add_child(_menu_button("Settings", Callable(self, "_show_settings")))
	panel.add_child(_admin_toggle_button())
	if GameState.is_admin_mode_enabled():
		panel.add_child(_menu_button("Admin Panel", Callable(self, "_show_admin")))
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
	_play_scroll.anchor_top = 0.23
	_play_scroll.anchor_right = 0.94
	_play_scroll.anchor_bottom = 0.88
	_play_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
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
	_add_scroll_arrows(Callable(self, "_scroll_play").bind(-1), Callable(self, "_scroll_play").bind(1), true)


func _show_saves() -> void:
	_current_view = VIEW_SAVES
	GameState.log_event("menu_view_opened", {"view": VIEW_SAVES})
	_clear_content()
	_add_top_button("Back", Callable(self, "_show_main"), false)
	_add_header("Saves", "Choose a slot or create a new save")

	_saves_scroll = ScrollContainer.new()
	_saves_scroll.anchor_left = 0.08
	_saves_scroll.anchor_top = 0.21
	_saves_scroll.anchor_right = 0.95
	_saves_scroll.anchor_bottom = 0.87
	_saves_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
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
	_pending_generation_mode = GameState.get_generation_mode()
	_pending_difficulty = GameState.get_initial_difficulty()
	GameState.log_event("menu_view_opened", {"view": VIEW_SETTINGS})
	_clear_content()
	_add_top_button("Back", Callable(self, "_show_main"), false)
	_add_header("Settings", "Local settings are saved separately from progress")

	var panel_frame := PanelContainer.new()
	panel_frame.anchor_left = 0.1
	panel_frame.anchor_top = 0.18
	panel_frame.anchor_right = 0.9
	panel_frame.anchor_bottom = 0.94
	panel_frame.add_theme_stylebox_override("panel", _panel_style(Color(0.025, 0.025, 0.045, 0.86), 3, false, PANEL_SETTINGS))
	_content.add_child(panel_frame)

	var panel_margin := MarginContainer.new()
	panel_margin.add_theme_constant_override("margin_left", 62)
	panel_margin.add_theme_constant_override("margin_right", 62)
	panel_margin.add_theme_constant_override("margin_top", 48)
	panel_margin.add_theme_constant_override("margin_bottom", 44)
	panel_frame.add_child(panel_margin)

	var panel := VBoxContainer.new()
	panel.add_theme_constant_override("separation", 12)
	panel_margin.add_child(panel)

	panel.add_child(_settings_volume_row())
	panel.add_child(_settings_mode_row())
	panel.add_child(_settings_difficulty_row())
	panel.add_child(_settings_key_row())
	panel.add_child(_settings_logs_row())
	_settings_status_label = Label.new()
	_settings_status_label.text = ""
	_settings_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_settings_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_apply_menu_font(_settings_status_label, 14)
	_settings_status_label.add_theme_color_override("font_color", Color(0.9, 0.82, 0.62))
	panel.add_child(_settings_status_label)

	var actions := HBoxContainer.new()
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_theme_constant_override("separation", 28)
	panel.add_child(actions)
	actions.add_child(_small_button("Apply", Callable(self, "_apply_settings"), true))
	actions.add_child(_small_button("Defaults", Callable(self, "_reset_settings"), false))


func _show_admin() -> void:
	_current_view = VIEW_ADMIN
	GameState.log_event("menu_view_opened", {"view": VIEW_ADMIN})
	_clear_content()
	_add_top_button("Back", Callable(self, "_show_main"), false)
	_add_header("Admin Panel", "Tools for testing, balancing, and quick administration")

	var panel_frame := PanelContainer.new()
	panel_frame.anchor_left = 0.1
	panel_frame.anchor_top = 0.2
	panel_frame.anchor_right = 0.9
	panel_frame.anchor_bottom = 0.92
	panel_frame.add_theme_stylebox_override("panel", _panel_style(Color(0.025, 0.025, 0.045, 0.9), 3, true, PANEL_SETTINGS))
	_content.add_child(panel_frame)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 58)
	margin.add_theme_constant_override("margin_right", 58)
	margin.add_theme_constant_override("margin_top", 46)
	margin.add_theme_constant_override("margin_bottom", 42)
	panel_frame.add_child(margin)

	var root := VBoxContainer.new()
	root.add_theme_constant_override("separation", 18)
	margin.add_child(root)

	var save_tools := HBoxContainer.new()
	save_tools.alignment = BoxContainer.ALIGNMENT_CENTER
	save_tools.add_theme_constant_override("separation", 16)
	root.add_child(save_tools)
	save_tools.add_child(_small_button("Unlock All", Callable(self, "_admin_unlock_all"), true))
	save_tools.add_child(_small_button("Complete Tutorial", Callable(self, "_admin_complete_tutorial"), true))
	save_tools.add_child(_small_button("Reset Save", Callable(self, "_admin_reset_save"), true))
	save_tools.add_child(_small_button("Export Logs", Callable(self, "_export_player_logs"), true))

	var launch_label := _settings_label("Quick Launch")
	launch_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(launch_label)

	var launch_grid := GridContainer.new()
	launch_grid.columns = 5
	launch_grid.add_theme_constant_override("h_separation", 12)
	launch_grid.add_theme_constant_override("v_separation", 12)
	root.add_child(launch_grid)
	var levels := GameState.get_levels()
	for level_variant in levels:
		var level_data: Dictionary = level_variant
		var level_id := String(level_data.get("id", ""))
		var number := int(level_data.get("number", 1))
		launch_grid.add_child(_small_button("Level %d" % number, Callable(self, "_admin_start_level").bind(level_id), true))
	for boss_variant in levels:
		var boss_data: Dictionary = boss_variant
		var boss_level_id := String(boss_data.get("id", ""))
		var boss_number := int(boss_data.get("number", 1))
		launch_grid.add_child(_small_button("Boss %d" % boss_number, Callable(self, "_admin_start_boss").bind(boss_level_id), true))

	_admin_status_label = Label.new()
	_admin_status_label.text = "Admin mode is local and saved in settings. Turn it off on the main screen for normal progression."
	_admin_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_admin_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_apply_menu_font(_admin_status_label, 15)
	_admin_status_label.add_theme_color_override("font_color", Color(0.9, 0.82, 0.62))
	root.add_child(_admin_status_label)


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
	_apply_menu_font(text, 18, true)
	text.add_theme_color_override("default_color", Color(1.0, 0.88, 0.5))
	description_panel.add_child(text)
	text.text = _inventory_description(items)


func _back_from_inventory() -> void:
	if _return_view == VIEW_PLAY:
		_show_play()
	else:
		_show_main()


func _tutorial_card() -> Control:
	var card := _card_base(Vector2(280, 480), false)
	var box := _card_vbox(card)
	box.add_child(_card_title("Tutorial"))
	box.add_child(_card_art("tutorial_art", Color(0.19, 0.43, 0.73), false))
	var status: String = "Completed" if GameState.is_tutorial_completed() else "Unlocked"
	box.add_child(_card_subtitle(status))
	var start_button := _card_button("Start", Callable(GameState, "start_tutorial"), true, true)
	box.add_child(start_button)
	return card


func _level_boss_card(index: int, level_data: Dictionary) -> Control:
	var number := int(level_data.get("number", index + 1))
	var admin_mode := GameState.is_admin_mode_enabled()
	var level_unlocked := admin_mode or GameState.is_level_unlocked(index)
	var boss_unlocked := admin_mode or GameState.is_boss_unlocked(index)
	var level_id := String(level_data.get("id", ""))
	var card := _card_base(Vector2(280, 480), false, not level_unlocked)
	var box := _card_vbox(card)
	var title := String(level_data.get("title", "Level"))
	box.add_child(_card_title("Level %d" % number))
	var preview_key := _level_art_key(number)
	if GameState.is_level_completed(level_id):
		preview_key = _boss_art_key(number)
	box.add_child(_card_art(preview_key, Color(0.16, 0.24, 0.38), false))

	box.add_child(_card_subtitle(title))

	var level_button := _card_button("Level %d" % number, Callable(self, "_start_level").bind(level_id), level_unlocked, true)
	var boss_button := _card_button("Boss %d" % number, Callable(self, "_start_boss").bind(level_id), boss_unlocked, true)
	box.add_child(level_button)
	box.add_child(boss_button)
	return card


func _save_card(index: int, slot: Dictionary) -> Control:
	var card := _card_base(Vector2(280, 480), index == GameState.active_save_slot, false, true)
	var box := _card_vbox(card)
	var empty := bool(slot.get("empty", true))
	var save_title := "Empty"
	if not empty:
		save_title = "Save %d" % [index + 1]
	box.add_child(_card_title(save_title))
	box.add_child(_card_art(_save_art_key(slot), Color(0.2, 0.29, 0.38), empty))
	if empty:
		box.add_child(_card_subtitle("New save"))
	else:
		box.add_child(_card_subtitle("Progress %d%%" % int(slot.get("progress_percent", 0))))
		var stage: Dictionary = slot.get("current_stage", {})
		box.add_child(_card_subtitle(_stage_title(stage)))
	var button_text: String = "Create" if empty else "Select"
	box.add_child(_card_button(button_text, Callable(self, "_select_save").bind(index), true))
	if not empty:
		box.add_child(_card_button("Delete", Callable(self, "_delete_save").bind(index), true))
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
	var patterns_button: Button = _toggle_button("Patterns", _pending_generation_mode == "patterns")
	var ai_button: Button = _toggle_button("AI Generation", _pending_generation_mode == "ai")
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
		var difficulty_button: Button = _toggle_button(text, _pending_difficulty == difficulty)
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
	_api_key_edit.custom_minimum_size = Vector2(680, 38)
	row.add_child(_api_key_edit)
	var hint := Label.new()
	hint.text = "Paste your Hugging Face key here to enable AI generation. If the key is empty, tasks use local patterns."
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	hint.add_theme_color_override("font_color", Color(0.86, 0.78, 0.62))
	_apply_menu_font(hint, 14)
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
	_apply_menu_font(_export_status_label, 14)
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
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD
	_apply_menu_font(sub, 20)
	sub.add_theme_color_override("font_color", Color(1.0, 0.82, 0.38))
	header.add_child(sub)


func _add_top_button(text: String, action: Callable, right_side: bool) -> void:
	var button := _small_button(text, Callable(self, "_run_with_fade").bind(action), true)
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
		arrows.anchor_left = 0.78
		arrows.anchor_top = 0.14
		arrows.anchor_right = 0.91
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
	button.custom_minimum_size = Vector2(350, 86)
	button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_apply_menu_font(button, 30)
	button.add_theme_stylebox_override("normal", _button_style(false, true))
	button.add_theme_stylebox_override("hover", _button_style(true, true))
	button.add_theme_stylebox_override("pressed", _button_style(true, true))
	button.add_theme_color_override("font_color", Color(1.0, 0.86, 0.42))
	button.pressed.connect(Callable(self, "_run_with_fade").bind(action))
	return button


func _admin_toggle_button() -> Button:
	var enabled := GameState.is_admin_mode_enabled()
	var button := Button.new()
	button.text = "Admin Mode: %s" % ("ON" if enabled else "OFF")
	button.custom_minimum_size = Vector2(350, 58)
	button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	_apply_menu_font(button, 18)
	button.add_theme_stylebox_override("normal", _button_style(enabled))
	button.add_theme_stylebox_override("hover", _button_style(true))
	button.add_theme_stylebox_override("pressed", _button_style(true))
	button.add_theme_color_override("font_color", Color(1.0, 0.86, 0.42))
	button.pressed.connect(Callable(self, "_toggle_admin_mode"))
	return button


func _small_button(text: String, action: Callable, enabled: bool) -> Button:
	var button := Button.new()
	button.text = text
	button.disabled = not enabled
	button.custom_minimum_size = Vector2(190, 58)
	button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_apply_menu_font(button, 17)
	button.add_theme_stylebox_override("normal", _button_style(false))
	button.add_theme_stylebox_override("hover", _button_style(true))
	button.add_theme_stylebox_override("pressed", _button_style(true))
	button.add_theme_stylebox_override("disabled", _button_style(false))
	button.add_theme_color_override("font_color", Color(1.0, 0.86, 0.42))
	button.add_theme_color_override("font_disabled_color", Color(0.55, 0.5, 0.42))
	if enabled:
		button.pressed.connect(action)
	return button


func _card_button(text: String, action: Callable, enabled: bool, fade_action: bool = false) -> Button:
	var final_action: Callable = Callable(self, "_run_with_fade").bind(action) if fade_action else action
	var button := _small_button(text, final_action, enabled)
	button.custom_minimum_size = Vector2(190, 46)
	_apply_menu_font(button, 16)
	return button


func _arrow_button(text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(78, 54)
	_apply_menu_font(button, 18)
	button.add_theme_stylebox_override("normal", _button_style(false))
	button.add_theme_stylebox_override("hover", _button_style(true))
	button.add_theme_stylebox_override("pressed", _button_style(true))
	button.add_theme_color_override("font_color", Color(1.0, 0.86, 0.42))
	button.pressed.connect(action)
	return button


func _toggle_button(text: String, selected: bool) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(190, 58)
	button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_apply_menu_font(button, 17)
	_set_toggle_button_selected(button, selected)
	button.add_theme_color_override("font_color", Color(1.0, 0.86, 0.42))
	return button


func _set_toggle_button_selected(button: Button, selected: bool) -> void:
	button.add_theme_stylebox_override("normal", _button_style(selected))
	button.add_theme_stylebox_override("hover", _button_style(true))
	button.add_theme_stylebox_override("pressed", _button_style(true))


func _title_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_apply_menu_font(label, 54)
	label.add_theme_color_override("font_color", Color(1.0, 0.76, 0.25))
	label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.95))
	label.add_theme_constant_override("shadow_offset_x", 3)
	label.add_theme_constant_override("shadow_offset_y", 3)
	return label


func _settings_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(220, 34)
	_apply_menu_font(label, 18)
	label.add_theme_color_override("font_color", Color(1.0, 0.86, 0.42))
	return label


func _card_base(card_size: Vector2, highlighted: bool, locked: bool = false, save_card: bool = false) -> PanelContainer:
	var card := PanelContainer.new()
	card.custom_minimum_size = card_size
	var texture_path := CARD_LARGE_IDLE
	if save_card:
		texture_path = SAVE_CARD_SELECTED if highlighted else SAVE_CARD_IDLE
	elif locked:
		texture_path = CARD_LARGE_LOCKED
	elif highlighted:
		texture_path = CARD_LARGE_SELECTED
	card.add_theme_stylebox_override("panel", _panel_style(Color(0.025, 0.025, 0.05, 0.88), 3 if highlighted else 2, highlighted, texture_path))
	return card


func _card_vbox(card: PanelContainer) -> VBoxContainer:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 38)
	margin.add_theme_constant_override("margin_right", 38)
	margin.add_theme_constant_override("margin_top", 54)
	margin.add_theme_constant_override("margin_bottom", 56)
	card.add_child(margin)
	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 5)
	margin.add_child(box)
	return box


func _card_title(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(190, 28)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_apply_menu_font(label, 22)
	label.add_theme_color_override("font_color", Color(1.0, 0.82, 0.35))
	return label


func _card_subtitle(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(190, 22)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD
	_apply_menu_font(label, 15)
	label.add_theme_color_override("font_color", Color(0.95, 0.85, 0.65))
	return label


func _card_art(symbol: String, tint: Color, locked: bool) -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(188, 176)
	panel.add_theme_stylebox_override("panel", _panel_style(tint.darkened(0.2), 1, false, INVENTORY_SLOT_IDLE))
	var stack := Control.new()
	stack.custom_minimum_size = Vector2(188, 176)
	panel.add_child(stack)
	var texture := _menu_texture(_card_art_path(symbol))
	if texture != null:
		var art := TextureRect.new()
		art.texture = texture
		art.set_anchors_preset(Control.PRESET_FULL_RECT)
		art.offset_left = 24
		art.offset_top = 24
		art.offset_right = -24
		art.offset_bottom = -24
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stack.add_child(art)
	else:
		stack.add_child(_fallback_art_label(symbol))
	if locked:
		_add_lock_overlay(stack)
	return panel


func _level_boss_art(number: int, level_locked: bool, boss_locked: bool) -> Control:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 6)
	row.custom_minimum_size = Vector2(166, 126)
	row.add_child(_mini_stage_art(_level_art_key(number), level_locked))
	row.add_child(_mini_stage_art(_boss_art_key(number), boss_locked))
	return row


func _mini_stage_art(art_key: String, locked: bool) -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(78, 122)
	panel.add_theme_stylebox_override("panel", _panel_style(Color(0.02, 0.02, 0.04, 0.9), 1, false, INVENTORY_SLOT_IDLE))
	var stack := Control.new()
	panel.add_child(stack)
	var texture := _menu_texture(_card_art_path(art_key))
	if texture != null:
		var art := TextureRect.new()
		art.texture = texture
		art.set_anchors_preset(Control.PRESET_FULL_RECT)
		art.offset_left = 5
		art.offset_top = 5
		art.offset_right = -5
		art.offset_bottom = -5
		art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
		art.mouse_filter = Control.MOUSE_FILTER_IGNORE
		stack.add_child(art)
	else:
		stack.add_child(_fallback_art_label("?"))
	if locked:
		_add_lock_overlay(stack)
	return panel


func _fallback_art_label(symbol: String) -> Label:
	var label := Label.new()
	label.text = "LOCK" if symbol == "locked" else symbol
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_color_override("font_color", Color(0.93, 0.82, 0.58))
	_apply_menu_font(label, 26)
	return label


func _add_lock_overlay(parent: Control) -> void:
	var shade := ColorRect.new()
	shade.color = Color(0.0, 0.0, 0.0, 0.62)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	parent.add_child(shade)
	parent.add_child(_fallback_art_label("locked"))


func _inventory_slot(title: String, locked: bool) -> Button:
	var button := Button.new()
	if locked:
		button.text = "Empty"
	else:
		button.text = "Hint\n%s" % title
	button.custom_minimum_size = Vector2(130, 135)
	button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_apply_menu_font(button, 16)
	button.add_theme_stylebox_override("normal", _panel_style(Color(0.025, 0.025, 0.05, 0.88), 2, false, INVENTORY_SLOT_IDLE))
	button.add_theme_stylebox_override("hover", _panel_style(Color(0.025, 0.025, 0.05, 0.88), 2, true, INVENTORY_SLOT_SELECTED))
	button.add_theme_color_override("font_color", Color(1.0, 0.86, 0.42))
	return button


func _inventory_description(items: Array) -> String:
	if items.is_empty():
		return "[b]Description:[/b]\nNo chests have been opened yet.\n\nCollected hints will be stored here."
	var index := clampi(_selected_inventory_index, 0, items.size() - 1)
	var item: Dictionary = items[index]
	return "[b]%s[/b]\n\n%s" % [String(item.get("title", "Hint")), String(item.get("description", ""))]


func _load_menu_font() -> void:
	# The generated bitmap font has very wide advance metrics. Regular UI keeps
	# Godot's readable font until we replace it with a production-ready atlas.
	_menu_font = null


func _apply_menu_font(control: Control, size: int, rich_text: bool = false) -> void:
	if rich_text:
		control.add_theme_font_size_override("normal_font_size", size)
		if _menu_font != null:
			control.add_theme_font_override("normal_font", _menu_font)
		return
	control.add_theme_font_size_override("font_size", size)
	if _menu_font != null:
		control.add_theme_font_override("font", _menu_font)


func _menu_texture(path: String) -> Texture2D:
	if _texture_cache.has(path):
		return _texture_cache[path]
	var texture: Texture2D = null
	if ResourceLoader.exists(path):
		texture = load(path) as Texture2D
	_texture_cache[path] = texture
	return texture


func _texture_style(path: String, margin: int, modulate: Color = Color.WHITE) -> StyleBoxTexture:
	var texture := _menu_texture(path)
	if texture == null:
		return null
	var style := StyleBoxTexture.new()
	style.texture = texture
	style.texture_margin_left = margin
	style.texture_margin_top = margin
	style.texture_margin_right = margin
	style.texture_margin_bottom = margin
	style.content_margin_left = 26
	style.content_margin_right = 26
	style.content_margin_top = 18
	style.content_margin_bottom = 18
	style.modulate_color = modulate
	return style


func _level_art_key(number: int) -> String:
	match number:
		1:
			return "level_01_variables"
		2:
			return "level_02_if_else"
		3:
			return "level_03_loops"
		4:
			return "level_04_functions"
		5:
			return "level_05_integration"
	return "tutorial_art"


func _boss_art_key(number: int) -> String:
	return "boss_%02d" % clampi(number, 1, 5)


func _card_art_path(key: String) -> String:
	if key == "T":
		return MENU_ASSET_ROOT + "card_art/tutorial_art.png"
	if key.is_valid_int():
		return MENU_ASSET_ROOT + "card_art/%s.png" % _level_art_key(int(key))
	return MENU_ASSET_ROOT + "card_art/%s.png" % key


func _save_art_key(slot: Dictionary) -> String:
	if bool(slot.get("empty", true)):
		return "locked"
	var stage: Dictionary = slot.get("current_stage", {})
	var stage_type := String(stage.get("type", "tutorial"))
	if stage_type == "tutorial":
		return "tutorial_art"
	var level_data := GameState.get_level_by_id(String(stage.get("level_id", "")))
	var number := int(level_data.get("number", 1))
	if stage_type == "boss":
		return _boss_art_key(number)
	return _level_art_key(number)


func _button_style(active: bool, large: bool = false) -> StyleBox:
	var texture_path := BUTTON_SMALL_SELECTED if active else BUTTON_SMALL_IDLE
	var textured := _texture_style(texture_path, 0)
	if textured != null:
		return textured
	var style := StyleBoxFlat.new()
	style.bg_color = INK if not active else Color(0.035, 0.16, 0.34, 0.98)
	style.border_color = ORANGE_BORDER if not active else BLUE_ACTIVE
	style.set_border_width_all(4)
	style.corner_radius_top_left = 12
	style.corner_radius_top_right = 12
	style.corner_radius_bottom_left = 12
	style.corner_radius_bottom_right = 12
	style.content_margin_left = 22
	style.content_margin_right = 22
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	style.shadow_color = Color(0.0, 0.0, 0.0, 0.55)
	style.shadow_size = 7
	style.shadow_offset = Vector2(0, 5)
	return style


func _panel_style(color: Color, border_width: int, highlighted: bool = false, texture_path: String = "", modulate: Color = Color.WHITE) -> StyleBox:
	if not texture_path.is_empty():
		var texture_margin := 44
		if texture_path == INVENTORY_SLOT_IDLE or texture_path == INVENTORY_SLOT_SELECTED:
			texture_margin = 28
		elif texture_path == PANEL_SETTINGS:
			texture_margin = 58
		var textured := _texture_style(texture_path, texture_margin, modulate)
		if textured != null:
			return textured
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = BLUE_ACTIVE if highlighted else ORANGE_BORDER
	style.set_border_width_all(border_width)
	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 10
	style.corner_radius_bottom_left = 10
	style.corner_radius_bottom_right = 10
	style.content_margin_left = 18
	style.content_margin_right = 18
	style.content_margin_top = 16
	style.content_margin_bottom = 16
	style.shadow_color = Color(0, 0, 0, 0.42)
	style.shadow_size = 5
	style.shadow_offset = Vector2(0, 4)
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


func _toggle_admin_mode() -> void:
	GameState.set_admin_mode(not GameState.is_admin_mode_enabled())
	_show_main()


func _admin_unlock_all() -> void:
	GameState.admin_unlock_all_progress()
	if _admin_status_label != null:
		_admin_status_label.text = "All tutorial, level, and boss progress is unlocked for the active save."


func _admin_complete_tutorial() -> void:
	GameState.admin_complete_tutorial()
	if _admin_status_label != null:
		_admin_status_label.text = "Tutorial is marked as completed. Level 1 is now available."


func _admin_reset_save() -> void:
	GameState.admin_reset_active_save()
	if _admin_status_label != null:
		_admin_status_label.text = "Active save slot was reset."


func _admin_start_level(level_id: String) -> void:
	GameState.start_level(level_id)


func _admin_start_boss(level_id: String) -> void:
	GameState.start_boss(level_id)


func _select_mode(mode: String) -> void:
	_pending_generation_mode = mode if mode == "patterns" else "ai"
	_refresh_settings_toggles()
	_set_settings_status("Settings changed. Press Apply to save.")


func _select_difficulty(difficulty: String) -> void:
	if difficulty in ["easy", "normal", "hard"]:
		_pending_difficulty = difficulty
	_refresh_settings_toggles()
	_set_settings_status("Settings changed. Press Apply to save.")


func _apply_settings() -> void:
	if _pending_generation_mode.is_empty():
		_pending_generation_mode = GameState.get_generation_mode()
	if _pending_difficulty.is_empty():
		_pending_difficulty = GameState.get_initial_difficulty()
	var saved_key := ""
	if _api_key_edit != null:
		saved_key = _api_key_edit.text.strip_edges()
	if _volume_slider != null:
		GameState.set_volume(float(_volume_slider.value))
	GameState.set_generation_mode(_pending_generation_mode)
	GameState.set_difficulty(_pending_difficulty)
	GameState.set_hf_api_key(saved_key)
	_refresh_settings_toggles()
	if _pending_generation_mode == "ai":
		if saved_key.is_empty():
			_set_settings_status("Settings saved. Add a Hugging Face key before using AI generation.")
		else:
			_set_settings_status("Settings saved. Hugging Face key is active for AI requests.")
	else:
		_set_settings_status("Settings saved. Pattern mode is active.")


func _reset_settings() -> void:
	GameState.reset_settings()
	_show_settings()


func _refresh_settings_toggles() -> void:
	for mode in _mode_buttons.keys():
		var mode_button: Button = _mode_buttons[mode]
		_set_toggle_button_selected(mode_button, String(mode) == _pending_generation_mode)
	for difficulty in _difficulty_buttons.keys():
		var difficulty_button: Button = _difficulty_buttons[difficulty]
		_set_toggle_button_selected(difficulty_button, String(difficulty) == _pending_difficulty)


func _set_settings_status(text: String) -> void:
	if _settings_status_label != null:
		_settings_status_label.text = text


func _export_player_logs() -> void:
	if _export_status_label != null:
		_export_status_label.text = "Preparing Excel workbook..."
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
		if _last_local_export_path.is_empty():
			_export_status_label.text = "Could not export logs: %s" % message
		else:
			_export_status_label.text = "Downloaded local logs: %s\nExcel workbook is not available yet: %s" % [_last_local_export_path, message]
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

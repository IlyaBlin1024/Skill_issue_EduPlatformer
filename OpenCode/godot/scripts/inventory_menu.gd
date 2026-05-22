extends CanvasLayer

const MENU_ASSET_ROOT := "res://assets/generated_menu/"
const BUTTON_SMALL_IDLE := MENU_ASSET_ROOT + "buttons/button_small_idle.png"
const BUTTON_SMALL_SELECTED := MENU_ASSET_ROOT + "buttons/button_small_selected.png"
const INVENTORY_SLOT_IDLE := MENU_ASSET_ROOT + "cards/inventory_slot_idle.png"
const INVENTORY_SLOT_SELECTED := MENU_ASSET_ROOT + "cards/inventory_slot_selected.png"
const PANEL_SETTINGS := MENU_ASSET_ROOT + "cards/panel_settings.png"

var _selected_index := 0
var _description_label: RichTextLabel
var _menu_font: Font
var _texture_cache: Dictionary = {}


func _ready() -> void:
	layer = 185
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_menu_font()
	_build()
	visible = false


func toggle_inventory() -> void:
	if visible:
		close_inventory()
	else:
		open_inventory()


func open_inventory() -> void:
	_refresh_description()
	visible = true
	get_tree().paused = true


func close_inventory() -> void:
	visible = false
	get_tree().paused = false


func _build() -> void:
	var shade := ColorRect.new()
	shade.color = Color(0.0, 0.0, 0.0, 0.62)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(shade)

	var title := Label.new()
	title.text = "Inventory"
	title.anchor_left = 0.25
	title.anchor_top = 0.05
	title.anchor_right = 0.75
	title.anchor_bottom = 0.16
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_apply_menu_font(title, 44)
	title.add_theme_color_override("font_color", Color(1.0, 0.76, 0.25))
	add_child(title)

	var close_button := _button("Back", Callable(self, "close_inventory"))
	close_button.anchor_left = 0.03
	close_button.anchor_top = 0.05
	close_button.anchor_right = 0.17
	close_button.anchor_bottom = 0.13
	add_child(close_button)

	var grid := GridContainer.new()
	grid.columns = 4
	grid.anchor_left = 0.17
	grid.anchor_top = 0.22
	grid.anchor_right = 0.69
	grid.anchor_bottom = 0.72
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	add_child(grid)

	var items := GameState.get_inventory_items()
	for index in range(8):
		var title_text := "Empty"
		var locked := true
		if index < items.size():
			var item: Dictionary = items[index]
			title_text = String(item.get("title", "Hint %d" % [index + 1]))
			locked = false
		var slot := _slot_button(title_text, locked)
		slot.pressed.connect(Callable(self, "_select_item").bind(index))
		grid.add_child(slot)

	var panel := PanelContainer.new()
	panel.anchor_left = 0.22
	panel.anchor_top = 0.76
	panel.anchor_right = 0.78
	panel.anchor_bottom = 0.94
	panel.add_theme_stylebox_override("panel", _panel_style())
	add_child(panel)

	_description_label = RichTextLabel.new()
	_description_label.bbcode_enabled = true
	_description_label.fit_content = true
	_apply_menu_font(_description_label, 18, true)
	_description_label.add_theme_color_override("default_color", Color(1.0, 0.88, 0.5))
	panel.add_child(_description_label)


func _select_item(index: int) -> void:
	_selected_index = index
	_refresh_description()


func _refresh_description() -> void:
	if _description_label == null:
		return
	var items := GameState.get_inventory_items()
	if items.is_empty() or _selected_index >= items.size():
		_description_label.text = "[b]Description:[/b]\nNo chest hints yet."
		return
	var item: Dictionary = items[_selected_index]
	_description_label.text = "[b]%s[/b]\n%s" % [String(item.get("title", "Hint")), String(item.get("description", ""))]


func _button(text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_apply_menu_font(button, 18)
	button.add_theme_color_override("font_color", Color(1.0, 0.86, 0.42))
	button.add_theme_stylebox_override("normal", _button_style(false))
	button.add_theme_stylebox_override("hover", _button_style(true))
	button.pressed.connect(action)
	return button


func _slot_button(text: String, locked: bool) -> Button:
	var button := Button.new()
	if locked:
		button.text = "Empty"
	else:
		button.text = "Hint\n%s" % text
	button.custom_minimum_size = Vector2(130, 135)
	button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_apply_menu_font(button, 16)
	button.add_theme_color_override("font_color", Color(1.0, 0.86, 0.42))
	button.add_theme_stylebox_override("normal", _panel_style(INVENTORY_SLOT_IDLE))
	button.add_theme_stylebox_override("hover", _panel_style(INVENTORY_SLOT_SELECTED))
	return button


func _button_style(active: bool) -> StyleBox:
	var textured := _texture_style(BUTTON_SMALL_SELECTED if active else BUTTON_SMALL_IDLE, 16)
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


func _panel_style(texture_path: String = PANEL_SETTINGS) -> StyleBox:
	var textured_margin := 24
	if texture_path == INVENTORY_SLOT_IDLE or texture_path == INVENTORY_SLOT_SELECTED:
		textured_margin = 18
	var textured := _texture_style(texture_path, textured_margin)
	if textured != null:
		return textured
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.025, 0.025, 0.05, 0.92)
	style.border_color = Color(0.95, 0.48, 0.1)
	style.set_border_width_all(3)
	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 10
	style.corner_radius_bottom_left = 10
	style.corner_radius_bottom_right = 10
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 10
	style.content_margin_bottom = 10
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
	style.content_margin_left = 14
	style.content_margin_right = 14
	style.content_margin_top = 10
	style.content_margin_bottom = 10
	return style


func _load_menu_font() -> void:
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

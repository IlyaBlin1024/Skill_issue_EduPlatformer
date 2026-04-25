extends CanvasLayer

class_name TutorialOverlay

signal advanced

@onready var dim_rect: ColorRect = $Dim
@onready var arrow_label: Label = $Arrow
@onready var panel: PanelContainer = $Panel
@onready var body_label: RichTextLabel = $Panel/Margin/VBox/Body
@onready var next_button: Button = $Panel/Margin/VBox/NextButton


func _ready() -> void:
	layer = 120
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process_input(true)
	hide_overlay()
	next_button.pressed.connect(_on_next_pressed)
	next_button.action_mode = BaseButton.ACTION_MODE_BUTTON_PRESS
	next_button.focus_mode = Control.FOCUS_ALL
	next_button.mouse_filter = Control.MOUSE_FILTER_STOP
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	dim_rect.mouse_filter = Control.MOUSE_FILTER_STOP
	body_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	arrow_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	next_button.gui_input.connect(_on_control_gui_input)
	panel.gui_input.connect(_on_control_gui_input)
	dim_rect.gui_input.connect(_on_control_gui_input)


func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("attack_primary") or event.is_action_pressed("jump") or _is_continue_key(event):
		_on_next_pressed()
		get_viewport().set_input_as_handled()


func show_step(text: String, target: Variant, arrow_direction: String = "down", panel_anchor: String = "bottom") -> void:
	visible = true
	dim_rect.visible = true
	panel.visible = true
	arrow_label.visible = true
	body_label.clear()
	body_label.append_text(text)
	_place_arrow(target, arrow_direction)
	_place_panel(panel_anchor)
	next_button.disabled = false
	next_button.grab_focus()


func hide_overlay() -> void:
	visible = false
	dim_rect.visible = false
	panel.visible = false
	arrow_label.visible = false


func _on_next_pressed() -> void:
	advanced.emit()


func _is_continue_key(event: InputEvent) -> bool:
	if event is not InputEventKey:
		return false
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return false
	return key_event.physical_keycode == Key.KEY_Q or key_event.physical_keycode == Key.KEY_SPACE


func _on_control_gui_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is not InputEventMouseButton:
		return
	var mouse_event := event as InputEventMouseButton
	if not mouse_event.pressed:
		return
	if mouse_event.button_index != MOUSE_BUTTON_LEFT:
		return
	_on_next_pressed()
	get_viewport().set_input_as_handled()


func _place_arrow(target: Variant, arrow_direction: String) -> void:
	var target_position: Vector2 = _resolve_target_position(target)
	match arrow_direction:
		"up":
			arrow_label.text = "^"
			arrow_label.position = target_position + Vector2(-14.0, 28.0)
		"left":
			arrow_label.text = "<"
			arrow_label.position = target_position + Vector2(28.0, -22.0)
		"right":
			arrow_label.text = ">"
			arrow_label.position = target_position + Vector2(-48.0, -22.0)
		_:
			arrow_label.text = "v"
			arrow_label.position = target_position + Vector2(-14.0, -58.0)


func _place_panel(panel_anchor: String) -> void:
	match panel_anchor:
		"top":
			panel.position = Vector2(120.0, 36.0)
		"center":
			panel.position = Vector2(160.0, 210.0)
		_:
			panel.position = Vector2(100.0, 500.0)


func _resolve_target_position(target: Variant) -> Vector2:
	if target is Control:
		return (target as Control).get_global_rect().get_center()
	if target is Node2D:
		return get_viewport().get_canvas_transform() * (target as Node2D).global_position
	if typeof(target) == TYPE_VECTOR2:
		return target
	return Vector2(640.0, 360.0)

extends CanvasLayer

class_name BossDialogueBox

signal next_pressed

const TEXT_GOLD := Color(1.0, 0.78, 0.24, 1.0)
const BODY_GOLD := Color(1.0, 0.88, 0.46, 1.0)

@onready var overlay: ColorRect = $Overlay
@onready var dialogue_panel: PanelContainer = $Root/DialoguePanel
@onready var name_plate: PanelContainer = $Root/NamePlate
@onready var portrait_frame: PanelContainer = $Root/PortraitFrame
@onready var name_label: Label = $Root/NamePlate/NameLabel
@onready var body_label: Label = $Root/DialoguePanel/ContentMargin/BodyLabel
@onready var prompt_label: Label = $Root/DialoguePanel/AdvanceBox/PromptLabel
@onready var next_button: Button = $Root/DialoguePanel/AdvanceBox/NextButton
@onready var portrait: ColorRect = $Root/PortraitFrame/PortraitMargin/Portrait

var _portrait_model: TextureRect = null


func _ready() -> void:
	layer = 50
	process_mode = Node.PROCESS_MODE_ALWAYS
	_apply_text_colors()
	_ensure_portrait_model()
	visible = true
	next_button.pressed.connect(_on_next_pressed)
	hide_box()


func _input(event: InputEvent) -> void:
	if not is_open():
		return
	if event.is_action_pressed("attack_primary") or event.is_action_pressed("interact") or event.is_action_pressed("jump"):
		get_viewport().set_input_as_handled()
		next_pressed.emit()


func show_line(speaker: String, text: String, portrait_color: Color, portrait_texture: Texture2D = null, portrait_faces_left: bool = false) -> void:
	visible = true
	overlay.visible = false
	dialogue_panel.visible = true
	name_plate.visible = true
	portrait_frame.visible = true
	name_label.text = speaker.strip_edges()
	body_label.text = text.strip_edges()
	prompt_label.text = "Q"
	portrait.color = Color(0, 0, 0, 0)
	_hide_legacy_portrait_children()
	if _portrait_model != null:
		_portrait_model.texture = portrait_texture
		_portrait_model.visible = portrait_texture != null
		_portrait_model.modulate = Color(1, 1, 1, 1)
		_portrait_model.flip_h = portrait_faces_left
	next_button.disabled = false


func hide_box() -> void:
	overlay.visible = false
	dialogue_panel.visible = false
	name_plate.visible = false
	portrait_frame.visible = false
	next_button.disabled = true
	name_label.text = ""
	body_label.text = ""
	if _portrait_model != null:
		_portrait_model.visible = false


func is_open() -> bool:
	return dialogue_panel.visible


func _on_next_pressed() -> void:
	next_pressed.emit()


func _apply_text_colors() -> void:
	for label in [name_label, body_label, prompt_label, next_button]:
		label.add_theme_color_override("font_color", TEXT_GOLD if label != body_label else BODY_GOLD)
		label.add_theme_color_override("font_shadow_color", Color(0.02, 0.01, 0.0, 0.9))
		label.add_theme_constant_override("shadow_offset_x", 2)
		label.add_theme_constant_override("shadow_offset_y", 2)


func _ensure_portrait_model() -> void:
	if _portrait_model != null:
		return
	_hide_legacy_portrait_children()
	_portrait_model = TextureRect.new()
	_portrait_model.name = "PortraitModel"
	_portrait_model.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_portrait_model.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_portrait_model.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portrait_model.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_portrait_model.set_anchors_preset(Control.PRESET_FULL_RECT)
	_portrait_model.offset_left = 12.0
	_portrait_model.offset_top = 8.0
	_portrait_model.offset_right = -12.0
	_portrait_model.offset_bottom = -8.0
	_portrait_model.visible = false
	portrait.add_child(_portrait_model)


func _hide_legacy_portrait_children() -> void:
	for child in portrait.get_children():
		if child == _portrait_model:
			continue
		if child is CanvasItem:
			var canvas_child := child as CanvasItem
			canvas_child.visible = false
			canvas_child.modulate = Color(1, 1, 1, 0)
			canvas_child.self_modulate = Color(1, 1, 1, 0)

extends CanvasLayer

class_name BossDialogueBox

signal next_pressed

@onready var overlay: ColorRect = $Overlay
@onready var dialogue_panel: PanelContainer = $Root/DialoguePanel
@onready var name_plate: PanelContainer = $Root/NamePlate
@onready var portrait_frame: PanelContainer = $Root/PortraitFrame
@onready var name_label: Label = $Root/NamePlate/NameLabel
@onready var body_label: Label = $Root/DialoguePanel/ContentMargin/BodyLabel
@onready var prompt_label: Label = $Root/DialoguePanel/AdvanceBox/PromptLabel
@onready var next_button: Button = $Root/DialoguePanel/AdvanceBox/NextButton
@onready var portrait: ColorRect = $Root/PortraitFrame/PortraitMargin/Portrait


func _ready() -> void:
	layer = 50
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = true
	next_button.pressed.connect(_on_next_pressed)
	hide_box()


func _input(event: InputEvent) -> void:
	if not is_open():
		return
	if event.is_action_pressed("attack_primary") or event.is_action_pressed("interact") or event.is_action_pressed("jump"):
		get_viewport().set_input_as_handled()
		next_pressed.emit()


func show_line(speaker: String, text: String, portrait_color: Color) -> void:
	visible = true
	overlay.visible = false
	dialogue_panel.visible = true
	name_plate.visible = true
	portrait_frame.visible = true
	name_label.text = speaker.strip_edges()
	body_label.text = text.strip_edges()
	prompt_label.text = "Q"
	portrait.color = portrait_color
	next_button.disabled = false


func hide_box() -> void:
	overlay.visible = false
	dialogue_panel.visible = false
	name_plate.visible = false
	portrait_frame.visible = false
	next_button.disabled = true
	name_label.text = ""
	body_label.text = ""


func is_open() -> bool:
	return dialogue_panel.visible


func _on_next_pressed() -> void:
	next_pressed.emit()

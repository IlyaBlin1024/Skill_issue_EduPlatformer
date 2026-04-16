extends CanvasLayer

class_name GameHud

@onready var health_label: Label = $Margin/VBox/HealthLabel
@onready var health_bar: ProgressBar = $Margin/VBox/HealthBar
@onready var enemy_counter_label: Label = $Margin/VBox/EnemyCounterLabel
@onready var room_label: Label = $Margin/VBox/RoomLabel
@onready var objective_label: Label = $Margin/VBox/ObjectiveLabel
@onready var boss_status_label: Label = $Margin/VBox/BossStatusLabel
@onready var message_label: Label = $Margin/VBox/MessageLabel

var _message_version: int = 0


func update_health(current_health: int, max_health: int) -> void:
	health_label.text = "Knight Integrity: %d / %d" % [current_health, max_health]
	health_bar.max_value = max_health
	health_bar.value = current_health


func update_enemy_counter(remaining_enemies: int, total_enemies: int) -> void:
	enemy_counter_label.text = "Sentries Remaining: %d / %d" % [remaining_enemies, total_enemies]
	enemy_counter_label.visible = total_enemies > 0


func set_room_context(room_title: String) -> void:
	room_label.text = room_title
	room_label.visible = not room_title.is_empty()


func set_objective(text: String) -> void:
	objective_label.text = text
	objective_label.visible = not text.is_empty()


func set_boss_status(text: String) -> void:
	boss_status_label.text = text
	boss_status_label.visible = not text.is_empty()


func show_message(text: String, duration: float = 1.6) -> void:
	_message_version += 1
	var version := _message_version
	message_label.text = text
	if duration <= 0.0:
		return
	await get_tree().create_timer(duration).timeout
	if version == _message_version:
		message_label.text = ""

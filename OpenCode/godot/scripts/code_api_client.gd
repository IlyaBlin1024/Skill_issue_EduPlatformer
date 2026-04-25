extends Node

signal validation_result_received(result: Dictionary)
signal hint_result_received(result: Dictionary)
signal task_result_received(result: Dictionary)
signal logs_export_received(file_path: String)
signal logs_export_failed(message: String)
signal request_failed(message: String)

const DEFAULT_URL := "http://127.0.0.1:8000/validate"
const HINTS_URL := "http://127.0.0.1:8000/hints"
const TASKS_URL := "http://127.0.0.1:8000/tasks/generate"
const LOG_EVENT_URL := "http://127.0.0.1:8000/logs/event"
const LOG_EXPORT_URL := "http://127.0.0.1:8000/logs/export"

var _http_request: HTTPRequest
var _task_request: HTTPRequest
var _log_request: HTTPRequest
var _export_request: HTTPRequest
var _pending_request_kind := "validate"
var _pending_export_path := ""
var _log_queue: Array[Dictionary] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	_http_request = HTTPRequest.new()
	_http_request.process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	_http_request.timeout = 15.0
	add_child(_http_request)
	_http_request.request_completed.connect(_on_request_completed)
	_task_request = HTTPRequest.new()
	_task_request.process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	_task_request.timeout = 10.0
	add_child(_task_request)
	_task_request.request_completed.connect(_on_task_request_completed)
	_log_request = HTTPRequest.new()
	_log_request.process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	_log_request.timeout = 4.0
	add_child(_log_request)
	_log_request.request_completed.connect(_on_log_request_completed)
	_export_request = HTTPRequest.new()
	_export_request.process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	_export_request.timeout = 30.0
	add_child(_export_request)
	_export_request.request_completed.connect(_on_export_request_completed)


func validate_interaction(payload: Dictionary) -> void:
	var headers := PackedStringArray(["Content-Type: application/json"])
	var body := JSON.stringify(payload)
	_pending_request_kind = "validate"
	var error := _http_request.request(DEFAULT_URL, headers, HTTPClient.METHOD_POST, body)
	if error != OK:
		request_failed.emit("Unable to contact backend. Is the FastAPI server running?")


func validate_combat(payload: Dictionary) -> void:
	var request_payload: Dictionary = payload.duplicate(true)
	request_payload["interaction_type"] = String(request_payload.get("interaction_type", "combat"))
	validate_interaction(request_payload)


func request_hints(payload: Dictionary) -> void:
	var headers := PackedStringArray(["Content-Type: application/json"])
	var body := JSON.stringify(payload)
	_pending_request_kind = "hints"
	var error := _http_request.request(HINTS_URL, headers, HTTPClient.METHOD_POST, body)
	if error != OK:
		request_failed.emit("Unable to contact backend. Is the FastAPI server running?")


func request_task(payload: Dictionary) -> void:
	var headers := PackedStringArray(["Content-Type: application/json"])
	var body := JSON.stringify(payload)
	var error := _task_request.request(TASKS_URL, headers, HTTPClient.METHOD_POST, body)
	if error != OK:
		request_failed.emit("Unable to fetch a generated task from backend.")


func send_log_event(payload: Dictionary) -> void:
	_log_queue.append(payload.duplicate(true))
	_pump_log_queue()


func _pump_log_queue() -> void:
	if _log_request.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		return
	if _log_queue.is_empty():
		return
	var payload: Dictionary = _log_queue.pop_front()
	var headers := PackedStringArray(["Content-Type: application/json"])
	var body := JSON.stringify(payload)
	var error := _log_request.request(LOG_EVENT_URL, headers, HTTPClient.METHOD_POST, body)
	if error != OK:
		call_deferred("_pump_log_queue")


func export_logs_to_downloads() -> void:
	if _export_request.get_http_client_status() != HTTPClient.STATUS_DISCONNECTED:
		logs_export_failed.emit("Log export is already running.")
		return
	var downloads_dir := OS.get_system_dir(OS.SYSTEM_DIR_DOWNLOADS)
	if downloads_dir.is_empty():
		downloads_dir = OS.get_user_data_dir()
	var timestamp := Time.get_datetime_string_from_system(false, true).replace(":", "-").replace(" ", "_")
	_pending_export_path = downloads_dir.path_join("Skill-Issue-player-logs-%s.xlsx" % timestamp)
	_export_request.download_file = _pending_export_path
	var error := _export_request.request(LOG_EXPORT_URL, PackedStringArray(), HTTPClient.METHOD_GET)
	if error != OK:
		_export_request.download_file = ""
		logs_export_failed.emit("Unable to request Excel log export.")


func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or response_code >= 400:
		request_failed.emit("Validation request failed with code %s." % response_code)
		return

	var parsed = JSON.parse_string(body.get_string_from_utf8())
	if typeof(parsed) != TYPE_DICTIONARY:
		request_failed.emit("Backend returned an unexpected payload.")
		return

	if _pending_request_kind == "hints":
		hint_result_received.emit(parsed)
		return
	validation_result_received.emit(parsed)


func _on_task_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or response_code >= 400:
		request_failed.emit("Task generation request failed with code %s." % response_code)
		return
	var parsed = JSON.parse_string(body.get_string_from_utf8())
	if typeof(parsed) != TYPE_DICTIONARY:
		request_failed.emit("Backend returned an unexpected task payload.")
		return
	task_result_received.emit(parsed)


func _on_log_request_completed(_result: int, _response_code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	_pump_log_queue()


func _on_export_request_completed(result: int, response_code: int, _headers: PackedStringArray, _body: PackedByteArray) -> void:
	_export_request.download_file = ""
	if result != HTTPRequest.RESULT_SUCCESS or response_code >= 400:
		logs_export_failed.emit("Log export failed with code %s." % response_code)
		return
	if _pending_export_path.is_empty() or not FileAccess.file_exists(_pending_export_path):
		logs_export_failed.emit("Log export finished, but the Excel file was not saved.")
		return
	logs_export_received.emit(_pending_export_path)

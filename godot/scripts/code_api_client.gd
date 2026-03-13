extends Node

signal combat_result_received(result: Dictionary)
signal request_failed(message: String)

const DEFAULT_URL := "http://127.0.0.1:8000/validate/combat"

var _http_request: HTTPRequest


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	_http_request = HTTPRequest.new()
	_http_request.process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	add_child(_http_request)
	_http_request.request_completed.connect(_on_request_completed)


func validate_combat(payload: Dictionary) -> void:
	var headers := PackedStringArray(["Content-Type: application/json"])
	var body := JSON.stringify(payload)
	var error := _http_request.request(DEFAULT_URL, headers, HTTPClient.METHOD_POST, body)
	if error != OK:
		request_failed.emit("Unable to contact backend. Is the FastAPI server running?")


func _on_request_completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	if result != HTTPRequest.RESULT_SUCCESS or response_code >= 400:
		request_failed.emit("Validation request failed with code %s." % response_code)
		return

	var parsed = JSON.parse_string(body.get_string_from_utf8())
	if typeof(parsed) != TYPE_DICTIONARY:
		request_failed.emit("Backend returned an unexpected payload.")
		return

	combat_result_received.emit(parsed)

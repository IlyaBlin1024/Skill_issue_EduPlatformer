extends Node

signal validation_result_received(result: Dictionary)
signal hint_result_received(result: Dictionary)
signal request_failed(message: String)

const DEFAULT_URL := "http://127.0.0.1:8000/validate"
const HINTS_URL := "http://127.0.0.1:8000/hints"

var _http_request: HTTPRequest
var _pending_request_kind := "validate"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	_http_request = HTTPRequest.new()
	_http_request.process_mode = Node.PROCESS_MODE_WHEN_PAUSED
	add_child(_http_request)
	_http_request.request_completed.connect(_on_request_completed)


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

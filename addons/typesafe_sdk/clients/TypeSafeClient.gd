class_name TypeSafeClient
extends Node
## Synchronous-style client for the TypeSafe API.
## Mirrors Python `TypeSafeClient` (https://docs.typesafe.ai/sdk/python/api/clients/sync).
##
## GDScript is signal-based: [method system_one] queues an async HTTP call and
## emits [signal evaluation_completed] or [signal evaluation_failed].
## Use `await client.evaluation_completed` for async/await style.
## [member models] mirrors `client.models` (`Models.list()`).

signal evaluation_completed(response: SystemOneResponse)
signal evaluation_failed(error: TypeSafeError)
signal custom_evaluation_completed(response: Variant)

var config: TypeSafeConfig
var default_retry: RetryPolicy

var models: Models

var _pending_requests: Dictionary = {}
var _request_counter: int = 0

const _PROTECTED_HEADERS: Array = ["authorization", "accept", "user-agent"]


func _init(p_api_key: Variant = null, p_model: Variant = null, p_base_url: Variant = null, p_timeout: float = -1.0, p_retry: RetryPolicy = null, p_headers: Dictionary = {}) -> void:
	config = TypeSafeConfig.resolve(p_api_key, p_base_url, p_model, p_timeout, p_headers)
	default_retry = p_retry if p_retry != null else RetryPolicy.default()

	models = Models.new(config)


func _ready() -> void:
	if models != null and models.get_parent() == null:
		add_child(models)


func _notification(what: int) -> void:
	if what == NOTIFICATION_ENTER_TREE:
		if models != null and models.get_parent() == null:
			add_child(models)
	elif what == NOTIFICATION_PREDELETE:
		if models != null and is_instance_valid(models) and models.get_parent() == null:
			models.free()


## Answer named questions about text, structured state, or images.
## Mirrors Python `system_one(state, questions, model, retry, timeout,
## extra_headers, extra_body, response_model)`.
## - `state`: String, Dictionary, Array, or TypeSafeImage (must not be null).
## - `questions`: non-empty Dictionary of Question objects or raw Dictionaries.
## - `p_response_model`: optional Callable(json_body: Dictionary, headers: Dictionary)
##   -> Variant, the GDScript equivalent of pydantic `response_model`. When set,
##   the raw JSON is passed to it and [signal custom_evaluation_completed] is
##   emitted instead of [signal evaluation_completed].
func system_one(state: Variant, questions: Dictionary, p_model: Variant = null, p_retry: RetryPolicy = null, p_timeout: float = -1.0, p_extra_headers: Variant = null, p_extra_body: Variant = null, p_response_model: Variant = null) -> Error:
	var explicit_assets = null
	if typeof(p_extra_body) == TYPE_DICTIONARY and (p_extra_body as Dictionary).has("assets"):
		explicit_assets = (p_extra_body as Dictionary)["assets"]
	return _execute_system_one(state, questions, explicit_assets, p_model, p_retry, p_timeout, p_extra_headers, p_extra_body, p_response_model)


## Answer named questions with an explicit assets collection.
## - `assets`: Dictionary mapping alias -> TypeSafeImage, Array[TypeSafeImage], or single TypeSafeImage.
func system_one_with_assets(state: Variant, questions: Dictionary, assets: Variant, p_model: Variant = null, p_retry: RetryPolicy = null, p_timeout: float = -1.0, p_extra_headers: Variant = null, p_extra_body: Variant = null, p_response_model: Variant = null) -> Error:
	return _execute_system_one(state, questions, assets, p_model, p_retry, p_timeout, p_extra_headers, p_extra_body, p_response_model)


func _execute_system_one(state: Variant, questions: Dictionary, p_assets: Variant, p_model: Variant, p_retry: RetryPolicy, p_timeout: float, p_extra_headers: Variant, p_extra_body: Variant, p_response_model: Variant) -> Error:
	var err := _validate_questions(questions)
	if err != OK:
		var type_err := TypeSafeError.new("Questions validation failed: " + _get_error_message(err))
		_call_deferred_failed(type_err)
		return err

	if state == null:
		var null_err := TypeSafeError.new("state must not be null (String, Dictionary, Array, or TypeSafeImage).")
		_call_deferred_failed(null_err)
		return ERR_INVALID_PARAMETER

	if config.api_key.strip_edges() == "":
		var key_err := TypeSafeError.new("TypeSafeClient: TypeSafe API key is missing. Set TYPESAFE_API_KEY environment variable or pass api_key to constructor.")
		_call_deferred_failed(key_err)
		return ERR_UNCONFIGURED

	# Non-destructive copy-on-write asset extraction and reference substitution
	var extraction := AssetExtractor.extract(state, questions, p_assets)
	if extraction.error_message != "":
		var extract_err := TypeSafeError.new("Asset extraction failed: " + extraction.error_message)
		_call_deferred_failed(extract_err)
		return ERR_INVALID_DATA

	var extra_headers: Dictionary = p_extra_headers if typeof(p_extra_headers) == TYPE_DICTIONARY else {}
	var extra_body: Dictionary = p_extra_body if typeof(p_extra_body) == TYPE_DICTIONARY else {}

	var payload := _prepare_system_one(extraction.cloned_state, extraction.cloned_questions, p_model, extra_body)

	var has_box_questions := _has_box_question(questions)
	var has_images := extraction.has_images or has_box_questions

	# HTTPRequest nodes only process inside the scene tree; auto-enter like enter().
	enter()

	var retry: RetryPolicy = p_retry if p_retry != null else default_retry
	var timeout := p_timeout if p_timeout >= 0.0 else config.timeout

	var request_id := _request_counter
	_request_counter += 1

	var http := HTTPRequest.new()
	http.timeout = timeout
	add_child(http)

	var is_raw := false
	var raw_body := PackedByteArray()
	var headers: PackedStringArray

	if extraction.has_images:
		# Build assets map with part references
		var assets_map := {}
		var idx := 0
		for asset_key in extraction.assets:
			var part_name := "asset-%d" % idx
			assets_map[asset_key] = {"type": "image", "part": part_name}
			idx += 1
		payload["assets"] = assets_map

		var json_str := JSON.stringify(payload)
		var mp_res := TypeSafeMultipart.encode_request(json_str, extraction.assets)
		headers = _build_headers(extra_headers, mp_res["content_type"], true)
		raw_body = mp_res["body"]
		is_raw = true
	else:
		var json_str := JSON.stringify(payload)
		if config.enable_zstd:
			var utf8_bytes := json_str.to_utf8_buffer()
			if utf8_bytes.size() >= 1024:
				raw_body = utf8_bytes.compress(FileAccess.COMPRESSION_ZSTD)
				headers = _build_headers(extra_headers, "application/json", has_box_questions)
				headers.append("Content-Encoding: zstd")
				is_raw = true
			else:
				headers = _build_headers(extra_headers, "application/json", has_box_questions)
		else:
			headers = _build_headers(extra_headers, "application/json", has_box_questions)

	var headers_dict := _headers_to_dict(headers)

	_pending_requests[request_id] = {
		"http": http,
		"type": "system_one",
		"retry": retry,
		"attempt": 0,
		"timeout": timeout,
		"start_time": Time.get_ticks_msec() / 1000.0,
		"payload": payload,
		"headers": headers,
		"headers_dict": headers_dict,
		"response_model": p_response_model,
		"is_raw": is_raw,
		"raw_body": raw_body,
	}
	http.request_completed.connect(_on_request_completed.bind(request_id))

	TypeSafeLogger.log_request("POST", config.system_one_url(), headers_dict, payload)
	var send_error: Error
	if is_raw:
		send_error = http.request_raw(config.system_one_url(), headers, HTTPClient.METHOD_POST, raw_body)
	else:
		send_error = http.request(config.system_one_url(), headers, HTTPClient.METHOD_POST, JSON.stringify(payload))

	if send_error != OK:
		_cleanup_request(request_id)
		var conn_err := TypeSafeAPIConnectionError.new("Failed to send request: %s" % send_error)
		_call_deferred_failed(conn_err)
		return send_error

	return OK


func _has_box_question(p_questions: Dictionary) -> bool:
	for k in p_questions:
		var q = p_questions[k]
		if q is Box:
			return true
		elif typeof(q) == TYPE_DICTIONARY and str(q.get("type", "")) == "box":
			return true
	return false


func _call_deferred_failed(p_err: TypeSafeError) -> void:
	call_deferred("emit_signal", "evaluation_failed", p_err)


func _validate_questions(questions: Dictionary) -> Error:
	# Mirrors Python: questions must be non-empty; score criteria must be non-empty.
	if typeof(questions) != TYPE_DICTIONARY or questions.size() == 0:
		return ERR_INVALID_PARAMETER

	for key in questions:
		var q = questions[key]
		if q is Question:
			if q is Choice:
				if typeof((q as Choice).criteria) != TYPE_DICTIONARY:
					return ERR_INVALID_PARAMETER
				if (q as Choice).criteria.size() > 255:
					TypeSafeLogger.warning("Choice question '%s' has %d options; API allows max 255." % [str(key), (q as Choice).criteria.size()])
			elif q is Score:
				if typeof((q as Score).criteria) != TYPE_ARRAY or (q as Score).criteria.is_empty():
					return ERR_INVALID_PARAMETER
				if (q as Score).criteria.size() < 2 or (q as Score).criteria.size() > 10:
					TypeSafeLogger.warning("Score question '%s' has %d levels; API accepts 2-10." % [str(key), (q as Score).criteria.size()])
			elif q is Noul:
				pass
			elif q is Box:
				pass
			else:
				return ERR_INVALID_PARAMETER
		elif typeof(q) == TYPE_DICTIONARY:
			if not q.has("type") or str(q["type"]).strip_edges() == "":
				return ERR_INVALID_PARAMETER
			var t := str(q["type"])
			if t == "choice" and not q.has("criteria"):
				return ERR_INVALID_PARAMETER
			if t == "score":
				if not q.has("criteria") or typeof(q["criteria"]) != TYPE_ARRAY:
					return ERR_INVALID_PARAMETER
				if (q["criteria"] as Array).is_empty():
					return ERR_INVALID_PARAMETER
			if t == "noul" or t == "box":
				pass
			# Raw dicts may carry unknown forward-compat fields (e.g. weight);
			# they pass through untouched.
		else:
			return ERR_INVALID_PARAMETER

	return OK


func _get_error_message(err: Error) -> String:
	match err:
		ERR_INVALID_PARAMETER:
			return "Invalid question format or missing required fields"
		ERR_UNCONFIGURED:
			return "Client not configured"
		_:
			return "Unknown error"


func _prepare_system_one(state: Variant, questions: Dictionary, p_model: Variant, p_extra_body: Dictionary) -> Dictionary:
	var serialized_questions: Dictionary = {}
	for key in questions:
		var q = questions[key]
		if q is Question:
			serialized_questions[key] = (q as Question).to_dict()
		elif typeof(q) == TYPE_DICTIONARY:
			serialized_questions[key] = q

	var resolved_model := config.default_model
	if p_model != null and str(p_model).strip_edges() != "":
		resolved_model = str(p_model)

	var payload: Dictionary = {
		"model": resolved_model,
		"state": state,
		"questions": serialized_questions,
	}

	# extra_body: shallow merge, last-write-wins (may override state/model/questions).
	for key in p_extra_body:
		payload[key] = p_extra_body[key]

	return payload


func _build_headers(p_extra_headers: Dictionary, p_content_type: String = "application/json", p_has_images: bool = false) -> PackedStringArray:
	var headers: PackedStringArray = [
		"Authorization: Bearer " + config.api_key,
		"Content-Type: " + p_content_type,
		"Accept: application/json",
		"User-Agent: %s/%s" % [TypeSafeConstants.SDK_NAME, TypeSafeConstants.SDK_VERSION],
	]

	var has_danger_zone := false
	for key in config.default_headers:
		var k := str(key)
		if k.to_lower() == TypeSafeConstants.IMAGES_HEADER.to_lower():
			has_danger_zone = true
		if not _is_protected_header(k):
			headers.append("%s: %s" % [k, str(config.default_headers[key])])
	for key in p_extra_headers:
		var k := str(key)
		if k.to_lower() == TypeSafeConstants.IMAGES_HEADER.to_lower():
			has_danger_zone = true
		if not _is_protected_header(k):
			headers.append("%s: %s" % [k, str(p_extra_headers[key])])
		else:
			TypeSafeLogger.warning("Ignoring extra header '%s': authentication, SDK identification, and Accept remain protected." % k)

	if p_has_images and not has_danger_zone:
		headers.append("%s: true" % TypeSafeConstants.IMAGES_HEADER)

	return headers


func _is_protected_header(p_name: String) -> bool:
	return p_name.strip_edges().to_lower() in _PROTECTED_HEADERS


func _on_request_completed(result: int, response_code: int, response_headers: PackedStringArray, body: PackedByteArray, request_id: int) -> void:
	if not _pending_requests.has(request_id):
		return
	var pending: Dictionary = _pending_requests[request_id]
	var retry: RetryPolicy = pending.get("retry", default_retry)
	var attempt: int = int(pending.get("attempt", 0))
	var timeout: float = float(pending.get("timeout", config.timeout))
	var start_time: float = float(pending.get("start_time", 0.0))
	var headers_dict: Dictionary = pending.get("headers_dict", {})

	var body_str := body.get_string_from_utf8()
	var resp_headers := _headers_to_dict(response_headers)

	if result != HTTPRequest.RESULT_SUCCESS:
		var fail_err := _handle_request_failure(result, timeout)
		TypeSafeLogger.log_response(response_code, resp_headers, body_str)
		pending["last_headers"] = resp_headers
		if retry.is_retryable(fail_err) and _within_budget(retry, attempt, start_time, resp_headers):
			_schedule_retry(request_id, fail_err, resp_headers)
			return
		_cleanup_request(request_id)
		evaluation_failed.emit(fail_err)
		return

	var json := JSON.new()
	if json.parse(body_str) != OK:
		TypeSafeLogger.log_response(response_code, resp_headers, body_str)
		var parse_err := TypeSafeAPIResponseValidationError.new(response_code, body_str, resp_headers, "root", config.system_one_url())
		_cleanup_request(request_id)
		evaluation_failed.emit(parse_err)
		return

	if response_code != 200:
		TypeSafeLogger.log_response(response_code, resp_headers, json.data)
		var api_err := _create_api_error(response_code, json.data, resp_headers)
		pending["last_headers"] = resp_headers
		if retry.is_retryable(api_err) and _within_budget(retry, attempt, start_time, resp_headers):
			_schedule_retry(request_id, api_err, resp_headers)
			return
		_cleanup_request(request_id)
		evaluation_failed.emit(api_err)
		return

	TypeSafeLogger.log_response(response_code, resp_headers, json.data)
	var raw_http := {"status": response_code, "headers": resp_headers, "body": body_str}
	if typeof(json.data) != TYPE_DICTIONARY:
		_cleanup_request(request_id)
		evaluation_failed.emit(TypeSafeAPIResponseValidationError.new(response_code, body_str, resp_headers, "root", config.system_one_url()))
		return

	var response_model: Variant = pending.get("response_model")
	_cleanup_request(request_id)
	if response_model != null:
		var custom := _apply_response_model(response_model, json.data as Dictionary, resp_headers, raw_http, response_code)
		if custom[0]:
			custom_evaluation_completed.emit(custom[1])
		else:
			evaluation_failed.emit(custom[1])
		return

	var response := SystemOneResponse.from_dict(json.data as Dictionary, resp_headers, raw_http)
	evaluation_completed.emit(response)


func _apply_response_model(p_model: Variant, p_json: Dictionary, p_headers: Dictionary, p_raw_http: Dictionary, p_status: int) -> Array:
	# Returns [ok: bool, value: Variant].
	if typeof(p_model) == TYPE_CALLABLE:
		var cb := p_model as Callable
		if not cb.is_valid():
			return [false, TypeSafeAPIResponseValidationError.new(p_status, p_json, p_headers, "root", config.system_one_url())]
		var value: Variant = cb.call(p_json, p_headers)
		return [true, value]
	# GDScript class with static from_dict(json, headers) or from_dict(json).
	if typeof(p_model) == TYPE_OBJECT:
		var obj: Object = p_model
		if obj.has_method("from_dict"):
			var v: Variant = obj.call("from_dict", p_json)
			return [true, v]
	return [false, TypeSafeAPIResponseValidationError.new(p_status, p_json, p_headers, "root", config.system_one_url())]


func _handle_request_failure(result: int, timeout: float) -> TypeSafeError:
	# HTTPRequest.Result in Godot 4.7: SUCCESS, CHUNKED_BODY_SIZE_MISMATCH,
	# CANT_CONNECT, CANT_RESOLVE, CONNECTION_ERROR, SSL_HANDSHAKE_ERROR,
	# NO_RESPONSE, BODY_SIZE_LIMIT_EXCEEDED, BODY_DECOMPRESS_FAILED,
	# REQUEST_FAILED, DOWNLOAD_FILE_CANT_OPEN, DOWNLOAD_FILE_WRITE_ERROR,
	# REDIRECT_LIMIT_REACHED, TIMEOUT.
	if result == HTTPRequest.RESULT_TIMEOUT:
		return TypeSafeAPITimeoutError.new(timeout)
	return TypeSafeAPIConnectionError.new("HTTP request failed: %d" % result)


func _create_api_error(status_code: int, body: Variant, headers: Dictionary) -> TypeSafeAPIError:
	var endpoint := config.system_one_url()

	match status_code:
		400:
			return TypeSafeBadRequestError.new(status_code, body, headers, _body_message(body), endpoint)
		401:
			return TypeSafeAuthenticationError.new(status_code, body, headers, _body_message(body), endpoint)
		403:
			return TypeSafePermissionDeniedError.new(status_code, body, headers, _body_message(body), endpoint)
		404:
			return TypeSafeNotFoundError.new(status_code, body, headers, _body_message(body), endpoint)
		422:
			return TypeSafeUnprocessableEntityError.new(status_code, body, headers, _body_message(body), endpoint)
		429:
			return TypeSafeRateLimitError.new(status_code, body, headers, _body_message(body), endpoint)
		_:
			if status_code >= 500:
				return TypeSafeInternalServerError.new(status_code, body, headers, _body_message(body), endpoint)
			return TypeSafeAPIError.new(status_code, body, headers, _body_message(body), endpoint)


func _body_message(p_body: Variant) -> String:
	if typeof(p_body) == TYPE_DICTIONARY:
		var d: Dictionary = p_body
		if d.has("message"):
			return str(d["message"])
		if d.has("detail"):
			var det = d["detail"]
			if typeof(det) == TYPE_DICTIONARY and (det as Dictionary).has("message"):
				return str((det as Dictionary)["message"])
			return str(det)
		if d.has("error"):
			return str(d["error"])
	elif typeof(p_body) == TYPE_STRING and (p_body as String).length() < 500:
		return p_body
	return ""


func _within_budget(retry: RetryPolicy, attempt: int, start_time: float, resp_headers: Dictionary) -> bool:
	if attempt >= retry.max_retries:
		return false
	if not retry.has_timeout_budget():
		return true
	var elapsed := (Time.get_ticks_msec() / 1000.0) - start_time
	var delay := retry.calculate_backoff(attempt + 1)
	var retry_after := retry.get_retry_after(resp_headers)
	if retry_after > 0.0:
		delay = maxf(delay, retry_after)
	return elapsed + delay < float(retry.timeout)


func _schedule_retry(request_id: int, _err: TypeSafeError, resp_headers: Dictionary) -> void:
	if not _pending_requests.has(request_id):
		return
	var pending: Dictionary = _pending_requests[request_id]
	var retry: RetryPolicy = pending.get("retry", default_retry)
	var attempt_next: int = int(pending.get("attempt", 0)) + 1
	var delay := retry.calculate_backoff(attempt_next)
	var retry_after := retry.get_retry_after(resp_headers)
	if retry_after > 0.0:
		delay = maxf(delay, retry_after)

	if retry.has_timeout_budget():
		var elapsed := (Time.get_ticks_msec() / 1000.0) - float(pending.get("start_time", 0.0))
		if elapsed + delay >= float(retry.timeout):
			_cleanup_request(request_id)
			evaluation_failed.emit(TypeSafeAPITimeoutError.new(float(retry.timeout)))
			return

	pending["pending_delay"] = delay

	var timer := Timer.new()
	timer.wait_time = maxf(delay, 0.0)
	timer.one_shot = true
	add_child(timer)
	timer.timeout.connect(_on_retry_timer_timeout.bind(timer, request_id))
	timer.start()

	pending["timer"] = timer
	_pending_requests[request_id] = pending


func _on_retry_timer_timeout(timer: Timer, request_id: int) -> void:
	if is_instance_valid(timer):
		timer.queue_free()
	if not _pending_requests.has(request_id):
		return
	var pending: Dictionary = _pending_requests[request_id]
	pending.erase("timer")
	pending["attempt"] = int(pending.get("attempt", 0)) + 1
	var http: HTTPRequest = pending.get("http")
	_pending_requests[request_id] = pending
	if http == null or not is_instance_valid(http):
		_cleanup_request(request_id)
		evaluation_failed.emit(TypeSafeAPIConnectionError.new("Retry failed: HTTP client was freed."))
		return
	TypeSafeLogger.debug("Retrying system_one request (attempt %d)." % int(pending["attempt"]))
	var error: Error
	if pending.get("is_raw", false):
		error = http.request_raw(config.system_one_url(), pending.get("headers", PackedStringArray()), HTTPClient.METHOD_POST, pending.get("raw_body", PackedByteArray()))
	else:
		error = http.request(config.system_one_url(), pending.get("headers", PackedStringArray()), HTTPClient.METHOD_POST, JSON.stringify(pending.get("payload", {})))
	if error != OK:
		_cleanup_request(request_id)
		evaluation_failed.emit(TypeSafeAPIConnectionError.new("Failed to resend request: %s" % error))


func _cleanup_request(request_id: int) -> void:
	if _pending_requests.has(request_id):
		var pending: Dictionary = _pending_requests[request_id]
		var http: HTTPRequest = pending.get("http")
		var timer: Timer = pending.get("timer")
		_pending_requests.erase(request_id)
		if timer != null and is_instance_valid(timer):
			timer.stop()
			timer.queue_free()
		if http != null and is_instance_valid(http):
			if http.request_completed.is_connected(_on_request_completed):
				http.request_completed.disconnect(_on_request_completed)
			http.queue_free()


func _headers_to_dict(headers: PackedStringArray) -> Dictionary:
	var dict := {}
	for h in headers:
		var parts := h.split(":", true, 1)
		if parts.size() == 2:
			dict[str(parts[0]).strip_edges()] = str(parts[1]).strip_edges()
	return dict


func enter() -> TypeSafeClient:
	if not is_inside_tree():
		var tree := Engine.get_main_loop() as SceneTree
		if tree != null:
			tree.root.add_child(self)
	return self


func close() -> void:
	for request_id in _pending_requests.keys():
		_cleanup_request(request_id)
	if models != null and is_instance_valid(models):
		models.close()
	if is_inside_tree():
		queue_free()
	else:
		call_deferred("free")


func exit() -> void:
	close()

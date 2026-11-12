extends SceneTree
## Temporary headless parity check against the Python SDK behavior.
## Run: Godot_v4.7.2 --headless --path <project> --script res://tests/parity_check.gd

var _fails: int = 0


func check(p_cond: bool, p_label: String) -> void:
	if p_cond:
		print("PASS: ", p_label)
	else:
		_fails += 1
		printerr("FAIL: ", p_label)


func _payload_contains(p_val: Variant, p_needle: String) -> bool:
	if p_val is String:
		return (p_val as String).contains(p_needle)
	if p_val is Dictionary:
		for k in p_val:
			if _payload_contains((p_val as Dictionary)[k], p_needle):
				return true
		return false
	if p_val is Array:
		for item in p_val:
			if _payload_contains(item, p_needle):
				return true
		return false
	return false


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	# --- Questions: Python-style constructors + wire format ---
	var n := Noul.new("Is this about billing?")
	check(n.to_dict() == {"type": "noul", "instructions": "Is this about billing?"}, "noul to_dict")
	var n2 := Noul.new("Q?", {"true": "yes it is", "false": null})
	var n2d := n2.to_dict()
	check(n2d["criteria"]["true"] == "yes it is" and n2d["criteria"]["false"] == null, "noul structured criteria + null")
	var c := Choice.new("Tone?", {"calm": null, "angry": "mad"})
	var cd := c.to_dict()
	check(cd == {"type": "choice", "instructions": "Tone?", "criteria": {"calm": null, "angry": "mad"}}, "choice to_dict with null option")
	var s := Score.new("Urgent?", ["low", "high"])
	check(s.to_dict() == {"type": "score", "instructions": "Urgent?", "criteria": ["low", "high"]}, "score to_dict")
	var nstruct := Noul.new({"question": "Same person?", "candidate": {"name": "John"}})
	check(typeof(nstruct.to_dict()["instructions"]) == TYPE_DICTIONARY, "structured instructions dict")

	# --- Box Question Primitive ---
	var bx := Box.new("Find the coffee mug")
	check(bx.to_dict() == {"type": "box", "instructions": "Find the coffee mug"}, "box to_dict with instructions")
	var bx_empty := Box.new()
	check(bx_empty.to_dict() == {"type": "box"}, "box to_dict empty instructions")

	# --- BoxCoordinates & BoxAnswer ---
	var coords := BoxCoordinates.new(0.2, 0.8, 0.1, 0.7)
	check(coords.to_dict() == {"top": 0.2, "bottom": 0.8, "left": 0.1, "right": 0.7}, "box coordinates to_dict")
	var rect := coords.to_rect2(100.0, 200.0)
	check(rect.position.x == 10.0 and rect.position.y == 40.0 and rect.size.x == 60.0 and rect.size.y == 120.0, "box coordinates to_rect2 scaling")
	var inverted := BoxCoordinates.new(0.8, 0.2, 0.7, 0.1).to_rect2(100.0, 200.0)
	check(inverted.size.x > 0.0 and inverted.size.y > 0.0, "inverted coordinates abs() conversion")

	var ba_dict := {
		"type": "box",
		"box": {"top": 0.25, "bottom": 0.75, "left": 0.15, "right": 0.65},
		"confidence": 0.94,
	}
	var ba := BoxAnswer.from_dict(ba_dict)
	check(ba.type == "box" and ba.box.top == 0.25 and ba.confidence == 0.94 and ba.has_confidence(), "box answer parse + confidence")
	var ba_null := BoxAnswer.from_dict({"type": "box", "box": {"top": 0.0, "bottom": 1.0, "left": 0.0, "right": 1.0}, "confidence": null})
	check(not ba_null.has_confidence() and ba_null.get_confidence_or(0.5) == 0.5, "box answer null confidence handling")

	# --- TypeSafeImage ---
	var png_header := PackedByteArray([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a, 0x00, 0x00])
	var img := TypeSafeImage.from_buffer(png_header)
	check(img != null and img.format == "png" and img.content_type == "image/png", "typesafe image from buffer format detect")
	check(img.reference.begins_with("<image:") and img.reference.ends_with(">"), "typesafe image reference format")
	var g_img := Image.create(32, 32, false, Image.FORMAT_RGBA8)
	var img_from_godot := TypeSafeImage.from_image(g_img)
	check(img_from_godot != null and img_from_godot.data.size() > 0 and img_from_godot.format == "png", "typesafe image from Godot Image")

	# --- AssetExtractor Non-Destructive Copy-on-Write ---
	var orig_dict := {"player": {"avatar": img, "hp": 100}}
	var orig_q := {"mug": Box.new("Find the mug")}
	var ext_res := AssetExtractor.extract(orig_dict, orig_q)
	check(orig_dict["player"]["avatar"] == img, "asset extractor does NOT mutate user dictionary")
	check(ext_res.cloned_state["player"]["avatar"] == img.reference, "asset extractor substitutes reference string in clone")
	check(ext_res.assets.has(img.reference), "asset extractor registers image in assets map")
	check(ext_res.has_images, "asset extractor flags has_images true")

	# --- AssetExtractor: over-deep / circular payloads fail loud, never ship a sentinel string ---
	var deep_state := {}
	var deep_cur: Dictionary = deep_state
	for i in range(40):
		var deep_nxt := {}
		deep_cur["child"] = deep_nxt
		deep_cur = deep_nxt
	deep_cur["leaf"] = "hello"
	var deep_res := AssetExtractor.extract(deep_state, {"q": Noul.new("Deep?")})
	check(deep_res.error_message != "" and deep_res.error_message.contains("maximum nesting depth"), "over-deep state reports depth error")
	check(not _payload_contains(deep_res.cloned_state, "__ERROR__"), "over-deep state never ships sentinel string")
	var deep_q := {}
	var deep_qcur: Dictionary = deep_q
	for i in range(40):
		var deep_qnxt := {}
		deep_qcur["child"] = deep_qnxt
		deep_qcur = deep_qnxt
	deep_qcur["leaf"] = "x"
	var deep_qres := AssetExtractor.extract({"ok": 1}, {"q": {"type": "noul", "instructions": "hi", "extra": deep_q}})
	check(deep_qres.error_message != "" and deep_qres.error_message.contains("maximum nesting depth"), "over-deep question reports depth error")
	check(not _payload_contains(deep_qres.cloned_questions, "__ERROR__"), "over-deep question never ships sentinel string")
	var cyc := {"name": "loop"}
	cyc["self"] = cyc
	var cyc_res := AssetExtractor.extract(cyc, {"q": Noul.new("Cycle?")})
	check(cyc_res.error_message != "" and cyc_res.error_message.contains("circular"), "circular state reports depth error")
	check(not _payload_contains(cyc_res.cloned_state, "__ERROR__"), "circular state never ships sentinel string")

	# --- TypeSafeMultipart RFC 7578 Encoding ---
	var mp_res := TypeSafeMultipart.encode_request("{\"model\":\"jev-latest\"}", {img.reference: img})
	check(mp_res["content_type"].begins_with("multipart/form-data; boundary="), "multipart content type header")
	var mp_body: PackedByteArray = mp_res["body"]
	check(mp_body.size() > 0, "multipart body encoded")
	var mp_str := mp_body.get_string_from_utf8()
	check(mp_str.contains("name=\"request\"") and mp_str.contains("name=\"asset-0\""), "multipart parts named properly")

	var client := TypeSafeClient.new("test-key-123")

	# --- Validation (mirrors Python: nonempty questions, nonempty score criteria) ---
	check(client._validate_questions({}) == ERR_INVALID_PARAMETER, "empty questions rejected")
	check(client._validate_questions({"a": Score.new("Q?", [])}) == ERR_INVALID_PARAMETER, "empty score criteria rejected")
	check(client._validate_questions({"a": {"type": "score", "instructions": "Q?", "criteria": []}}) == ERR_INVALID_PARAMETER, "empty raw score criteria rejected")
	check(client._validate_questions({"a": {"type": "choice", "instructions": "Q?"}}) == ERR_INVALID_PARAMETER, "choice without criteria rejected")
	check(client._validate_questions({"box": Box.new("mug")}) == OK, "box question accepted")
	check(client._validate_questions({"box": {"type": "box", "instructions": "mug"}}) == OK, "raw box question accepted")
	var ok_q := {"billing": Noul.new("B?"), "tone": {"type": "choice", "instructions": "T?", "criteria": {"a": null}}, "u": Score.new("U?", ["l", "h"]), "loc": Box.new("L?")}
	check(client._validate_questions(ok_q) == OK, "mixed object+raw questions accepted")
	check(client.system_one(null, ok_q) == ERR_INVALID_PARAMETER, "null state rejected")

	# --- Payload: model/state/questions + extra_body last-write-wins ---
	var payload := client._prepare_system_one("hello", {"b": Noul.new("B?")}, null, {"beam_width": 4, "model": "custom"})
	check(payload["model"] == "custom" and payload["state"] == "hello" and payload["questions"]["b"]["type"] == "noul" and payload["beam_width"] == 4, "extra_body shallow merge wins")
	var payload2 := client._prepare_system_one({"doc": "x"}, {"b": Noul.new("B?")}, "jev", {})
	check(payload2["model"] == "jev", "per-call model override")

	# --- Headers: auth + protected extras ---
	var h := client._build_headers({"X-Custom": "v", "Authorization": "hacked", "Accept": "text/plain"})
	var hd := client._headers_to_dict(h)
	check(hd.get("Authorization") == "Bearer test-key-123", "authorization protected")
	check(hd.get("Accept") == "application/json", "accept protected")
	check(hd.get("X-Custom") == "v", "custom header passes")
	var h_danger := client._build_headers({}, "application/json", true)
	var hd_danger := client._headers_to_dict(h_danger)
	check(hd_danger.get("TypeSafe-Danger-Zone-Images") == "true", "danger zone header automatically injected")

	# --- Response parsing ---
	var raw := {
		"model": "jev-1.14.0",
		"usage": {"input_tokens": 296, "output_tokens": 20},
		"answers": {
			"is_urgent": {"type": "noul", "noul": 0.95},
			"dept": {"type": "choice", "choice": "billing", "confidence": 0.81, "probabilities": {"billing": 0.88, "technical": 0.12}},
			"frus": {"type": "score", "score": 1.05, "confidence": 0.92, "legend": {"0": "Calm", "1": "Frustrated"}, "probabilities": {"0": 0.0, "1": 0.95, "2": 0.05}},
			"target": {"type": "box", "box": {"top": 0.1, "bottom": 0.9, "left": 0.2, "right": 0.8}, "confidence": 0.96},
			"future": {"type": "quantum", "value": 1},
		},
	}
	var resp := SystemOneResponse.from_dict(raw, {"X-Typesafe-Request-Id": "req-1"}, {"status": 200})
	check(resp.model == "jev-1.14.0", "response model")
	check(resp.nouls["is_urgent"].noul == 0.95, "noul answer")
	check(resp.choices["dept"].choice == "billing" and resp.choices["dept"].confidence == 0.81, "choice answer + confidence")
	check(resp.scores["frus"].score == 1.05 and resp.scores["frus"].legend.has(1) and resp.scores["frus"].probabilities.has(1), "score answer int keys")
	check(resp.has_box("target") and resp.boxes["target"].box.top == 0.1 and resp.boxes["target"].confidence == 0.96, "box answer in response")
	check(resp.answers.size() == 4, "unknown answer kind skipped while box is kept")
	check(resp.request_id == "req-1", "request_id from header")
	check(resp.usage.input_tokens == 296 and resp.usage.output_tokens == 20, "usage tokens")
	var resp2 := SystemOneResponse.from_dict({"model": "m", "answers": {}}, {}, {})
	check(resp2.usage.input_tokens == null and resp2.usage.output_tokens == null, "usage null when unreported")
	check(resp2.get_noul("missing") == null, "missing answer returns null")
	check(resp2.get_box("missing") == null, "missing box returns null")

	# --- Errors ---
	var rl := TypeSafeRateLimitError.new(429, {}, {"retry-after-ms": "250"}, "", "ep")
	check(rl.retry_after_ms == 250 and rl.status == 429 and rl.status_code == 429, "rate limit ms header")
	var rl2 := TypeSafeRateLimitError.new(429, {}, {"Retry-After": "2"}, "", "ep")
	check(rl2.retry_after_ms == 2000, "rate limit seconds header")
	var rl3 := TypeSafeRateLimitError.new(429, {}, {}, "", "ep")
	check(rl3.retry_after_ms == null, "rate limit absent -> null")
	var e401 := client._create_api_error(401, {"message": "bad key"}, {})
	check(e401 is TypeSafeAuthenticationError and e401.request_id == null, "401 maps + null request_id")
	check(client._create_api_error(400, {}, {}) is TypeSafeBadRequestError, "400 maps")
	check(client._create_api_error(422, {}, {}) is TypeSafeUnprocessableEntityError, "422 maps")
	check(client._create_api_error(503, {}, {}) is TypeSafeInternalServerError, "5xx maps")

	# --- RetryPolicy parity ---
	var rp := RetryPolicy.default()
	check(rp.max_retries == 2 and rp.backoff_initial == 0.5 and rp.backoff_max == 5.0 and rp.backoff_jitter == 0.25 and rp.timeout == 30.0, "retry defaults")
	check(rp.http_statuses.has(408) and rp.http_statuses.has(429) and rp.http_statuses.has(500) and rp.http_statuses.has(599) and not rp.http_statuses.has(400), "retry statuses 408/429/500-599")
	check(rp.is_retryable(TypeSafeRateLimitError.new(429, {}, {}, "", "e")), "429 retryable")
	check(not rp.is_retryable(TypeSafeBadRequestError.new(400, {}, {}, "", "e")), "400 not retryable")
	check(rp.is_retryable(TypeSafeAPIConnectionError.new("x")), "connection retryable")
	check(rp.is_retryable(TypeSafeAPITimeoutError.new(1.0)), "timeout retryable")
	var rp0 := RetryPolicy.new(2, 0.5, 5.0, 0.0)
	check(rp0.calculate_backoff(1) == 0.5 and rp0.calculate_backoff(2) == 1.0 and rp0.calculate_backoff(20) == 5.0, "backoff doubling + cap")
	check(rp.get_retry_after({"Retry-After": "2"}) == 2.0 and rp.get_retry_after({"retry-after-ms": "250"}) == 0.25 and rp.get_retry_after({}) == -1.0, "retry-after headers")
	check(not client._within_budget(RetryPolicy.no_retry(), 0, 0.0, {}), "no_retry never retries")

	# --- Config / constants ---
	check(TypeSafeConstants.DEFAULT_BASE_URL == "https://api.typesafe.ai", "const base url")
	check(TypeSafeConstants.DEFAULT_MODEL == "jev-latest", "const model")
	check(TypeSafeConstants.DEFAULT_TIMEOUT == 10.0, "const timeout")
	var cfg := TypeSafeConfig.resolve(null, null, null, -1.0, {})
	check(cfg.base_url == "https://api.typesafe.ai" and cfg.default_model == "jev-latest" and cfg.timeout == 10.0, "config defaults")
	check(cfg.system_one_url() == "https://api.typesafe.ai/v1/systemone" and cfg.models_url() == "https://api.typesafe.ai/v1/models", "endpoint urls")
	var cfg2 := TypeSafeConfig.resolve("", null, null, -1.0, {})
	check(cfg2.api_key == "", "explicit empty key does not fall back")
	var cfg3 := TypeSafeConfig.resolve("k", "https://gw.test/", null, -1.0, {})
	check(cfg3.base_url == "https://gw.test" and cfg3.system_one_url() == "https://gw.test/v1/systemone", "custom base url")

	# --- Models response ---
	var lm := ListModelsResponse.from_dict({"models": [{"name": "jev-latest", "description": "d", "release_date": "2026-01-01"}], "extra": 1}, {"x-typesafe-request-id": "m-1"}, {})
	check(lm.models.size() == 1 and lm.models[0].name == "jev-latest" and lm.request_id == "m-1", "models list parse")

	var rpcustom := RetryPolicy.new(1, 0.5, 5.0, 0.0, [429], true, true, true, [], null, 10.0)
	check(rpcustom.http_statuses == [429], "custom statuses assign")
	check(rpcustom.is_retryable(TypeSafeRateLimitError.new(429, {}, {}, "", "e")) and not rpcustom.is_retryable(TypeSafeInternalServerError.new(503, {}, {}, "", "e")), "custom statuses honored")

	# --- Async client parity ---
	var aclient := AsyncTypeSafeClient.new("k")
	check(aclient is TypeSafeClient and aclient.config.default_model == "jev-latest", "async client constructs")

	# Clean up clients to ensure 0 ObjectDB leaks on exit
	client.close()
	aclient.close()

	print("----")
	if _fails == 0:
		print("ALL PARITY CHECKS PASSED")
	else:
		printerr("FAILURES: %d" % _fails)

	await process_frame
	await process_frame
	quit(_fails)

extends SceneTree
## Exhaustive End-User Experience Verification Test
## Simulates how a real game developer integrates and uses the SDK in a Godot project.

var _fails: int = 0


func check(p_cond: bool, p_label: String) -> void:
	if p_cond:
		print("PASS: [End-User] ", p_label)
	else:
		_fails += 1
		printerr("FAIL: [End-User] ", p_label)


func _init() -> void:
	_run_all.call_deferred()


func _run_all() -> void:
	print("==================================================")
	print("STARTING END-USER EXPERIENCE STABILITY TEST SUITE")
	print("==================================================")

	await _test_real_file_and_box_detection()
	await _test_async_await_flow_with_image()
	await _test_explicit_assets_flow()
	await _test_graceful_error_handling()
	await _test_concurrent_multimodal_requests()

	print("==================================================")
	if _fails == 0:
		print("ALL END-USER STABILITY TESTS PASSED CLEANLY!")
	else:
		printerr("END-USER STABILITY TESTS FAILED: %d errors" % _fails)
	print("==================================================")

	await process_frame
	await process_frame
	quit(_fails)


## Test 1: Real file loading from res:// and object localization with Box
func _test_real_file_and_box_detection() -> void:
	print("\n--- Test 1: Real File Loading & Box Detection ---")
	var icon_path := "res://addons/typesafe_sdk/icon.png"
	var icon_img := TypeSafeImage.from_file(icon_path)
	check(icon_img != null and icon_img.data.size() > 0, "TypeSafeImage.from_file loaded res:// icon.png")
	check(icon_img.format == "png", "detected icon format as png")

	var client := TypeSafeClient.new()
	get_root().add_child(client)
	await process_frame

	var responses: Array = []
	client.evaluation_completed.connect(func(r: SystemOneResponse) -> void: responses.append(r))
	client.evaluation_failed.connect(func(e: TypeSafeError) -> void: responses.append(e))

	var err := client.system_one(
		{"app_icon": icon_img, "meta": {"project": "typesafe_sdk"}},
		{
			"is_logo": Noul.new("Is this an application logo or icon?"),
			"logo_box": Box.new("The logo in `app_icon`")
		}
	)
	check(err == OK, "system_one accepted real image payload")
	check(await _wait_for(func() -> bool: return responses.size() > 0, 60.0), "live response received")

	if responses.size() > 0 and responses[0] is SystemOneResponse:
		var resp: SystemOneResponse = responses[0]
		check(resp.has_noul("is_logo") and resp.nouls["is_logo"].noul > 0.5, "noul evaluated logo correctly")
		check(resp.has_box("logo_box"), "box question evaluated successfully")
		var box_ans: BoxAnswer = resp.get_box("logo_box")
		check(box_ans != null and box_ans.box != null, "box answer contains valid BoxCoordinates")
		var rect: Rect2 = box_ans.box.to_rect2(128.0, 128.0)
		check(rect.size.x > 0.0 and rect.size.y > 0.0, "to_rect2 converted to valid positive Rect2")
		print("Detected logo at Rect2: ", rect, " with confidence: ", box_ans.confidence)
	else:
		var err_msg := (responses[0] as TypeSafeError).to_string() if responses.size() > 0 and responses[0] is TypeSafeError else str(responses)
		printerr("Test 1 failed with error: ", err_msg)
		check(false, "received valid SystemOneResponse for real image")

	client.close()
	await process_frame


## Test 2: Idiomatic GDScript await flow with AsyncTypeSafeClient
func _test_async_await_flow_with_image() -> void:
	print("\n--- Test 2: Idiomatic Async/Await Flow with AsyncTypeSafeClient ---")
	var g_img := Image.create(128, 128, false, Image.FORMAT_RGBA8)
	g_img.fill(Color(0.2, 0.7, 0.3, 1.0)) # Green texture
	var green_ts_img := TypeSafeImage.from_image(g_img, "png")

	var aclient := AsyncTypeSafeClient.new()
	get_root().add_child(aclient)
	await process_frame

	var outcome: Array = []
	aclient.evaluation_completed.connect(func(r: SystemOneResponse) -> void: outcome.append(r))
	aclient.evaluation_failed.connect(func(e: TypeSafeError) -> void: outcome.append(e))

	aclient.system_one(
		green_ts_img,
		{"green_canvas": Box.new("The green area")}
	)

	check(await _wait_for(func() -> bool: return outcome.size() > 0, 60.0), "await flow received response")
	if outcome.size() > 0 and outcome[0] is SystemOneResponse:
		var resp: SystemOneResponse = outcome[0]
		check(resp != null and resp.model.begins_with("jev"), "response model is jev")
		check(resp.has_box("green_canvas"), "response has green_canvas box")
		var b := resp.get_box("green_canvas")
		check(b.box.bottom >= b.box.top and b.box.right >= b.box.left, "coordinates are ordered properly")
		print("Canvas box edges: top=", b.box.top, " bottom=", b.box.bottom, " left=", b.box.left, " right=", b.box.right)
	else:
		var err_msg := (outcome[0] as TypeSafeError).to_string() if outcome.size() > 0 and outcome[0] is TypeSafeError else str(outcome)
		printerr("Test 2 failed with: ", err_msg)
		check(false, "async call succeeded")

	aclient.aclose()
	await process_frame


## Test 3: Explicit system_one_with_assets flow
func _test_explicit_assets_flow() -> void:
	print("\n--- Test 3: Explicit system_one_with_assets Flow ---")
	var g_img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	g_img.fill(Color(0.0, 0.0, 1.0, 1.0)) # Blue texture
	var blue_img := TypeSafeImage.from_image(g_img)

	var client := TypeSafeClient.new()
	get_root().add_child(client)
	await process_frame

	var responses: Array = []
	client.evaluation_completed.connect(func(r: SystemOneResponse) -> void: responses.append(r))
	client.evaluation_failed.connect(func(e: TypeSafeError) -> void: responses.append(e))

	var err := client.system_one_with_assets(
		"Look at <custom-alias>.",
		{"is_blue": Noul.new("Is this a blue square?")},
		{"<custom-alias>": blue_img}
	)
	check(err == OK, "system_one_with_assets returned OK")
	check(await _wait_for(func() -> bool: return responses.size() > 0, 60.0), "response received for explicit asset")

	if responses.size() > 0 and responses[0] is SystemOneResponse:
		var resp: SystemOneResponse = responses[0]
		check(resp.has_noul("is_blue") and resp.nouls["is_blue"].noul > 0.5, "explicit asset noul evaluated true")
	else:
		check(false, "system_one_with_assets succeeded")

	client.close()
	await process_frame


## Test 4: Graceful Error Handling & Safety
func _test_graceful_error_handling() -> void:
	print("\n--- Test 4: Graceful Error Handling & Safety ---")

	# 1. Missing file returns null without engine crash
	var missing := TypeSafeImage.from_file("res://does_not_exist_xyz.png")
	check(missing == null, "from_file on non-existent file gracefully returns null")

	# 2. Empty buffer returns null
	var empty := TypeSafeImage.from_buffer(PackedByteArray())
	check(empty == null, "from_buffer on empty byte array returns null")

	# 3. Client rejects null state gracefully
	var client := TypeSafeClient.new()
	get_root().add_child(client)
	await process_frame

	var failed_out: Array = []
	client.evaluation_failed.connect(func(e: TypeSafeError) -> void: failed_out.append(e))

	var err := client.system_one(null, {"q": Noul.new("Test?")})
	check(err == ERR_INVALID_PARAMETER, "system_one with null state returns ERR_INVALID_PARAMETER")
	check(await _wait_for(func() -> bool: return failed_out.size() > 0, 5.0), "evaluation_failed emitted for null state")

	# 4. Bad request returns TypeSafeBadRequestError
	var bad_req_out: Array = []
	client.evaluation_failed.connect(func(e: TypeSafeError) -> void: bad_req_out.append(e))
	# Send empty criteria to force 400 Bad Request
	client.system_one("test", {"q": {"type": "choice", "instructions": "Q?", "criteria": {}}})
	check(await _wait_for(func() -> bool: return bad_req_out.size() > 0, 10.0), "evaluation_failed emitted for bad request")

	client.close()
	await process_frame


## Test 5: Concurrent Multi-Modal Requests (Text + Vision)
func _test_concurrent_multimodal_requests() -> void:
	print("\n--- Test 5: Concurrent Multi-Modal Requests ---")
	var client := TypeSafeClient.new()
	get_root().add_child(client)
	await process_frame

	var completed: Array = []
	client.evaluation_completed.connect(func(r: SystemOneResponse) -> void: completed.append(r))

	var g_img := Image.create(64, 64, false, Image.FORMAT_RGBA8)
	g_img.fill(Color(1.0, 1.0, 0.0, 1.0)) # Yellow texture
	var yellow_img := TypeSafeImage.from_image(g_img)

	# Request 1: Pure text
	client.system_one("The quick brown fox jumps over the lazy dog.", {"fox": Noul.new("Is there a fox?")})
	# Request 2: Vision with Box
	client.system_one(yellow_img, {"yellow_box": Box.new("The yellow canvas")})

	check(await _wait_for(func() -> bool: return completed.size() >= 2, 60.0), "both concurrent requests completed")
	check(completed.size() >= 2, "received 2 responses from concurrent calls")

	client.close()
	await process_frame


func _wait_for(p_cond: Callable, p_seconds: float) -> bool:
	var start := Time.get_ticks_msec()
	while not bool(p_cond.call()):
		await process_frame
		if (Time.get_ticks_msec() - start) / 1000.0 > p_seconds:
			return false
	return true

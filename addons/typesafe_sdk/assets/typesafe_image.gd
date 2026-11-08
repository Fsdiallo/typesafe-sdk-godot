class_name TypeSafeImage
extends RefCounted
## Media asset representing an image. Mirrors Python `Image`.
##
## Wraps raw image bytes, Godot engine `Image` objects, or files,
## providing a unique reference placeholder (e.g. `<image:uuid>`)
## to place anywhere inside `state` or question instructions/criteria.

var data: PackedByteArray
var content_type: String = "application/octet-stream"
var format: String = "png"
var reference: String = ""

const PNG_SIGNATURE: PackedByteArray = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]
const JPEG_SIGNATURE: PackedByteArray = [0xff, 0xd8, 0xff]


func _init(p_data: PackedByteArray = PackedByteArray(), p_content_type: String = "", p_format: String = "", p_reference: String = "") -> void:
	data = p_data
	reference = p_reference if p_reference != "" else generate_reference()
	if p_content_type != "":
		content_type = p_content_type
	if p_format != "":
		format = p_format
	elif data.size() > 0:
		_detect_format()


func _to_string() -> String:
	return reference


func get_reference() -> String:
	return reference


static func generate_reference() -> String:
	var crypto := Crypto.new()
	var random_bytes := crypto.generate_random_bytes(16)
	return "<image:%s>" % random_bytes.hex_encode()


func _detect_format() -> void:
	if _matches_signature(PNG_SIGNATURE):
		content_type = "image/png"
		format = "png"
	elif _matches_signature(JPEG_SIGNATURE):
		content_type = "image/jpeg"
		format = "jpg"
	else:
		content_type = "application/octet-stream"
		format = "png"


func _matches_signature(p_sig: PackedByteArray) -> bool:
	if data.size() < p_sig.size():
		return false
	for i in p_sig.size():
		if data[i] != p_sig[i]:
			return false
	return true


## Create a TypeSafeImage from a Godot Image instance.
## Re-encodes the image to PNG or JPEG buffer, ensuring any format
## (SVG, WebP, ViewportTexture, etc.) is serialized to API-compatible bytes.
## If p_auto_upscale is true and the image dimensions are smaller than 512x512,
## it is automatically upscaled using bilinear interpolation to meet the TypeSafe API minimum requirement.
static func from_image(p_image: Image, p_format: String = "png", p_auto_upscale: bool = true) -> TypeSafeImage:
	if p_image == null or p_image.is_empty():
		push_error("TypeSafeImage.from_image: Provided Godot Image is null or empty.")
		return null

	var working_image := p_image
	if p_auto_upscale:
		var w := p_image.get_width()
		var h := p_image.get_height()
		if w < 512 or h < 512:
			var scale_factor := maxf(512.0 / float(maxi(w, 1)), 512.0 / float(maxi(h, 1)))
			var new_w := maxi(int(ceil(float(w) * scale_factor)), 512)
			var new_h := maxi(int(ceil(float(h) * scale_factor)), 512)
			working_image = p_image.duplicate()
			working_image.resize(new_w, new_h, Image.INTERPOLATE_BILINEAR)

	var fmt := p_format.to_lower().strip_edges()
	var bytes: PackedByteArray
	var mime: String
	if fmt in ["jpg", "jpeg"]:
		bytes = working_image.save_jpg_to_buffer()
		mime = "image/jpeg"
		fmt = "jpg"
	else:
		bytes = working_image.save_png_to_buffer()
		mime = "image/png"
		fmt = "png"

	return TypeSafeImage.new(bytes, mime, fmt)


## Create a TypeSafeImage from a local file path (res://, user://, or absolute).
static func from_file(p_path: String, p_auto_upscale: bool = true) -> TypeSafeImage:
	if not FileAccess.file_exists(p_path):
		if ResourceLoader.exists(p_path):
			var res = load(p_path)
			if res is Texture2D:
				return from_image((res as Texture2D).get_image(), "png", p_auto_upscale)
			elif res is Image:
				return from_image(res as Image, "png", p_auto_upscale)
		push_error("TypeSafeImage.from_file: File does not exist at '%s'" % p_path)
		return null

	var bytes := FileAccess.get_file_as_bytes(p_path)
	if bytes.is_empty():
		if ResourceLoader.exists(p_path):
			var res = load(p_path)
			if res is Texture2D:
				return from_image((res as Texture2D).get_image(), "png", p_auto_upscale)
			elif res is Image:
				return from_image(res as Image, "png", p_auto_upscale)
		push_error("TypeSafeImage.from_file: File is empty or unreadable at '%s'" % p_path)
		return null

	if p_auto_upscale:
		var godot_img := Image.new()
		var err := godot_img.load_png_from_buffer(bytes)
		if err != OK:
			err = godot_img.load_jpg_from_buffer(bytes)
		if err == OK and not godot_img.is_empty():
			var ext := p_path.get_extension().to_lower()
			var fmt := "jpg" if ext in ["jpg", "jpeg"] else "png"
			return from_image(godot_img, fmt, true)

	var img := TypeSafeImage.new(bytes)
	# Fallback extension hint if magic byte check was indeterminate
	if img.content_type == "application/octet-stream":
		var ext := p_path.get_extension().to_lower()
		if ext in ["jpg", "jpeg"]:
			img.content_type = "image/jpeg"
			img.format = "jpg"
		elif ext == "png":
			img.content_type = "image/png"
			img.format = "png"
	return img


## Create a TypeSafeImage from raw byte buffer (PackedByteArray).
static func from_buffer(p_buffer: PackedByteArray, p_format: String = "") -> TypeSafeImage:
	if p_buffer.is_empty():
		push_error("TypeSafeImage.from_buffer: Buffer is empty.")
		return null
	return TypeSafeImage.new(p_buffer, "", p_format)


## Create a TypeSafeImage from Base64-encoded image string.
static func from_base64(p_base64_str: String, p_format: String = "") -> TypeSafeImage:
	var clean := p_base64_str.strip_edges().replace("\n", "").replace("\r", "").replace(" ", "")
	if clean == "":
		push_error("TypeSafeImage.from_base64: Base64 string is empty.")
		return null

	var bytes := Marshalls.base64_to_raw(clean)
	if bytes.is_empty():
		push_error("TypeSafeImage.from_base64: Failed to decode base64 string.")
		return null
	return TypeSafeImage.new(bytes, "", p_format)


## Returns dictionary representation for the API assets map.
## In multipart mode: {"type": "image", "part": "asset-0"}
## In JSON base64 mode: {"type": "image", "format": "png", "data_base64": "..."}
func to_asset_dict(use_multipart: bool = true, part_name: String = "") -> Dictionary:
	if use_multipart:
		return {
			"type": "image",
			"part": part_name if part_name != "" else "asset-0",
		}
	return {
		"type": "image",
		"format": format,
		"data_base64": Marshalls.raw_to_base64(data),
	}

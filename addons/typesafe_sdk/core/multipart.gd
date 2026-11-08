class_name TypeSafeMultipart
extends RefCounted
## Encodes requests with attached assets as RFC 7578 multipart/form-data payloads.

const CRLF: String = "\r\n"


class Part:
	var name: String
	var content_type: String
	var filename: String
	var data: PackedByteArray

	func _init(p_name: String, p_content_type: String, p_filename: String, p_data: PackedByteArray) -> void:
		name = p_name
		content_type = p_content_type
		filename = p_filename
		data = p_data


## Encodes a JSON request payload and a list of TypeSafeImage assets into multipart body.
## Returns a Dictionary with:
## - "content_type": "multipart/form-data; boundary=..."
## - "body": PackedByteArray
static func encode_request(p_request_json: String, p_assets: Dictionary) -> Dictionary:
	var crypto := Crypto.new()
	var boundary := crypto.generate_random_bytes(16).hex_encode()

	var parts: Array[Part] = []

	# 1. Part 1: JSON request part named 'request'
	var req_bytes := p_request_json.to_utf8_buffer()
	parts.append(Part.new("request", "application/json", "", req_bytes))

	# 2. Part 2..N: Media asset parts named 'asset-0', 'asset-1', ...
	var idx := 0
	for key in p_assets:
		var asset = p_assets[key]
		if asset is TypeSafeImage:
			var img: TypeSafeImage = asset
			var part_name := "asset-%d" % idx
			var ext := img.format if img.format != "" else "png"
			var filename := "%s.%s" % [part_name, ext]
			parts.append(Part.new(part_name, img.content_type, filename, img.data))
			idx += 1

	return encode(parts, boundary)


static func encode(p_parts: Array[Part], p_boundary: String) -> Dictionary:
	var body := PackedByteArray()
	var crlf_bytes := CRLF.to_utf8_buffer()

	for part in p_parts:
		var header := "--%s%s" % [p_boundary, CRLF]
		header += 'Content-Disposition: form-data; name="%s"' % part.name
		if part.filename != "":
			header += '; filename="%s"' % part.filename
		header += CRLF
		header += "Content-Type: %s%s" % [part.content_type, CRLF]
		header += CRLF

		body.append_array(header.to_utf8_buffer())
		body.append_array(part.data)
		body.append_array(crlf_bytes)

	var footer := "--%s--%s" % [p_boundary, CRLF]
	body.append_array(footer.to_utf8_buffer())

	return {
		"content_type": "multipart/form-data; boundary=%s" % p_boundary,
		"body": body,
	}

class_name BoxCoordinates
extends RefCounted
## Normalized bounding box edges as fractions of image dimensions.
## Vertical edges (top, bottom) are measured from the top of the image (0-1).
## Horizontal edges (left, right) are measured from the left of the image (0-1).

var top: float = 0.0
var bottom: float = 0.0
var left: float = 0.0
var right: float = 0.0


func _init(p_top: float = 0.0, p_bottom: float = 0.0, p_left: float = 0.0, p_right: float = 0.0) -> void:
	top = p_top
	bottom = p_bottom
	left = p_left
	right = p_right


func _get_property_list() -> Array[Dictionary]:
	return [
		{"name": "top", "type": TYPE_FLOAT, "usage": PROPERTY_USAGE_READ_ONLY},
		{"name": "bottom", "type": TYPE_FLOAT, "usage": PROPERTY_USAGE_READ_ONLY},
		{"name": "left", "type": TYPE_FLOAT, "usage": PROPERTY_USAGE_READ_ONLY},
		{"name": "right", "type": TYPE_FLOAT, "usage": PROPERTY_USAGE_READ_ONLY},
	]


func _to_string() -> String:
	return "BoxCoordinates(top=%s, bottom=%s, left=%s, right=%s)" % [str(top), str(bottom), str(left), str(right)]


static func from_dict(p_dict: Dictionary) -> BoxCoordinates:
	var coords := BoxCoordinates.new()
	coords.top = float(p_dict.get("top", 0.0))
	coords.bottom = float(p_dict.get("bottom", 0.0))
	coords.left = float(p_dict.get("left", 0.0))
	coords.right = float(p_dict.get("right", 0.0))
	return coords


func to_dict() -> Dictionary:
	return {
		"top": top,
		"bottom": bottom,
		"left": left,
		"right": right,
	}


## Convert normalized coordinates to a Godot Rect2 (x, y, width, height).
## Scales by optional image dimensions (default 1.0 for normalized coordinates).
## Uses .abs() to ensure positive width and height if model predictions are inverted.
func to_rect2(image_width: float = 1.0, image_height: float = 1.0, clamp_bounds: bool = false) -> Rect2:
	var l := clampf(left, 0.0, 1.0) if clamp_bounds else left
	var r := clampf(right, 0.0, 1.0) if clamp_bounds else right
	var t := clampf(top, 0.0, 1.0) if clamp_bounds else top
	var b := clampf(bottom, 0.0, 1.0) if clamp_bounds else bottom
	var rect := Rect2(l * image_width, t * image_height, (r - l) * image_width, (b - t) * image_height)
	return rect.abs()

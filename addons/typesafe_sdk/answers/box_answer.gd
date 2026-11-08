class_name BoxAnswer
extends RefCounted
## Located bounding box with normalized edge coordinates and confidence.
## Mirrors Python `BoxAnswer`.

var type: String = "box"
var box: BoxCoordinates
var confidence: Variant = null


func _init(p_box: BoxCoordinates = null, p_confidence: Variant = null) -> void:
	box = p_box if p_box != null else BoxCoordinates.new()
	if p_confidence != null:
		confidence = float(p_confidence)
	else:
		confidence = null


func _get_property_list() -> Array[Dictionary]:
	return [
		{"name": "type", "type": TYPE_STRING, "usage": PROPERTY_USAGE_READ_ONLY},
		{"name": "box", "type": TYPE_OBJECT, "usage": PROPERTY_USAGE_READ_ONLY},
		{"name": "confidence", "type": TYPE_FLOAT, "usage": PROPERTY_USAGE_READ_ONLY},
	]


func _to_string() -> String:
	return "BoxAnswer(box=%s, confidence=%s)" % [str(box), str(confidence)]


## Returns true if the model returned a confidence score for this box.
func has_confidence() -> bool:
	return confidence != null


## Safe confidence getter avoiding Nil comparison errors when confidence is null.
func get_confidence_or(p_default: float = 0.0) -> float:
	if confidence != null:
		return float(confidence)
	return p_default


static func from_dict(p_dict: Dictionary) -> BoxAnswer:
	var answer := BoxAnswer.new()
	answer.type = str(p_dict.get("type", "box"))
	var box_val = p_dict.get("box", {})
	if typeof(box_val) == TYPE_DICTIONARY:
		answer.box = BoxCoordinates.from_dict(box_val)
	else:
		answer.box = BoxCoordinates.new()

	if p_dict.has("confidence") and p_dict["confidence"] != null:
		answer.confidence = float(p_dict["confidence"])
	else:
		answer.confidence = null
	return answer


func to_dict() -> Dictionary:
	return {
		"type": type,
		"box": box.to_dict() if box != null else {},
		"confidence": confidence,
	}

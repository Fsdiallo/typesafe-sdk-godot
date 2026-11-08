class_name Box
extends Question
## Box question for object localization. Mirrors Python `Box`.
## Finds where something is in an image, returning bounding edges and confidence.
## Requires an image in the request and uses model Jev 1.14+.

func _init(p_instructions: Variant = null) -> void:
	super._init(p_instructions)


func get_type() -> String:
	return "box"


func to_dict() -> Dictionary:
	var data := super.to_dict()
	data["type"] = "box"
	return data

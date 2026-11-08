class_name AssetExtractor
extends RefCounted
## Performs non-destructive copy-on-write traversal of request payloads,
## extracting TypeSafeImage assets and substituting them with reference strings.

const MAX_DEPTH: int = 32

class Result:
	var cloned_state: Variant
	var cloned_questions: Dictionary = {}
	var assets: Dictionary = {} # reference_str -> TypeSafeImage
	var has_images: bool = false
	var error_message: String = ""


static func extract(p_state: Variant, p_questions: Dictionary, p_explicit_assets: Variant = null) -> Result:
	var result := Result.new()
	var known_assets: Dictionary = {} # ref_str -> TypeSafeImage

	# 1. Register explicit assets if provided
	if p_explicit_assets != null:
		if typeof(p_explicit_assets) == TYPE_DICTIONARY:
			for k in p_explicit_assets:
				var asset = p_explicit_assets[k]
				if asset is TypeSafeImage:
					known_assets[str(k)] = asset
					result.assets[str(k)] = asset
		elif typeof(p_explicit_assets) == TYPE_ARRAY:
			for asset in p_explicit_assets:
				if asset is TypeSafeImage:
					known_assets[(asset as TypeSafeImage).reference] = asset
					result.assets[(asset as TypeSafeImage).reference] = asset
		elif p_explicit_assets is TypeSafeImage:
			known_assets[(p_explicit_assets as TypeSafeImage).reference] = p_explicit_assets
			result.assets[(p_explicit_assets as TypeSafeImage).reference] = p_explicit_assets

	# 2. Extract and clone state
	var visited := {}
	var state_res = _clone_and_extract(p_state, result.assets, known_assets, visited, 0)
	if state_res is String and state_res.begins_with("__ERROR__:"):
		result.error_message = state_res.trim_prefix("__ERROR__:")
		return result
	result.cloned_state = state_res

	# 3. Extract and clone questions
	for q_key in p_questions:
		var q = p_questions[q_key]
		if q is Question:
			var q_dict: Dictionary = (q as Question).to_dict()
			var cloned_q = _clone_and_extract(q_dict, result.assets, known_assets, visited, 0)
			result.cloned_questions[q_key] = cloned_q
		elif typeof(q) == TYPE_DICTIONARY:
			var cloned_q = _clone_and_extract(q, result.assets, known_assets, visited, 0)
			result.cloned_questions[q_key] = cloned_q
		else:
			result.cloned_questions[q_key] = q

	result.has_images = result.assets.size() > 0
	return result


static func _clone_and_extract(p_val: Variant, out_assets: Dictionary, known_assets: Dictionary, visited: Dictionary, depth: int) -> Variant:
	if depth > MAX_DEPTH:
		return "__ERROR__:Payload exceeds maximum nesting depth (%d). Possible circular reference." % MAX_DEPTH

	if p_val is TypeSafeImage:
		var img: TypeSafeImage = p_val
		out_assets[img.reference] = img
		return img.reference

	match typeof(p_val):
		TYPE_DICTIONARY:
			var dict_val: Dictionary = p_val
			var cloned_dict := {}
			for k in dict_val:
				# Object keys must remain text (not replaced)
				var key_str := str(k)
				cloned_dict[key_str] = _clone_and_extract(dict_val[k], out_assets, known_assets, visited, depth + 1)
			return cloned_dict

		TYPE_ARRAY:
			var arr_val: Array = p_val
			var cloned_arr := []
			cloned_arr.resize(arr_val.size())
			for i in arr_val.size():
				cloned_arr[i] = _clone_and_extract(arr_val[i], out_assets, known_assets, visited, depth + 1)
			return cloned_arr

		TYPE_STRING:
			var str_val: String = p_val
			# Check if any known asset reference is inside this string
			for ref_key in known_assets:
				if ref_key in str_val:
					out_assets[ref_key] = known_assets[ref_key]
			return str_val

		_:
			return p_val

class_name RushFirestoreCodec
extends RefCounted
## Deterministic hashes exclude transport timestamps and preserve numeric identity.
static func canonical(value: Variant) -> Variant:
	if value is Dictionary:
		var result: Dictionary = {}
		var keys: Array = value.keys()
		keys.sort()
		for key: String in keys:
			result[key] = canonical(value[key])
		return result
	if value is Array:
		var result: Array = []
		for item: Variant in value:
			result.append(canonical(item))
		return result
	if value is float and is_finite(value) and value==floor(value):
		return int(value)
	return value
static func digest(value: Dictionary) -> String:
	return JSON.stringify(canonical(value)).sha256_text()
static func fields(value: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for key: String in value:
		result[key] = encode(value[key])
	return result
static func encode(value: Variant) -> Dictionary:
	if value==null: return {"nullValue":null}
	if value is bool: return {"booleanValue":value}
	if value is int: return {"integerValue":str(value)}
	if value is float:
		return {"integerValue":str(int(value))} if is_finite(value) and value==floor(value) else {"doubleValue":value}
	if value is String: return {"stringValue":value}
	if value is Dictionary: return {"mapValue":{"fields":fields(value)}}
	if value is Array:
		var result: Array = []
		for item: Variant in value: result.append(encode(item))
		return {"arrayValue":{"values":result}}
	return {"nullValue":null}
static func decode_fields(value: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for key: String in value:
		result[key] = decode(value[key]) if value[key] is Dictionary else null
	return result
static func decode(value: Dictionary) -> Variant:
	if value.has("stringValue"): return String(value.stringValue)
	if value.has("integerValue"): return int(value.integerValue)
	if value.has("doubleValue"): return float(value.doubleValue)
	if value.has("booleanValue"): return bool(value.booleanValue)
	if value.has("timestampValue"): return String(value.timestampValue)
	if value.has("mapValue"): return decode_fields(value.mapValue.get("fields",{}))
	if value.has("arrayValue"):
		var result: Array = []
		for item: Dictionary in value.arrayValue.get("values",[]): result.append(decode(item))
		return result
	return null

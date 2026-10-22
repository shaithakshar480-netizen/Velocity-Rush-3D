class_name RushDrivingData
extends RefCounted
static var data: Dictionary = {}
static func get_data() -> Dictionary:
	if data.is_empty():
		data = JSON.parse_string(FileAccess.get_file_as_string("res://Data/DrivingPass.json"))
	return data

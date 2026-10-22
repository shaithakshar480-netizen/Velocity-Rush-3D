class_name RushStoreCatalog
extends RefCounted
static var data: Dictionary = {}
static var presentation: Dictionary = {}
static func prepare() -> void:
	if data.is_empty():
		data = JSON.parse_string(FileAccess.get_file_as_string("res://Data/StoreCatalog.json"))
	if presentation.is_empty():
		presentation = JSON.parse_string(FileAccess.get_file_as_string("res://Data/StorePresentation.json"))
static func find_offer(group: String, id: String) -> Dictionary:
	prepare()
	for offer: Dictionary in data.get(group,[]):
		if String(offer.id)==id:
			return offer
	return {}

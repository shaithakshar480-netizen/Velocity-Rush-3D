@tool
extends EditorPlugin
var exporter: EditorExportPlugin
func _enter_tree() -> void:
	exporter = AdsExport.new()
	add_export_plugin(exporter)
func _exit_tree() -> void:
	remove_export_plugin(exporter)
class AdsExport extends EditorExportPlugin:
	func _get_name() -> String: return "VelocityRushAdsBridge"
	func _supports_platform(platform: EditorExportPlatform) -> bool:
		return platform is EditorExportPlatformAndroid
	func _configured() -> bool:
		if not FileAccess.file_exists("res://addons/rush_ads/bin/RushAdsBridge.aar"): return false
		var stamp: String = "res://addons/rush_ads/bin/RushAdsBridge.config.sha256"
		if not FileAccess.file_exists(stamp) or FileAccess.get_sha256("res://Data/AdsConfig.json")!=FileAccess.get_file_as_string(stamp).strip_edges():
			push_warning("Ads bridge/config changed. Rebuild AdsBridge; ads omitted from this export.")
			return false
		var config: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://Data/AdsConfig.json"))
		if not config is Dictionary: return false
		var mode: String = String(config.get("mode",""))
		if mode not in ["TEST","PRODUCTION"]: return false
		var ids: Variant = config.get("test" if mode=="TEST" else "production",{})
		if not ids is Dictionary: return false
		if mode=="PRODUCTION" and ids.get("privacy_setup_complete",false)!=true: return false
		for key: String in ["app_id","rewarded_id","interstitial_id"]:
			if not ids.get(key) is String or String(ids[key]).is_empty(): return false
			if mode=="PRODUCTION" and String(ids[key]).contains("3940256099942544"): return false
		return true
	func _get_android_libraries(_platform: EditorExportPlatform, _debug: bool) -> PackedStringArray:
		return PackedStringArray(["rush_ads/bin/RushAdsBridge.aar"]) if _configured() else PackedStringArray()
	func _get_android_dependencies(_platform: EditorExportPlatform, _debug: bool) -> PackedStringArray:
		return PackedStringArray(["com.google.android.gms:play-services-ads:24.1.0","com.google.android.ump:user-messaging-platform:3.1.0"]) if _configured() else PackedStringArray()

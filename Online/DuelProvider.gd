class_name RushDuelProvider
extends Node
signal received(packet: Dictionary)
signal disconnected
func open(_endpoint: String, _token: String) -> bool: return false
func send(_packet: Dictionary) -> bool: return false
func close() -> void: pass

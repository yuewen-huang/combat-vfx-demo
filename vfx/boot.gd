extends Control
## Start with a lightweight scene so the initial gallery can show loading too.
func _ready() -> void:
	_enter.call_deferred()

func _enter() -> void:
	preload("res://vfx/screen_loading.gd").open_scene(self, "res://main.tscn", "正在打开特效工作室")

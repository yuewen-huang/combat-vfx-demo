class_name RenderCaps
## Whether the game runs without a graphics card (a software renderer) and every effect
## should use its light 兜底 path. Default is the full GPU path; nothing degrades on its own.
## Detected once: `-- --fallback` / `-- --no-fallback` force it, as does the project setting
## combat_vfx/force_fallback; otherwise a software adapter name turns it on.

static var fallback := false
## Why fallback is on, for the on-screen note, e.g. "软件渲染：llvmpipe" or "手动开启".
static var reason := ""
static var _detected := false

const SOFTWARE := ["llvmpipe", "softpipe", "lavapipe", "swiftshader", "microsoft basic render", "warp"]

static func is_software(adapter: String) -> bool:
	var lower := adapter.to_lower()
	return SOFTWARE.any(func(word: String) -> bool: return lower.contains(word))

static func detect() -> void:
	if _detected: return
	_detected = true
	var args := OS.get_cmdline_user_args()
	if "--no-fallback" in args:
		fallback = false
		reason = ""
	elif "--fallback" in args or bool(ProjectSettings.get_setting("combat_vfx/force_fallback", false)):
		fallback = true
		reason = "手动开启"
	elif DisplayServer.get_name() != "headless":
		var adapter := RenderingServer.get_video_adapter_name()
		fallback = is_software(adapter) or is_software(RenderingServer.get_video_adapter_vendor())
		reason = "软件渲染：%s" % adapter if fallback else ""

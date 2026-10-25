extends RefCounted
## Material identity is independent of formation and colour.
const KEYS := ["leaf", "feather", "sand"]
const NAMES := {"leaf": "落叶", "feather": "羽毛", "sand": "沙漠"}
const DEFAULTS := {"material": "leaf",
	"leaf_curl": 0.55, "leaf_sway": 1.0, "feather_bend": 0.65, "feather_split": 0.45,
	"sand_grain": 1.0, "sand_dust": 0.7, "sand_settle": 1.0}
## [field, label, min, max, step]. Only meaningful properties appear for each material.
const FIELDS := {
	"leaf": [["leaf_curl", "叶片卷曲", 0, 1, 0.05], ["leaf_sway", "摇摆幅度", 0, 2, 0.05]],
	"feather": [["feather_bend", "羽片柔度", 0, 1, 0.05], ["feather_split", "羽枝分叉", 0, 1, 0.05]],
	"sand": [["sand_grain", "砂砾粒径", 0.4, 2, 0.05], ["sand_dust", "细尘比例", 0, 1, 0.05], ["sand_settle", "沉降强度", 0, 2, 0.05]],
}

static func merge_defaults(event: Dictionary) -> Dictionary:
	var values := DEFAULTS.duplicate()
	values.merge(event, true)
	if not String(values.material) in KEYS: values.material = "leaf"
	for fields: Array in FIELDS.values():
		for field: Array in fields:
			values[field[0]] = clampf(float(values[field[0]]), float(field[2]), float(field[3]))
	return values

# 多技能编排

作品库 → 多技能 → 添加招式 → 连线 → 编辑单招 → 应用并返回 → 保存整段作品。
公共入口为 `flow_editor.tscn`；`editor.tscn` 与 `quake_editor.tscn` 兼容打开同一流程图。
`node_editor.tscn` 是节点内部参数页。

- 一条线：顺序衔接；一对多：并行；多对一：等待全部前招。
- 可以设置开始偏移、与前招同时开始、自动或手动衔接时长。衔接时长不截断前招残留。
- 保存包含 `_flow` 图与编译后的普通事件；原作品首次保存保留 `.bak`。
- 单招编辑带入真实前置状态。孤立消散提供临时自然材质云团，辅助事件不写入作品。
- 可混用原有月牙、轨迹、水墨、爪痕、魔法、地震、群体和屏幕演出。
- F11 / Alt+Enter 切换全屏，退出恢复原窗口。

验证：`godot --headless --path . --script res://tools/verify_public.gd`。
原生窗口验证：`godot --path . --script res://tools/verify_fullscreen.gd`。

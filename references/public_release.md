# 公开版内容清单

本工程使用根目录 LICENSE 指定的非商业使用许可。

本次新增：地震基础材质与四种传播、群体三种自然材质和七种队形、多技能流程图、
节点内编辑、前置状态预览、全屏、截图、性能与回归工具。

颜色：材质原色、金、紫、赤红、冰蓝、翠绿、白银、暗黑、秋叶、羽白、沙漠，以及自定义色板编辑。
新增样例只使用登记的公开材质、配色与事件，全部能在本仓库独立运行。
原有作品、styles 与 media 保留；许可证保持原样。

## 本地检查

```sh
python tools/audit_public.py
godot --headless --path . --script res://tools/verify_public.gd
godot --path . --script res://tools/capture_public.gd
godot --path . --script res://tools/verify_fullscreen.gd
godot --path . --script res://tools/bench_quake.gd -- --budget=3
```

截图输出到忽略目录 verification/public/，不自动加入发布包。
``verify_public`` 同时检查既有作品的事件与流程图转换，以及自然材质预览、保存和播放。

[本次验证记录](validation.md)。

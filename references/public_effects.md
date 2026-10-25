# 公开版地震与群体事件

## 地震

`do: quake`；材质 `unit`：earth / ice / magma / magic / thunder / shadow / holy。
传播 `mode`：radial / sweep / split / cone；`reverse` 反向。
范围：x、y、width、length、angle、perspective、cone。
节奏：travel、ease；或 rhythm: staged 配 stages（distance、time、pause、strength）。
外观与配套：unit_size、spacing、unit_time、body_growth、cracks、wave、debris、dust、seed。
首批提供岩刺阵、冰晶簇、灼地熔化、天雷、通用法阵与光柱等基础形态。

网格在配置时生成，动画由 action clock 和 shader 驱动；形状储存明度，渐变色板映射到颜色。
软件适配器自动降级，`-- --fallback` 可以强制预览。它仍然需要可用的图形后端。
性能工具 `tools/bench_quake.gd -- --budget=3` 测量指定机器、窗口及预设下相对空舞台的平均帧耗时；
3 ms 是该组基准目标，不是任意机器或多效果叠加的保证，也不是独立 GPU 时间测量。

## 群体

`do: swarm`；同名 `id` 控制同一群体，后续事件改变队形、材质或颜色。
材质 `material`：leaf（落叶）、feather（羽毛）、sand（砂砾与细尘）。
队形 `form`：cloud / stream / vortex / sphere / burst / fall / gone。
中心 `at`：attacker / target / [x,y]；另有 offset_x、offset_y。
范围与运动：count、size、radius、height、time、travel、length、width、path、swirl、turbulence、tumble、linger、seed。
`path` 为最多 12 个 [x,y] 点；未填写时生成默认曲线。
落叶：leaf_curl、leaf_sway；羽毛：feather_bend、feather_split；沙：sand_grain、sand_dust、sand_settle。
材质形状、表面、运动不同；配色和队形独立。
`gone` 是消散，不是立即删除；单独编辑时提供临时来源预览。
后续同名事件未指定的参数继承上一个状态，包括材质与配色。

## 配色与画质

`ramp` 可用 gold / violet / crimson / azure / jade / silver / abyss / autumn / ivory / dune，
也可填写五个十六进制色标（深 → 暗 → 中 → 亮 → 发光）。
默认配色：落叶 autumn、羽毛 ivory、沙 dune。
`style.json` 中 quake_style: real / cel / pixel；quake_detail: balanced / fine / ultimate / explosive。
公开包只包含以上登记材质与配色；既有刀光、魔法作品和风格保持兼容。

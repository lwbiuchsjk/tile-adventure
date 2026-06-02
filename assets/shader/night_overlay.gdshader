// 夜晚视野 MVP（入口 4 后段第 1 份）+ L1.2 多源视野升级（vec4[8] 数组多光源）
// 设计文档：tile-advanture-design/夜晚视野_MVP.md
//          tile-advanture-design/无限地图实装/L1.2_多源视野与据点机制_MVP.md §2.4 / §10.1
//
// UV 空间遮罩（2026-05-11 跑测修复版本）：
//   - 光源位置用 SCREEN_UV 空间 [0,1] 表达，避开 canvas_items stretch 模式下
//     viewport pixel 与真实窗口 pixel 不一致的问题
//   - 距离按 aspect_xy 校正成正圆（X 方向拉伸到与 Y 同基准 = viewport 高度）
//   - 半径在 UV 空间也以 viewport 高度归一（GDScript 端传 radius_uv = pixel / vp_height）
//   - phase_alpha 总因子驱动昼夜 fade（白天=0 / 夜晚=1，含 Tween 中间值）
//
// L1.2 多光源升级（2026-06-01，Phase 0）：
//   - 单光源 vec2 light_uv 升级为 vec4[8] 数组 lights[]，每个 vec4 打包 (uv.x, uv.y, radius_uv, falloff_uv)
//   - active_light_count 控制实际生效的光源数；fragment 遍历取 max_visible（视野并集）
//   - lights[0] 约定为玩家队伍源（GDScript 端保留平滑像素 + night_vision_config 视觉半径路径）
//   - lights[1..] 为据点 / 占领 slot 源（Phase 2 接入；Phase 0 运行时 active_count=1 等价单光源）
//
// 原作者曾警告 vec4[N] 在部分 Godot 4.6 canvas_item 下传递不稳 → Phase 0 已用 AB 对比 testbed
// （test/scenes/test_shader_multilight.tscn）在本环境（Godot 4.6.2 + Windows）桌面验证：
// vec4[8] 数组方案与 8 独立 uniform 方案渲染完全一致，5 用例全通过 → 确认数组方案在本环境稳定，
// 采用数组方案（代码更简洁）。fallback（8 独立 uniform）方案保留在设计文档 §10.1 备查。
shader_type canvas_item;

// 光源数量上限（与 GDScript 端 NightVisionLayer.MAX_LIGHTS 常量保持一致）
const int MAX_LIGHTS = 8;

// 多光源数据数组：每个 vec4 = (uv.x, uv.y, radius_uv, falloff_uv)
//   - xy：光源在 SCREEN_UV 空间的位置（[0,1]）
//   - z ：光源照亮半径，UV 空间（以 viewport 高度为基准）
//   - w ：浓雾过渡带宽度，UV 空间（同样以 viewport 高度为基准）
uniform vec4 lights[MAX_LIGHTS];

// 实际生效的光源数（0..MAX_LIGHTS）；超出部分数组槽位忽略
uniform int active_light_count = 1;

// 浓雾近黑色（默认完全黑）
uniform vec4 fog_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);

// 昼夜 fade 因子（0=完全白天透明 / 1=完全夜晚生效）
uniform float phase_alpha : hint_range(0.0, 1.0) = 0.0;

// 屏幕宽高比（GDScript 每帧设：vp_size.x / vp_size.y）
// X 方向距离按 aspect 拉伸 → 让圆是正圆（不被宽屏拉成椭圆）
uniform float aspect_xy = 1.778;


// 单个光源的可见度计算
//   light: (uv.x, uv.y, radius_uv, falloff_uv)
//   返回：[0,1]，越靠近光源越接近 1
float _calc_visible(vec4 light, vec2 uv) {
	vec2 d = uv - light.xy;
	// X 按 aspect 拉伸到与 Y 同基准（viewport 高度）；保证圆而非椭圆
	d.x *= aspect_xy;
	float dist = length(d);
	// smoothstep(radius, radius + falloff, dist):
	//   dist <= radius           → 0（在光源内）
	//   dist >= radius + falloff → 1（在浓雾外）
	// visible = 1 - smoothstep → 越靠近光源越亮
	return 1.0 - smoothstep(light.z, light.z + light.w, dist);
}


void fragment() {
	vec2 uv = SCREEN_UV;

	// 多光源取并集：任一光源照亮即可见，取所有光源可见度的最大值
	// 循环上界用常量 MAX_LIGHTS（GLSL 要求循环次数编译期可定），内部用 active_light_count 守卫
	float max_visible = 0.0;
	for (int i = 0; i < MAX_LIGHTS; i++) {
		if (i >= active_light_count) {
			break;
		}
		max_visible = max(max_visible, _calc_visible(lights[i], uv));
	}

	// alpha = (1 - 可见度) × 昼夜因子
	float alpha = (1.0 - max_visible) * phase_alpha;
	COLOR = vec4(fog_color.rgb, alpha);
}

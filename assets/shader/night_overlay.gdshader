// 夜晚视野 MVP（入口 4 后段第 1 份）
// 设计文档：tile-advanture-design/夜晚视野_MVP.md
//
// 单光源 UV 空间遮罩（2026-05-11 跑测修复版本）：
//   - 光源位置用 SCREEN_UV 空间 [0,1] 表达，避开 canvas_items stretch 模式下
//     viewport pixel 与真实窗口 pixel 不一致的问题
//   - 距离按 aspect_xy 校正成正圆（X 方向拉伸到与 Y 同基准 = viewport 高度）
//   - 半径在 UV 空间也以 viewport 高度归一（GDScript 端传 radius_uv = pixel / vp_height）
//   - phase_alpha 总因子驱动昼夜 fade（白天=0 / 夜晚=1，含 Tween 中间值）
//
// 多光源接口为何先简化为单光源：
//   - 跑测发现 vec4[N] uniform 数组在部分 Godot 4.6 canvas_item shader 下传递不稳
//   - MVP 阶段只用 1 个玩家光源，单 uniform 最稳；未来扩展多光源时再换 vec4[] / texture
//   - 多光源备忘见待跟踪事项索引 §十一 P3
shader_type canvas_item;

// 光源在 SCREEN_UV 空间的位置（[0,1]，每帧 GDScript 更新）
uniform vec2 light_uv = vec2(0.5, 0.5);

// 光源照亮半径，UV 空间（以 viewport 高度为基准；GDScript 端 = radius_in_vp_pixels / vp_height）
uniform float light_radius_uv : hint_range(0.0, 2.0) = 0.25;

// 浓雾过渡带宽度，UV 空间（同样以 viewport 高度为基准）
uniform float fog_falloff_uv : hint_range(0.0, 1.0) = 0.05;

// 浓雾近黑色（默认完全黑）
uniform vec4 fog_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);

// 昼夜 fade 因子（0=完全白天透明 / 1=完全夜晚生效）
uniform float phase_alpha : hint_range(0.0, 1.0) = 0.0;

// 屏幕宽高比（GDScript 每帧设：vp_size.x / vp_size.y）
// X 方向距离按 aspect 拉伸 → 让圆是正圆（不被宽屏拉成椭圆）
uniform float aspect_xy = 1.778;


void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 d = uv - light_uv;
	// X 按 aspect 拉伸到与 Y 同基准（viewport 高度）；保证圆而非椭圆
	d.x *= aspect_xy;
	float dist = length(d);

	// smoothstep(radius, radius + falloff, dist):
	//   dist <= radius           → 0（在光源内）
	//   dist >= radius + falloff → 1（在浓雾外）
	// visible = 1 - smoothstep → 越靠近光源越亮
	float visible = 1.0 - smoothstep(light_radius_uv, light_radius_uv + fog_falloff_uv, dist);

	// alpha = (1 - 可见度) × 昼夜因子
	float alpha = (1.0 - visible) * phase_alpha;
	COLOR = vec4(fog_color.rgb, alpha);
}

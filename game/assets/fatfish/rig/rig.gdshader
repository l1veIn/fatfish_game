shader_type canvas_item;
// 大肥鱼's body as one subdivided mesh (FishRig), bent like a Live2D warp deformer: every
// vertex knows its rest position (UV, 0..1 over the 1024 px body texture) and is moved by the
// regions it belongs to, with soft falloffs so nothing tears. The region positions are
// uniforms: the defaults fit the standing drawing (art_src/rig/master_0.png), FishRig sets the
// seated one's (seat_0.png) from FishRig.REGIONS.

uniform float tex_px = 1024.0;
uniform float t = 0.0;
uniform float head_angle = 0.0;      // radians, around the neck
uniform vec2 head_shift = vec2(0.0); // uv units
uniform float breath = 0.0;          // uv units, upper body rises
uniform float hair_amp = 0.004;      // uv units, outer hair sway
uniform float tail_angle = 0.0;
uniform float fin_angle = 0.0;       // the whale-fin ears flap (mirrored)
uniform float ahoge_angle = 0.0;
uniform float arm_angle = 0.0;       // both arms swing out (mirrored)
uniform float belly = 0.0;           // 0..~0.12: the tummy rounds out as she eats

// regions (uv)
uniform vec2 neck = vec2(0.498, 0.43);
uniform vec2 head_y = vec2(0.39, 0.47);        // head weight: 1 above x, 0 below y
uniform vec4 ahoge_box = vec4(0.29, 0.47, 0.045, 0.08);   // x from, x to, y full, y none
uniform vec2 ahoge_root = vec2(0.45, 0.075);
uniform vec4 fin_l = vec4(0.27, 0.335, 0.075, 0.065);     // centre xy, radius xy
uniform vec2 fin_l_root = vec2(0.32, 0.325);
uniform vec4 fin_r = vec4(0.72, 0.315, 0.085, 0.055);
uniform vec2 fin_r_root = vec2(0.66, 0.31);
uniform vec4 arm_l = vec4(0.30, 0.63, 0.13, 0.11);
uniform vec2 arm_l_root = vec2(0.40, 0.50);
uniform vec4 arm_r = vec4(0.70, 0.63, 0.13, 0.11);
uniform vec2 arm_r_root = vec2(0.60, 0.50);
uniform vec4 belly_e = vec4(0.5, 0.60, 0.2, 0.14);
uniform vec2 breath_y = vec2(0.52, 0.78);      // the body above x rises, below y stays
uniform vec4 hair_band = vec4(0.27, 0.37, 0.33, 0.85);   // |x - 0.5| from, to; y from, to
uniform vec4 tail_box = vec4(0.70, 0.77, 0.52, 0.60);    // x from, to; y from, to (fades out at 0.86..0.92)
uniform vec2 tail_root = vec2(0.71, 0.75);

vec2 rot(vec2 p, vec2 c, float a) {
	vec2 d = p - c;
	float s = sin(a);
	float k = cos(a);
	return c + vec2(d.x * k - d.y * s, d.x * s + d.y * k);
}

float ell(vec2 uv, vec4 e) {
	return 1.0 - smoothstep(0.55, 1.0, length((uv - e.xy) / e.zw));
}

void vertex() {
	vec2 uv = UV;
	vec2 p = uv;
	// ahoge and fins swing on their own, then ride along with the head
	float wa = (1.0 - smoothstep(ahoge_box.z, ahoge_box.w, uv.y)) * (1.0 - smoothstep(ahoge_box.y - 0.03, ahoge_box.y, uv.x)) * smoothstep(ahoge_box.x, ahoge_box.x + 0.04, uv.x);
	p = mix(p, rot(p, ahoge_root, ahoge_angle), wa);
	p = mix(p, rot(p, fin_l_root, -fin_angle), ell(uv, fin_l));
	p = mix(p, rot(p, fin_r_root, fin_angle), ell(uv, fin_r));
	// arms, from the shoulders
	p = mix(p, rot(p, arm_l_root, arm_angle), ell(uv, arm_l));
	p = mix(p, rot(p, arm_r_root, -arm_angle), ell(uv, arm_r));
	// the tummy swells from its centre
	p += (uv - belly_e.xy) * belly * ell(uv, belly_e);
	// the head and everything attached to it
	float wh = 1.0 - smoothstep(head_y.x, head_y.y, uv.y);
	p = mix(p, rot(p, neck, head_angle) + head_shift, wh);
	// breathing: the upper body rises
	p.y -= breath * (1.0 - smoothstep(breath_y.x, breath_y.y, uv.y));
	// the outer hair sways, a wave running down it
	float ws = smoothstep(hair_band.x, hair_band.y, abs(uv.x - 0.5)) * smoothstep(hair_band.z, hair_band.w, uv.y);
	p.x += hair_amp * ws * sin(t * 1.6 - uv.y * 7.0 + sign(uv.x - 0.5) * 0.8);
	p.y += hair_amp * 0.3 * ws * sin(t * 1.3 + uv.x * 5.0);
	// the tail
	float wt = smoothstep(tail_box.x, tail_box.y, uv.x) * smoothstep(tail_box.z, tail_box.w, uv.y) * (1.0 - smoothstep(0.86, 0.92, uv.y));
	p = mix(p, rot(p, tail_root, tail_angle), wt);
	VERTEX += (p - uv) * tex_px;
}

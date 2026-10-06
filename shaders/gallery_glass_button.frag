#version 320 es

#include <flutter/runtime_effect.glsl>

uniform vec2 u_size;
uniform sampler2D u_texture_input;

out vec4 frag_color;

void main() {
  vec2 position = FlutterFragCoord().xy;
#ifdef IMPELLER_TARGET_OPENGLES
  position.y = u_size.y - position.y;
#endif

  vec2 center = u_size * 0.5;
  vec2 radial = position - center;
  float radius = min(u_size.x, u_size.y) * 0.5;
  float normalizedRadius = clamp(length(radial) / radius, 0.0, 0.98);

  // Thin spherical cap: bend the backdrop ray by the air/glass Snell angle.
  float capHeight = 1.4;
  float surfaceSlope = (capHeight / radius) * normalizedRadius /
      sqrt(max(1.0 - normalizedRadius * normalizedRadius, 0.04));
  float incidence = atan(surfaceSlope);
  float transmission = asin(clamp(sin(incidence) / 1.52, 0.0, 0.99));
  float shift = clamp((incidence - transmission) * 8.0, 0.0, 0.45);
  shift *= smoothstep(0.08, 0.42, normalizedRadius);

  vec2 direction = radial / max(length(radial), 0.001);
  vec2 samplePosition = position + direction * shift;
  vec2 uv = clamp(samplePosition / u_size, vec2(0.001), vec2(0.999));
  frag_color = texture(u_texture_input, uv);
}

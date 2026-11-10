#version 300 es
precision highp float;
in vec2 vPosition;
uniform vec2 size;
uniform sampler2D source;
uniform sampler2D selectedLabels;
uniform sampler2D pillBackdrop;
uniform float flip;
uniform float blur;
uniform float denseBlur;
uniform vec2 blurDirection;
uniform float indicator;
uniform float dark;
uniform float labelPass;
uniform float pillBlur;
uniform vec4 pill;
out vec4 fragColor;

vec4 sampleAt(vec2 p) {
    vec2 uv = p / size;
    uv.y = mix(uv.y, 1.0 - uv.y, flip);
    return texture(source, uv);
}

float pillCoverage() {
    vec2 halfSize = pill.zw * .5;
    float r = min(halfSize.x, halfSize.y);
    vec2 q = abs(vPosition - pill.xy) - halfSize + r;
    float sd = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
    return 1.0 - smoothstep(-.5, .5, sd);
}

void main() {
    vec4 color = sampleAt(vPosition);
    if (blur > 0.0) {
        color = vec4(0);
        float sum = 0.0;
        int radius = denseBlur > 0.0 ? 12 : 6;
        float stepSize = denseBlur > 0.0 ? .25 : .5;
        for (int i = -radius; i <= radius; i++) {
            float offset = float(i) * stepSize;
            float weight = exp(-.5 * offset * offset);
            color += sampleAt(vPosition + blurDirection * offset * blur) * weight;
            sum += weight;
        }
        color /= sum;
    }
    if (indicator > 0.0) {
        float coverage = pillCoverage();
        if (pillBlur > 0.0 && coverage > 0.0) {
            vec4 blurred = vec4(0);
            float sum = 0.0;
            for (int i = -6; i <= 6; i++) {
                float weight = exp(-float(i*i) / 8.0);
                vec2 uv = (vPosition + vec2(0.0, float(i) * pillBlur * .5)) / size;
                blurred += texture(pillBackdrop, vec2(uv.x, 1.0 - uv.y)) * weight;
                sum += weight;
            }
            color = mix(color, blurred / sum, coverage * indicator);
        }
        float alpha = coverage * indicator * (38.0 / 255.0);
        color = vec4(vec3(dark * alpha), alpha) + color * (1.0 - alpha);
    }
    if (labelPass > 0.0) {
        color = mix(color, texture(selectedLabels, vPosition / size), pillCoverage());
    }
    fragColor = color;
}

#version 330 core

in  vec2      vUV;
out vec4      fragColor;

uniform sampler2D uTex;
uniform float uWidth;
uniform float uHeight;
uniform float uRadius;

void main() {
    vec2 size = vec2(uWidth, uHeight);
    float radius = min(uRadius, min(uWidth, uHeight) * 0.25);
    vec2 q = abs(vUV * size - size * 0.5) - (size * 0.5 - radius);
    float distance = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radius;
    float alpha = 1.0 - smoothstep(-1.0, 0.5, distance);
    vec3 color = texture(uTex, vUV).rgb;
    color = mix(color, vec3(0.75), smoothstep(-1.8, -0.6, distance) * 0.3);
    fragColor = vec4(color, alpha);
}

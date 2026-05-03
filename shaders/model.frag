#version 330 core

in vec3 vFragPos;
in vec3 vNormal;

// Two-light Blinn-Phong setup
uniform vec3 uLightPos[2];
uniform vec3 uLightColor[2];
uniform vec3 uCamPos;
uniform vec3 uObjectColor;

out vec4 FragColor;

void main() {
    vec3 N = normalize(vNormal);
    vec3 V = normalize(uCamPos - vFragPos);

    // Ambient
    vec3 color = 0.12 * uObjectColor;

    for (int i = 0; i < 2; ++i) {
        vec3 L    = normalize(uLightPos[i] - vFragPos);
        vec3 H    = normalize(L + V);

        // Diffuse + specular
        float diff = max(dot(N, L), 0.0);
        float spec = pow(max(dot(N, H), 0.0), 64.0);

        color += diff * uLightColor[i] * uObjectColor;
        color += spec * uLightColor[i] * 0.4;
    }

    FragColor = vec4(color, 1.0);
}

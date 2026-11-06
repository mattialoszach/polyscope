#version 330 core

// Per-vertex attributes uploaded from the Mesh VAO
layout(location = 0) in vec3 aPos;
layout(location = 1) in vec3 aNormal;

// Transformation matrices
uniform mat4 uModel;
uniform mat4 uView;
uniform mat4 uProj;
// Normal matrix = transpose(inverse(mat3(model))).
// Pre-computed on the CPU so we don't invert inside the shader.
uniform mat3 uNormalMat;

// Outputs to the fragment shader
out vec3 vFragPos;   // world-space position
out vec3 vNormal;    // world-space normal

void main() {
    vec4 worldPos = uModel * vec4(aPos, 1.0);
    vFragPos  = worldPos.xyz;
    vNormal   = normalize(uNormalMat * aNormal);
    gl_Position = uProj * uView * worldPos;
}

#include "renderer.h"
#include <glm/gtc/matrix_transform.hpp>
#include <glm/gtc/type_ptr.hpp>
#include <vector>

// ── Construction ──────────────────────────────────────────────────────────────

Renderer::Renderer() {
    glEnable(GL_DEPTH_TEST);
    glEnable(GL_MULTISAMPLE);  // MSAA (requested in window hints)

    buildGrid(10, 20);         // 20×20 grid spanning ±10 units
}

Renderer::~Renderer() {
    glDeleteBuffers(1, &m_gridVBO);
    glDeleteVertexArrays(1, &m_gridVAO);
}

void Renderer::resize(int w, int h) {
    m_width  = w;
    m_height = (h > 0) ? h : 1;
}

// ── Projection ────────────────────────────────────────────────────────────────

glm::mat4 Renderer::projMatrix() const {
    float aspect = static_cast<float>(m_width) / static_cast<float>(m_height);
    return glm::perspective(glm::radians(45.f), aspect, 0.01f, 1000.f);
}

// ── Grid ──────────────────────────────────────────────────────────────────────

void Renderer::buildGrid(int halfExtent, int cells) {
    std::vector<glm::vec3> lines;
    lines.reserve(static_cast<size_t>((cells + 1) * 4));

    float step  = static_cast<float>(2 * halfExtent) / static_cast<float>(cells);
    float start = static_cast<float>(-halfExtent);

    for (int i = 0; i <= cells; ++i) {
        float x = start + i * step;
        // Parallel to Z axis
        lines.push_back({x,    0.f, start});
        lines.push_back({x,    0.f, -start});
        // Parallel to X axis
        lines.push_back({start,  0.f, x});
        lines.push_back({-start, 0.f, x});
    }
    m_gridLineVerts = static_cast<int>(lines.size());

    glGenVertexArrays(1, &m_gridVAO);
    glBindVertexArray(m_gridVAO);

    glGenBuffers(1, &m_gridVBO);
    glBindBuffer(GL_ARRAY_BUFFER, m_gridVBO);
    glBufferData(GL_ARRAY_BUFFER,
                 static_cast<GLsizeiptr>(lines.size() * sizeof(glm::vec3)),
                 lines.data(), GL_STATIC_DRAW);

    glEnableVertexAttribArray(0);
    glVertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, sizeof(glm::vec3), nullptr);

    glBindVertexArray(0);
}

void Renderer::drawGrid(const Camera& camera) {
    glm::mat4 mvp = projMatrix() * camera.viewMatrix(); // model = identity

    m_flatShader.use();
    m_flatShader.set("uMVP",   mvp);
    m_flatShader.set("uColor", glm::vec4(0.35f, 0.35f, 0.38f, 1.0f));

    glBindVertexArray(m_gridVAO);
    glDrawArrays(GL_LINES, 0, m_gridLineVerts);
    glBindVertexArray(0);
}

// ── Main render call ──────────────────────────────────────────────────────────

void Renderer::render(const Mesh& mesh, const Camera& camera,
                      bool showGrid, bool wireframe) {
    // Background: dark charcoal
    glClearColor(0.11f, 0.11f, 0.13f, 1.f);
    glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT);

    if (showGrid) drawGrid(camera);

    // ── Model draw ───────────────────────────────────────────────────────────
    glm::mat4 model = glm::mat4(1.f);   // no object transform — mesh is pre-centered
    glm::mat4 view  = camera.viewMatrix();
    glm::mat4 proj  = projMatrix();
    // Normal matrix transforms normals correctly under non-uniform scale.
    // For this viewer the model matrix has no scale, but we compute it properly
    // so the code is instructive.
    glm::mat3 normalMat = glm::transpose(glm::inverse(glm::mat3(model)));

    // Two-point lighting: warm key light + cool fill light
    glm::vec3 lights[2] = {
        { 5.f,  8.f,  6.f },  // key light  (warm, upper-right-front)
        {-4.f, -2.f, -5.f },  // fill light (cool, lower-left-back)
    };
    glm::vec3 lightColors[2] = {
        { 1.00f, 0.94f, 0.88f },  // warm cream
        { 0.25f, 0.35f, 0.55f },  // cool blue
    };

    m_modelShader.use();
    m_modelShader.set("uModel",      model);
    m_modelShader.set("uView",       view);
    m_modelShader.set("uProj",       proj);
    m_modelShader.set("uNormalMat",  normalMat);
    m_modelShader.set("uCamPos",     camera.position());
    m_modelShader.set("uObjectColor",glm::vec3(0.80f, 0.80f, 0.83f));

    // Arrays of uniforms — set each element individually
    for (int i = 0; i < 2; ++i) {
        m_modelShader.set("uLightPos["   + std::to_string(i) + "]", lights[i]);
        m_modelShader.set("uLightColor[" + std::to_string(i) + "]", lightColors[i]);
    }

    if (wireframe) glPolygonMode(GL_FRONT_AND_BACK, GL_LINE);
    mesh.draw();
    if (wireframe) glPolygonMode(GL_FRONT_AND_BACK, GL_FILL);
}

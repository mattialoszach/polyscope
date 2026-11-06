#include "renderer.h"
#include "camera_frame.h"
#include <glm/gtc/matrix_transform.hpp>
#include <glm/gtc/type_ptr.hpp>
#include <vector>
#include <array>

namespace {

glm::vec4 gestureColor(GestureEvent::Type gesture) {
    switch (gesture) {
        case GestureEvent::Type::Orbit: return {0.20f, 1.00f, 0.45f, 1.f};
        case GestureEvent::Type::Pan:   return {1.00f, 0.68f, 0.18f, 1.f};
        case GestureEvent::Type::Zoom:  return {0.95f, 0.30f, 1.00f, 1.f};
        default:                        return {0.60f, 0.60f, 0.60f, 1.f};
    }
}

} // namespace

// ── Construction ──────────────────────────────────────────────────────────────

Renderer::Renderer() {
    glEnable(GL_DEPTH_TEST);
    glEnable(GL_MULTISAMPLE);

    buildGrid(10, 20);

    // ── Camera overlay: textured quad VAO ────────────────────────────────────
    // 4 vertices × (vec2 pos + vec2 uv) = 16 floats; rebuilt each frame.
    glGenVertexArrays(1, &m_quadVAO);
    glBindVertexArray(m_quadVAO);
    glGenBuffers(1, &m_quadVBO);
    glBindBuffer(GL_ARRAY_BUFFER, m_quadVBO);
    glBufferData(GL_ARRAY_BUFFER, 4 * 4 * sizeof(float), nullptr, GL_DYNAMIC_DRAW);
    glEnableVertexAttribArray(0);
    glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, 4 * sizeof(float),
                          reinterpret_cast<void*>(0));
    glEnableVertexAttribArray(1);
    glVertexAttribPointer(1, 2, GL_FLOAT, GL_FALSE, 4 * sizeof(float),
                          reinterpret_cast<void*>(2 * sizeof(float)));
    glBindVertexArray(0);

    // ── Camera overlay: landmark lines/points VAO ─────────────────────────────
    // Preallocate for max 46 line verts + 21 point verts (each vec3).
    glGenVertexArrays(1, &m_landmarkVAO);
    glBindVertexArray(m_landmarkVAO);
    glGenBuffers(1, &m_landmarkVBO);
    glBindBuffer(GL_ARRAY_BUFFER, m_landmarkVBO);
    glBufferData(GL_ARRAY_BUFFER, 128 * sizeof(glm::vec3), nullptr, GL_DYNAMIC_DRAW);
    glEnableVertexAttribArray(0);
    glVertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, sizeof(glm::vec3), nullptr);
    glBindVertexArray(0);

    // ── Camera overlay: texture (1×1 placeholder, resized on first frame) ────
    glGenTextures(1, &m_overlayTex);
    glBindTexture(GL_TEXTURE_2D, m_overlayTex);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, GL_CLAMP_TO_EDGE);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, GL_CLAMP_TO_EDGE);
    uint8_t px[4] = {0, 0, 0, 255};
    glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, 1, 1, 0,
                 GL_BGRA, GL_UNSIGNED_BYTE, px);
    glBindTexture(GL_TEXTURE_2D, 0);
}

Renderer::~Renderer() {
    glDeleteBuffers(1, &m_gridVBO);
    glDeleteVertexArrays(1, &m_gridVAO);
    glDeleteBuffers(1, &m_quadVBO);
    glDeleteVertexArrays(1, &m_quadVAO);
    glDeleteBuffers(1, &m_landmarkVBO);
    glDeleteVertexArrays(1, &m_landmarkVAO);
    glDeleteTextures(1, &m_overlayTex);
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
    m_flatShader.set("uColor", m_dark ? glm::vec4(.23f, .24f, .27f, 1.f)
                                    : glm::vec4(.82f, .83f, .85f, 1.f));

    glBindVertexArray(m_gridVAO);
    glDrawArrays(GL_LINES, 0, m_gridLineVerts);
    glBindVertexArray(0);
}

// ── Main render call ──────────────────────────────────────────────────────────

void Renderer::render(const Mesh& mesh, const Camera& camera,
                      bool showGrid, bool wireframe) {
    if (m_dark) glClearColor(.10f, .11f, .13f, 1.f);
    else glClearColor(.95f, .955f, .965f, 1.f);
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

// ── Camera overlay ────────────────────────────────────────────────────────────

void Renderer::drawOverlay(const FrameSnapshot& frame, float scale) {
    if (!frame.hasFrame || frame.width <= 0 || frame.height <= 0) return;

    const float fw = static_cast<float>(m_width);
    const float fh = static_cast<float>(m_height);

    // Keep the source aspect ratio, including widescreen and portrait cameras.
    const auto rect = cameraPreviewRect(m_width, m_height, frame.width, frame.height, scale);
    const float x0 = rect.x, y0 = rect.y, x1 = x0 + rect.width, y1 = y0 + rect.height;

    // Helper: pixel → NDC
    auto toNDC = [fw, fh](float px, float py) -> std::pair<float, float> {
        return { px / fw * 2.f - 1.f, py / fh * 2.f - 1.f };
    };

    auto [nx0, ny0] = toNDC(x0, y0);
    auto [nx1, ny1] = toNDC(x1, y1);

    // ── Upload camera texture ─────────────────────────────────────────────────
    glBindTexture(GL_TEXTURE_2D, m_overlayTex);
    if (frame.width != m_overlayTexW || frame.height != m_overlayTexH) {
        glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8,
                     frame.width, frame.height, 0,
                     GL_BGRA, GL_UNSIGNED_BYTE, frame.bgra.data());
        m_overlayTexW = frame.width;
        m_overlayTexH = frame.height;
    } else {
        glTexSubImage2D(GL_TEXTURE_2D, 0, 0, 0,
                        frame.width, frame.height,
                        GL_BGRA, GL_UNSIGNED_BYTE, frame.bgra.data());
    }

    // ── State: disable depth test, enable blend ───────────────────────────────
    glDisable(GL_DEPTH_TEST);
    glEnable(GL_BLEND);
    glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA);

    // ── Draw camera quad ──────────────────────────────────────────────────────
    // UV (0,0) = bottom-left of image (row 0 in our reversed buffer = cam bottom).
    const float leftU = frame.mirrored ? 1.f : 0.f, rightU = 1.f - leftU;
    const float quadVerts[16] = {
        nx0, ny0,  leftU, 0.f,
        nx1, ny0,  rightU, 0.f,
        nx0, ny1,  leftU, 1.f,
        nx1, ny1,  rightU, 1.f,
    };
    glBindVertexArray(m_quadVAO);
    glBindBuffer(GL_ARRAY_BUFFER, m_quadVBO);
    glBufferSubData(GL_ARRAY_BUFFER, 0, sizeof(quadVerts), quadVerts);

    m_overlayShader.use();
    m_overlayShader.set("uTex", 0);
    m_overlayShader.set("uWidth", rect.width);
    m_overlayShader.set("uHeight", rect.height);
    m_overlayShader.set("uRadius", 12.f * scale);
    glActiveTexture(GL_TEXTURE0);
    glBindTexture(GL_TEXTURE_2D, m_overlayTex);
    glDrawArrays(GL_TRIANGLE_STRIP, 0, 4);

    // ── Draw hand skeleton ────────────────────────────────────────────────────
    if (frame.landmarksValid) {
        // Bone connections: indices into frame.joints
        static const int kBones[][2] = {
            {0,1},{1,2},{2,3},{3,4},           // thumb
            {0,5},{5,6},{6,7},{7,8},           // index
            {0,9},{9,10},{10,11},{11,12},       // middle
            {0,13},{13,14},{14,15},{15,16},     // ring
            {0,17},{17,18},{18,19},{19,20},     // little
            {5,9},{9,13},{13,17},               // palm bar
        };

        // Convert Vision joint position → NDC on the overlay quad
        auto jndcValid = [&](int i) -> bool {
            return frame.joints[i].x >= 0.f;
        };
        auto jndc = [&](int i) -> glm::vec3 {
            float px = x0 + frame.joints[i].x * rect.width;
            float py = y0 + frame.joints[i].y * rect.height;
            auto [nx, ny] = toNDC(px, py);
            return {nx, ny, 0.f};
        };

        // Build line vertex list
        std::vector<glm::vec3> lines;
        lines.reserve(46);
        for (const auto& b : kBones) {
            if (jndcValid(b[0]) && jndcValid(b[1])) {
                lines.push_back(jndc(b[0]));
                lines.push_back(jndc(b[1]));
            }
        }

        // Build point vertex list
        std::vector<glm::vec3> pts;
        pts.reserve(21);
        for (int i = 0; i < 21; ++i)
            if (jndcValid(i)) pts.push_back(jndc(i));

        glBindVertexArray(m_landmarkVAO);
        glBindBuffer(GL_ARRAY_BUFFER, m_landmarkVBO);
        m_flatShader.use();
        m_flatShader.set("uMVP", glm::mat4(1.f));

        if (!lines.empty()) {
            glBufferSubData(GL_ARRAY_BUFFER, 0,
                            static_cast<GLsizeiptr>(lines.size() * sizeof(glm::vec3)),
                            lines.data());
            m_flatShader.set("uColor", gestureColor(frame.activeGesture));
            glDrawArrays(GL_LINES, 0, static_cast<GLsizei>(lines.size()));
        }
        if (!pts.empty()) {
            glBufferSubData(GL_ARRAY_BUFFER, 0,
                            static_cast<GLsizeiptr>(pts.size() * sizeof(glm::vec3)),
                            pts.data());
            glPointSize(6.f);
            m_flatShader.set("uColor", glm::vec4(1.f, 1.f, 1.f, 1.f));     // white
            glDrawArrays(GL_POINTS, 0, static_cast<GLsizei>(pts.size()));
            glPointSize(1.f);
        }
    }

    // ── Restore state ─────────────────────────────────────────────────────────
    glBindVertexArray(0);
    glBindTexture(GL_TEXTURE_2D, 0);
    glEnable(GL_DEPTH_TEST);
    glDisable(GL_BLEND);
}

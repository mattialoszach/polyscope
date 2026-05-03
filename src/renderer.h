#pragma once
#include "gl.h"
#include "shader.h"
#include "camera.h"
#include "mesh.h"
#include "gesture.h"
#include <glm/glm.hpp>

class Renderer {
public:
    Renderer();
    ~Renderer();

    Renderer(const Renderer&)            = delete;
    Renderer& operator=(const Renderer&) = delete;

    void resize(int width, int height);

    // Draw the 3D scene
    void render(const Mesh& mesh, const Camera& camera,
                bool showGrid, bool wireframe);

    // Draw the camera preview + hand skeleton in the bottom-right corner.
    // Call after render() and before glfwSwapBuffers().
    void drawOverlay(const FrameSnapshot& frame);

private:
    int m_width  = 1280;
    int m_height = 800;

    // ── 3D scene shaders ──────────────────────────────────────────────────────
    Shader m_modelShader { SHADER_DIR "/model.vert", SHADER_DIR "/model.frag" };
    Shader m_flatShader  { SHADER_DIR "/flat.vert",  SHADER_DIR "/flat.frag"  };

    // ── Grid geometry ─────────────────────────────────────────────────────────
    GLuint m_gridVAO       = 0;
    GLuint m_gridVBO       = 0;
    int    m_gridLineVerts = 0;

    // ── Camera overlay ────────────────────────────────────────────────────────
    Shader m_overlayShader { SHADER_DIR "/overlay.vert", SHADER_DIR "/overlay.frag" };

    GLuint m_quadVAO = 0;   // textured camera quad (pos2 + uv2)
    GLuint m_quadVBO = 0;

    GLuint m_landmarkVAO = 0;   // landmark lines + points (pos3)
    GLuint m_landmarkVBO = 0;

    GLuint m_overlayTex  = 0;
    int    m_overlayTexW = 0;
    int    m_overlayTexH = 0;

    glm::mat4 projMatrix() const;
    void buildGrid(int halfExtent, int cells);
    void drawGrid(const Camera& camera);
};

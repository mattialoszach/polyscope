#pragma once
#include "gl.h"
#include "shader.h"
#include "camera.h"
#include "mesh.h"
#include <glm/glm.hpp>

// Owns the two shader programs (Blinn-Phong mesh + flat grid) and handles all
// OpenGL draw calls for a single frame.
class Renderer {
public:
    Renderer();
    ~Renderer();

    Renderer(const Renderer&)            = delete;
    Renderer& operator=(const Renderer&) = delete;

    // Call whenever the framebuffer is resized
    void resize(int width, int height);

    // Draw a complete frame
    void render(const Mesh& mesh, const Camera& camera,
                bool showGrid, bool wireframe);

private:
    int m_width  = 1280;
    int m_height = 800;

    Shader m_modelShader { SHADER_DIR "/model.vert", SHADER_DIR "/model.frag" };
    Shader m_flatShader  { SHADER_DIR "/flat.vert",  SHADER_DIR "/flat.frag"  };

    // Grid geometry
    GLuint m_gridVAO       = 0;
    GLuint m_gridVBO       = 0;
    int    m_gridLineVerts = 0;

    glm::mat4 projMatrix() const;
    void buildGrid(int halfExtent, int cells);
    void drawGrid(const Camera& camera);
};

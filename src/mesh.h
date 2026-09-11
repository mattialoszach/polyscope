#pragma once
#include "gl.h"
#include "model_loader.h"
#include <string>
#include <vector>

// Loads a supported model file and uploads its triangle geometry to the GPU.
class Mesh {
public:
    explicit Mesh(const std::string& path);
    ~Mesh();

    Mesh(const Mesh&)            = delete;
    Mesh& operator=(const Mesh&) = delete;

    void   draw()          const;   // issues glDrawArrays
    size_t triangleCount() const { return static_cast<size_t>(m_vertexCount) / 3; }

private:
    GLuint  m_vao        = 0;
    GLuint  m_vbo        = 0;
    GLsizei m_vertexCount = 0;

    void upload(const std::vector<Vertex>& verts);
};

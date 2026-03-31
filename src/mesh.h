#pragma once
#include "gl.h"
#include <glm/glm.hpp>
#include <string>
#include <vector>

// A single interleaved vertex: 3 floats position + 3 floats normal = 24 bytes
struct Vertex {
    glm::vec3 position;
    glm::vec3 normal;
};

// Parses a Wavefront OBJ file and uploads the resulting triangle geometry to
// the GPU.  The mesh is automatically centered at the origin and scaled to fit
// a unit sphere so it always fills the view regardless of the original units.
class Mesh {
public:
    explicit Mesh(const std::string& objPath);
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

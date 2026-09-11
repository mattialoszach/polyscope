#include "mesh.h"

#include <cstddef>

Mesh::Mesh(const std::string& path) {
    upload(loadModelVertices(path));
}

void Mesh::upload(const std::vector<Vertex>& verts) {
    m_vertexCount = static_cast<GLsizei>(verts.size());

    glGenVertexArrays(1, &m_vao);
    glBindVertexArray(m_vao);

    glGenBuffers(1, &m_vbo);
    glBindBuffer(GL_ARRAY_BUFFER, m_vbo);
    glBufferData(GL_ARRAY_BUFFER,
                 static_cast<GLsizeiptr>(verts.size() * sizeof(Vertex)),
                 verts.data(), GL_STATIC_DRAW);

    glEnableVertexAttribArray(0);
    glVertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, sizeof(Vertex),
                          reinterpret_cast<void*>(offsetof(Vertex, position)));
    glEnableVertexAttribArray(1);
    glVertexAttribPointer(1, 3, GL_FLOAT, GL_FALSE, sizeof(Vertex),
                          reinterpret_cast<void*>(offsetof(Vertex, normal)));

    glBindVertexArray(0);
}

Mesh::~Mesh() {
    glDeleteBuffers(1, &m_vbo);
    glDeleteVertexArrays(1, &m_vao);
}

void Mesh::draw() const {
    glBindVertexArray(m_vao);
    glDrawArrays(GL_TRIANGLES, 0, m_vertexCount);
    glBindVertexArray(0);
}

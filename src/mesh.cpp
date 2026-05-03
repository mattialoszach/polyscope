#include "mesh.h"
#include <glm/gtc/matrix_transform.hpp>
#include <fstream>
#include <sstream>
#include <iostream>
#include <stdexcept>
#include <limits>
#include <algorithm>

// ── OBJ parsing ───────────────────────────────────────────────────────────────
//
// The Wavefront OBJ format stores positions, normals, and faces separately.
// A face vertex references position/texcoord/normal by 1-based index.
// Formats:    v1   |   v1/vt1   |   v1//vn1   |   v1/vt1/vn1
//
// We flatten everything into a single Vertex array (no shared indices) so we
// can upload it as a plain VBO — easy to understand and fast enough for a viewer.

namespace {

struct FaceVert { int v = 0, vt = 0, vn = 0; }; // 1-based; 0 = not present

FaceVert parseFaceVert(const std::string& tok) {
    FaceVert fv;
    size_t s1 = tok.find('/');
    if (s1 == std::string::npos) {
        fv.v = std::stoi(tok);
        return fv;
    }
    fv.v = std::stoi(tok.substr(0, s1));
    size_t s2 = tok.find('/', s1 + 1);
    if (s2 == std::string::npos) {
        // v/vt
        if (s1 + 1 < tok.size()) fv.vt = std::stoi(tok.substr(s1 + 1));
    } else {
        // v//vn  or  v/vt/vn
        if (s2 > s1 + 1)        fv.vt = std::stoi(tok.substr(s1 + 1, s2 - s1 - 1));
        if (s2 + 1 < tok.size()) fv.vn = std::stoi(tok.substr(s2 + 1));
    }
    return fv;
}

// Resolve a 1-based OBJ index (may be negative = from-end) to a 0-based index
int resolve(int idx, int size) {
    return idx > 0 ? idx - 1 : size + idx;
}

} // namespace

// ── Constructor ───────────────────────────────────────────────────────────────

Mesh::Mesh(const std::string& objPath) {
    std::ifstream file(objPath);
    if (!file.is_open())
        throw std::runtime_error("Mesh: cannot open OBJ file: " + objPath);

    std::vector<glm::vec3> positions;
    std::vector<glm::vec3> normals;
    struct Face { std::vector<FaceVert> verts; };
    std::vector<Face> faces;

    std::string line;
    while (std::getline(file, line)) {
        if (line.empty() || line[0] == '#') continue;
        std::istringstream ss(line);
        std::string token;
        ss >> token;

        if (token == "v") {
            glm::vec3 p; ss >> p.x >> p.y >> p.z;
            positions.push_back(p);
        } else if (token == "vn") {
            glm::vec3 n; ss >> n.x >> n.y >> n.z;
            normals.push_back(n);
        } else if (token == "f") {
            Face face;
            std::string t;
            while (ss >> t) face.verts.push_back(parseFaceVert(t));
            if (face.verts.size() >= 3) faces.push_back(std::move(face));
        }
        // vt (texture coords) are parsed but ignored — we only need geometry
    }

    if (positions.empty()) throw std::runtime_error("Mesh: no vertices in " + objPath);

    // ── Smooth normals ────────────────────────────────────────────────────────
    // When the OBJ provides no normals (common for simple meshes), we compute
    // area-weighted smooth normals: for each face, accumulate the *un-normalized*
    // cross product (which has magnitude = area) into each referenced position.
    // After all faces, normalizing gives a smooth, area-weighted average.
    bool hasNormals = !normals.empty();
    std::vector<glm::vec3> smoothNormals;

    if (!hasNormals) {
        smoothNormals.assign(positions.size(), glm::vec3(0.f));
        for (auto& face : faces) {
            auto& p0 = positions[resolve(face.verts[0].v, (int)positions.size())];
            auto& p1 = positions[resolve(face.verts[1].v, (int)positions.size())];
            auto& p2 = positions[resolve(face.verts[2].v, (int)positions.size())];
            glm::vec3 n = glm::cross(p1 - p0, p2 - p0); // not normalized (area-weighted)
            for (auto& fv : face.verts)
                smoothNormals[resolve(fv.v, (int)positions.size())] += n;
        }
        for (auto& n : smoothNormals)
            if (glm::length(n) > 1e-6f) n = glm::normalize(n);
    }

    // ── Flatten into a triangle list (fan-triangulate polygons) ───────────────
    std::vector<Vertex> vertices;
    vertices.reserve(faces.size() * 3);

    for (auto& face : faces) {
        // Fan triangulation: (0,1,2), (0,2,3), (0,3,4), …
        for (size_t i = 1; i + 1 < face.verts.size(); ++i) {
            FaceVert trio[3] = { face.verts[0], face.verts[i], face.verts[i + 1] };
            for (auto& fv : trio) {
                Vertex vert;
                int pidx = resolve(fv.v, (int)positions.size());
                vert.position = positions[pidx];

                if (hasNormals && fv.vn != 0)
                    vert.normal = normals[resolve(fv.vn, (int)normals.size())];
                else
                    vert.normal = smoothNormals[pidx];

                vertices.push_back(vert);
            }
        }
    }

    if (vertices.empty()) throw std::runtime_error("Mesh: no triangles produced from " + objPath);

    // ── Normalize: center at origin, scale to unit sphere ─────────────────────
    glm::vec3 bmin(std::numeric_limits<float>::max());
    glm::vec3 bmax(std::numeric_limits<float>::lowest());
    for (auto& v : vertices) {
        bmin = glm::min(bmin, v.position);
        bmax = glm::max(bmax, v.position);
    }
    glm::vec3 center  = (bmin + bmax) * 0.5f;
    float     maxExt  = glm::length(bmax - bmin) * 0.5f;
    float     invExt  = (maxExt > 1e-6f) ? 1.f / maxExt : 1.f;

    for (auto& v : vertices)
        v.position = (v.position - center) * invExt;

    upload(vertices);
}

// ── GPU upload ────────────────────────────────────────────────────────────────

void Mesh::upload(const std::vector<Vertex>& verts) {
    m_vertexCount = static_cast<GLsizei>(verts.size());

    // Vertex Array Object: remembers the buffer bindings + attribute layout
    glGenVertexArrays(1, &m_vao);
    glBindVertexArray(m_vao);

    // Vertex Buffer Object: one contiguous array of interleaved Vertex structs
    glGenBuffers(1, &m_vbo);
    glBindBuffer(GL_ARRAY_BUFFER, m_vbo);
    glBufferData(GL_ARRAY_BUFFER,
                 static_cast<GLsizeiptr>(verts.size() * sizeof(Vertex)),
                 verts.data(), GL_STATIC_DRAW);

    // Tell OpenGL how the data is laid out:
    //   location 0 = position (3 floats, offset 0)
    //   location 1 = normal   (3 floats, offset 12 bytes)
    glEnableVertexAttribArray(0);
    glVertexAttribPointer(0, 3, GL_FLOAT, GL_FALSE, sizeof(Vertex),
                          reinterpret_cast<void*>(offsetof(Vertex, position)));
    glEnableVertexAttribArray(1);
    glVertexAttribPointer(1, 3, GL_FLOAT, GL_FALSE, sizeof(Vertex),
                          reinterpret_cast<void*>(offsetof(Vertex, normal)));

    glBindVertexArray(0);
}

// ── Destructor ────────────────────────────────────────────────────────────────

Mesh::~Mesh() {
    glDeleteBuffers(1, &m_vbo);
    glDeleteVertexArrays(1, &m_vao);
}

// ── Draw ──────────────────────────────────────────────────────────────────────

void Mesh::draw() const {
    glBindVertexArray(m_vao);
    glDrawArrays(GL_TRIANGLES, 0, m_vertexCount);
    glBindVertexArray(0);
}

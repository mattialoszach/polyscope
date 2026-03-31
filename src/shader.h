#pragma once
#include "gl.h"
#include <glm/glm.hpp>
#include <string>

// Thin RAII wrapper around a GLSL shader program.
// Loads vertex and fragment shader source from disk, compiles, and links them.
class Shader {
public:
    Shader(const std::string& vertPath, const std::string& fragPath);
    ~Shader();

    // No copy, allow move
    Shader(const Shader&)            = delete;
    Shader& operator=(const Shader&) = delete;

    void use() const;

    // Typed uniform setters (look up location each call — good enough for a viewer)
    void set(const std::string& name, float v)           const;
    void set(const std::string& name, int v)             const;
    void set(const std::string& name, const glm::vec3& v) const;
    void set(const std::string& name, const glm::vec4& v) const;
    void set(const std::string& name, const glm::mat3& m) const;
    void set(const std::string& name, const glm::mat4& m) const;

private:
    GLuint m_id = 0;

    static std::string readFile(const std::string& path);
    static GLuint      compile(GLenum type, const std::string& src);
};

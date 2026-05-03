#include "shader.h"
#include <glm/gtc/type_ptr.hpp>
#include <fstream>
#include <sstream>
#include <iostream>
#include <stdexcept>

// ── Helpers ──────────────────────────────────────────────────────────────────

std::string Shader::readFile(const std::string& path) {
    std::ifstream f(path);
    if (!f.is_open())
        throw std::runtime_error("Shader::readFile – cannot open: " + path);
    std::stringstream ss;
    ss << f.rdbuf();
    return ss.str();
}

GLuint Shader::compile(GLenum type, const std::string& src) {
    GLuint shader = glCreateShader(type);
    const char* c = src.c_str();
    glShaderSource(shader, 1, &c, nullptr);
    glCompileShader(shader);

    GLint ok;
    glGetShaderiv(shader, GL_COMPILE_STATUS, &ok);
    if (!ok) {
        char log[512];
        glGetShaderInfoLog(shader, sizeof(log), nullptr, log);
        throw std::runtime_error(std::string("Shader compile error:\n") + log);
    }
    return shader;
}

// ── Construction / destruction ────────────────────────────────────────────────

Shader::Shader(const std::string& vertPath, const std::string& fragPath) {
    GLuint vert = compile(GL_VERTEX_SHADER,   readFile(vertPath));
    GLuint frag = compile(GL_FRAGMENT_SHADER, readFile(fragPath));

    m_id = glCreateProgram();
    glAttachShader(m_id, vert);
    glAttachShader(m_id, frag);
    glLinkProgram(m_id);

    // Shaders are baked into the program; the separate objects can be freed.
    glDeleteShader(vert);
    glDeleteShader(frag);

    GLint ok;
    glGetProgramiv(m_id, GL_LINK_STATUS, &ok);
    if (!ok) {
        char log[512];
        glGetProgramInfoLog(m_id, sizeof(log), nullptr, log);
        throw std::runtime_error(std::string("Shader link error:\n") + log);
    }
}

Shader::~Shader() {
    glDeleteProgram(m_id);
}

// ── Public API ────────────────────────────────────────────────────────────────

void Shader::use() const { glUseProgram(m_id); }

void Shader::set(const std::string& name, float v) const {
    glUniform1f(glGetUniformLocation(m_id, name.c_str()), v);
}
void Shader::set(const std::string& name, int v) const {
    glUniform1i(glGetUniformLocation(m_id, name.c_str()), v);
}
void Shader::set(const std::string& name, const glm::vec3& v) const {
    glUniform3fv(glGetUniformLocation(m_id, name.c_str()), 1, glm::value_ptr(v));
}
void Shader::set(const std::string& name, const glm::vec4& v) const {
    glUniform4fv(glGetUniformLocation(m_id, name.c_str()), 1, glm::value_ptr(v));
}
void Shader::set(const std::string& name, const glm::mat3& m) const {
    glUniformMatrix3fv(glGetUniformLocation(m_id, name.c_str()), 1, GL_FALSE, glm::value_ptr(m));
}
void Shader::set(const std::string& name, const glm::mat4& m) const {
    glUniformMatrix4fv(glGetUniformLocation(m_id, name.c_str()), 1, GL_FALSE, glm::value_ptr(m));
}

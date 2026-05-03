#include "camera.h"
#include <glm/gtc/matrix_transform.hpp>
#include <cmath>
#include <algorithm>

Camera::Camera() { reset(); }

void Camera::reset() {
    m_azimuth  =  0.4f;
    m_altitude =  0.35f;
    m_radius   =  3.0f;
    m_target   = {0.f, 0.f, 0.f};
}

// ── Derived state ─────────────────────────────────────────────────────────────

glm::vec3 Camera::position() const {
    // Spherical → Cartesian
    return m_target + glm::vec3(
        m_radius * std::cos(m_altitude) * std::sin(m_azimuth),
        m_radius * std::sin(m_altitude),
        m_radius * std::cos(m_altitude) * std::cos(m_azimuth)
    );
}

glm::mat4 Camera::viewMatrix() const {
    return glm::lookAt(position(), m_target, glm::vec3(0.f, 1.f, 0.f));
}

// ── Input handlers ────────────────────────────────────────────────────────────

void Camera::onMouseMove(float dx, float dy, bool leftDown, bool rightDown) {
    if (leftDown) {
        // Orbit: drag left/right changes azimuth; drag up/down changes altitude
        m_azimuth  -= dx * kRotateSpeed;
        m_altitude += dy * kRotateSpeed;

        // Clamp altitude so we never flip upside-down (gimbal lock prevention)
        static constexpr float kLimit = glm::half_pi<float>() - 0.01f;
        m_altitude = std::clamp(m_altitude, -kLimit, kLimit);
    }

    if (rightDown) {
        // Pan: move the target point in the camera's local XY plane.
        // We need the camera's right and world-up-projected-to-screen-up vectors.
        glm::vec3 forward = glm::normalize(m_target - position());
        glm::vec3 right   = glm::normalize(glm::cross(forward, glm::vec3(0.f, 1.f, 0.f)));
        glm::vec3 up      = glm::normalize(glm::cross(right, forward));

        m_target -= right * (dx * kPanSpeed * m_radius);
        m_target += up    * (dy * kPanSpeed * m_radius);
    }
}

void Camera::onScroll(float dy) {
    // Scroll up → zoom in (reduce radius), scroll down → zoom out
    m_radius *= (1.f - dy * kZoomSpeed);
    m_radius  = std::clamp(m_radius, kMinRadius, kMaxRadius);
}

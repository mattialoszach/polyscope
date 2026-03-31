#pragma once
#include <glm/glm.hpp>

// Orbital (arcball) camera that circles a target point.
//
// Controls:
//   Left-drag   → rotate (azimuth + altitude)
//   Right-drag  → pan the target point in screen space
//   Scroll      → zoom (change radius)
//   R key       → reset to default position  (handled in main)
class Camera {
public:
    Camera();
    void reset();

    // Call once per frame to get the view matrix for the GPU
    glm::mat4 viewMatrix() const;
    glm::vec3 position()   const;

    // Input — dx/dy in pixels
    void onMouseMove(float dx, float dy, bool leftDown, bool rightDown);
    void onScroll(float dy);

private:
    float     m_azimuth  =  0.4f;   // horizontal angle (radians)
    float     m_altitude =  0.35f;  // vertical angle above the XZ plane (radians)
    float     m_radius   =  3.0f;   // distance from target
    glm::vec3 m_target   = {0.f, 0.f, 0.f};

    static constexpr float kRotateSpeed = 0.006f;
    static constexpr float kPanSpeed    = 0.003f;
    static constexpr float kZoomSpeed   = 0.12f;
    static constexpr float kMinRadius   = 0.1f;
    static constexpr float kMaxRadius   = 100.f;
};

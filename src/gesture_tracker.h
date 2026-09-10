#pragma once

#include "gesture.h"
#include <array>

// Platform-independent gesture classifier and motion filter. Vision supplies
// normalised joints; keeping the temporal logic here makes it deterministic and
// testable without a camera.
struct GestureTrackingResult {
    GestureEvent       event{};
    GestureEvent::Type activeGesture = GestureEvent::Type::None;
    bool               handValid     = false;
};

class GestureTracker {
public:
    GestureTrackingResult update(const std::array<glm::vec2, 21>& joints);
    void reset();

private:
    GestureEvent::Type m_active         = GestureEvent::Type::None;
    GestureEvent::Type m_candidate      = GestureEvent::Type::None;
    int                m_candidateFrames = 0;

    bool  m_haveMotion = false;
    float m_smoothX    = 0.f;
    float m_smoothY    = 0.f;
    float m_lastRawX   = 0.f;
    float m_lastRawY   = 0.f;
    float m_smoothHandScale = 0.f;

    void resetMotion();
};

#include "gesture_tracker.h"

#include <algorithm>
#include <cmath>

namespace {

constexpr int kWrist = 0;
constexpr int kThumbTip = 4;

struct Finger {
    int mcp;
    int pip;
    int tip;
};

constexpr Finger kFingers[] = {
    {5,  6,  8},  // index
    {9,  10, 12}, // middle
    {13, 14, 16}, // ring
    {17, 18, 20}, // little
};

bool valid(const glm::vec2& p) {
    return std::isfinite(p.x) && std::isfinite(p.y)
        && p.x >= 0.f && p.x <= 1.f && p.y >= 0.f && p.y <= 1.f;
}

float distance(glm::vec2 a, glm::vec2 b) {
    return glm::length(a - b);
}

bool extended(const std::array<glm::vec2, 21>& joints,
              const Finger& finger, float palmLength) {
    const glm::vec2 wrist = joints[kWrist];
    const glm::vec2 mcp   = joints[finger.mcp];
    const glm::vec2 pip   = joints[finger.pip];
    const glm::vec2 tip   = joints[finger.tip];
    if (!valid(mcp) || !valid(pip) || !valid(tip)) return false;

    const glm::vec2 lower = pip - mcp;
    const glm::vec2 upper = tip - pip;
    const float lowerLen = glm::length(lower);
    const float upperLen = glm::length(upper);
    if (lowerLen < 0.001f || upperLen < 0.001f) return false;

    // Both tests are orientation-independent. The reach test separates folded
    // fingers; the direction test rejects a fingertip curled back over the palm.
    const float direction = glm::dot(lower / lowerLen, upper / upperLen);
    const float reach = distance(tip, wrist) - distance(mcp, wrist);
    return direction > 0.25f && reach > palmLength * 0.40f;
}

struct Classification {
    GestureEvent::Type mode = GestureEvent::Type::None;
    glm::vec2 anchor{0.f};
    float pinchRatio = 0.f;
    float handScale = 0.f;
    bool handValid = false;
};

Classification classify(const std::array<glm::vec2, 21>& joints,
                        bool zoomLatched) {
    Classification out;
    if (!valid(joints[kWrist]) || !valid(joints[5]) ||
        !valid(joints[9]) || !valid(joints[13]) || !valid(joints[17])) {
        return out;
    }

    const float palmLength = distance(joints[kWrist], joints[9]);
    const float palmWidth  = distance(joints[5], joints[17]);
    if (palmLength < 0.025f || palmWidth < 0.025f) return out;
    out.handValid = true;
    // Vision does not provide a reliable depth value. Under perspective, the
    // geometric mean of palm length and width grows as the hand approaches the
    // webcam and shrinks as it moves away.
    out.handScale = std::sqrt(palmLength * palmWidth);

    // Average rigid palm landmarks instead of following a fingertip. This is
    // substantially steadier while fingers change pose.
    out.anchor = (joints[kWrist] + joints[5] + joints[9] +
                  joints[13] + joints[17]) / 5.f;

    if (valid(joints[kThumbTip]) && valid(joints[kFingers[0].tip])) {
        out.pinchRatio = distance(joints[kThumbTip], joints[kFingers[0].tip])
                       / palmWidth;
        // A wider release threshold prevents mode flicker while adjusting the
        // pinch gap. Thresholds scale with the user's apparent hand size.
        const float pinchThreshold = zoomLatched ? 0.62f : 0.36f;
        if (out.pinchRatio < pinchThreshold) {
            out.mode = GestureEvent::Type::Zoom;
            return out;
        }
    }

    bool fingersExtended[4]{};
    for (int i = 0; i < 4; ++i) {
        const Finger& finger = kFingers[i];
        if (!valid(joints[finger.pip]) || !valid(joints[finger.tip])) {
            out.handValid = false;
            return out;
        }
        fingersExtended[i] = extended(joints, finger, palmLength);
    }

    const int extendedCount = static_cast<int>(fingersExtended[0])
                            + static_cast<int>(fingersExtended[1])
                            + static_cast<int>(fingersExtended[2])
                            + static_cast<int>(fingersExtended[3]);

    if (fingersExtended[0] && fingersExtended[1] &&
        !fingersExtended[2] && !fingersExtended[3]) {
        out.mode = GestureEvent::Type::Pan;
    } else if (extendedCount >= 3) {
        out.mode = GestureEvent::Type::Orbit;
    }
    return out;
}

float deadZone(float value, float threshold) {
    if (std::abs(value) <= threshold) return 0.f;
    return std::copysign(std::abs(value) - threshold, value);
}

} // namespace

void GestureTracker::resetMotion() {
    m_haveMotion = false;
    m_smoothX = m_smoothY = m_lastRawX = m_lastRawY = 0.f;
    m_smoothHandScale = 0.f;
}

void GestureTracker::reset() {
    m_active = GestureEvent::Type::None;
    m_candidate = GestureEvent::Type::None;
    m_candidateFrames = 0;
    resetMotion();
}

GestureTrackingResult
GestureTracker::update(const std::array<glm::vec2, 21>& joints) {
    const bool zoomLatched = m_active == GestureEvent::Type::Zoom
                          || m_candidate == GestureEvent::Type::Zoom;
    const Classification detected = classify(joints, zoomLatched);

    if (detected.mode != m_active) {
        // Never move using a pose that disagrees with the active mode. Requiring
        // a few consecutive frames removes one-frame Vision classification noise.
        resetMotion();
        if (detected.mode == m_candidate) {
            ++m_candidateFrames;
        } else {
            m_candidate = detected.mode;
            m_candidateFrames = 1;
        }

        const int framesRequired = detected.mode == GestureEvent::Type::None ? 2 : 3;
        if (m_candidateFrames >= framesRequired) {
            m_active = detected.mode;
            m_candidate = GestureEvent::Type::None;
            m_candidateFrames = 0;
        }
        return {{}, m_active, detected.handValid};
    }

    m_candidate = GestureEvent::Type::None;
    m_candidateFrames = 0;

    GestureTrackingResult out;
    out.activeGesture = m_active;
    out.handValid = detected.handValid;
    if (m_active == GestureEvent::Type::None) return out;

    out.event.type = m_active;
    if (!m_haveMotion) {
        m_smoothX = m_lastRawX = detected.anchor.x;
        m_smoothY = m_lastRawY = detected.anchor.y;
        m_smoothHandScale = detected.handScale;
        m_haveMotion = true;
        return out;
    }

    if (m_active == GestureEvent::Type::Zoom) {
        // Pinch acts as a clutch; zoom comes from apparent palm-size change.
        // Log ratios make equal percentage movements feel equal at any distance.
        const float rawChange = std::log(detected.handScale / m_smoothHandScale);
        if (std::abs(rawChange) > 0.35f) {
            m_smoothHandScale = detected.handScale;
            return out;
        }
        const float previous = m_smoothHandScale;
        m_smoothHandScale += (detected.handScale - m_smoothHandScale) * 0.45f;
        float relativeChange = std::log(m_smoothHandScale / previous);
        relativeChange = deadZone(relativeChange, 0.003f);
        relativeChange = std::clamp(relativeChange, -0.04f, 0.04f);
        out.event.scale = relativeChange * 14.f;
        return out;
    }

    if (distance(detected.anchor, {m_lastRawX, m_lastRawY}) > 0.18f) {
        m_smoothX = m_lastRawX = detected.anchor.x;
        m_smoothY = m_lastRawY = detected.anchor.y;
        return out;
    }
    m_lastRawX = detected.anchor.x;
    m_lastRawY = detected.anchor.y;

    const float previousX = m_smoothX;
    const float previousY = m_smoothY;
    m_smoothX += (detected.anchor.x - m_smoothX) * 0.45f;
    m_smoothY += (detected.anchor.y - m_smoothY) * 0.45f;

    float dx = deadZone(m_smoothX - previousX, 0.0015f);
    float dy = deadZone(m_smoothY - previousY, 0.0015f);
    dx = std::clamp(dx, -0.04f, 0.04f);
    dy = std::clamp(dy, -0.04f, 0.04f);
    out.event.dx = dx * 500.f;
    out.event.dy = dy * -500.f; // Vision uses a bottom-left origin.
    return out;
}

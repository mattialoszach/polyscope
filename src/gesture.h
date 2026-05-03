#pragma once
#include <glm/glm.hpp>
#include <array>
#include <vector>
#include <cstdint>

// Gesture classification emitted once per detected frame.
struct GestureEvent {
    enum class Type { None, Orbit, Pan, Zoom };
    Type  type  = Type::None;
    float dx    = 0.f;   // pixel-scale delta for Camera::onMouseMove
    float dy    = 0.f;
    float scale = 0.f;   // scroll-wheel delta for Camera::onScroll
};

// 21-joint snapshot from Vision, plus the raw camera pixels for the preview.
// Joint index layout: 0=wrist, 1-4=thumb (CMC→tip), 5-8=index, 9-12=middle,
// 13-16=ring, 17-20=little.  Position is Vision-normalised [0,1] origin
// bottom-left; invalid joints have position (-1,-1).
struct FrameSnapshot {
    std::vector<uint8_t>      bgra;            // BGRA pixels, width*height*4,
                                               // row 0 = bottom of image (GL convention)
    int                       width  = 0;
    int                       height = 0;
    std::array<glm::vec2, 21> joints{};        // hand landmark positions
    bool                      landmarksValid = false;
    bool                      hasFrame       = false;
};

// Forward-declared at file scope so Objective-C++ code in gesture.mm can
// reference it without hitting C++ private-access restrictions.
struct GestureImpl;

// Reads the front-facing webcam, runs Apple Vision hand-pose detection on
// a background thread, and exposes:
//   - poll()     gesture events (feed straight to Camera::onMouseMove/onScroll)
//   - getFrame() latest camera frame + 21-joint landmarks for the UI preview
//
// Gesture mapping:
//   Open hand / one+ fingers  → Orbit
//   Peace sign (idx + mid)    → Pan
//   Pinch (thumb ↔ index)     → Zoom
class GestureSource {
public:
    GestureSource();
    ~GestureSource();

    GestureEvent  poll();        // drain one event; call once per frame
    FrameSnapshot getFrame();    // latest pixels + landmarks (copies on new frame only)

    void setActive(bool on);     // start / stop the AVCaptureSession
    bool isRunning() const;      // true when session is running

private:
    GestureImpl* m_impl = nullptr;
};

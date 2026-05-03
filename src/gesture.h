#pragma once

// A single gesture event, emitted once per recognised frame.
// dx/dy are pixel-scale deltas suitable for Camera::onMouseMove.
// scale is a scroll-wheel-scale delta suitable for Camera::onScroll.
struct GestureEvent {
    enum class Type { None, Orbit, Pan, Zoom };
    Type  type  = Type::None;
    float dx    = 0.f;
    float dy    = 0.f;
    float scale = 0.f;
};

// Forward-declared at file scope so the Objective-C++ implementation can
// reference it without hitting C++ private-access restrictions.
struct GestureImpl;

// Reads the front-facing webcam, detects a single hand pose each frame via
// Apple Vision, classifies the gesture, and queues GestureEvents for the
// main thread.  Gesture-to-camera mapping:
//
//   Open hand / single finger   → Orbit  (feeds Camera::onMouseMove left-drag)
//   Peace sign (index+middle)   → Pan    (feeds Camera::onMouseMove right-drag)
//   Pinch (thumb ↔ index close) → Zoom   (feeds Camera::onScroll)
//
// poll() is cheap (mutex + deque pop); call it once per frame.
class GestureSource {
public:
    GestureSource();
    ~GestureSource();

    GestureEvent poll();
    bool         isRunning() const;

private:
    GestureImpl* m_impl = nullptr;
};

#include "gesture_tracker.h"

#include <cassert>
#include <cmath>
#include <iostream>

namespace {

using Joints = std::array<glm::vec2, 21>;

Joints hand(bool index, bool middle, bool ring, bool little) {
    Joints j;
    j.fill({-1.f, -1.f});
    j[0] = {0.50f, 0.16f};
    j[1] = {0.38f, 0.24f};
    j[2] = {0.32f, 0.31f};
    j[3] = {0.28f, 0.38f};
    j[4] = {0.24f, 0.44f};

    const float xs[] = {0.40f, 0.47f, 0.54f, 0.61f};
    const int bases[] = {5, 9, 13, 17};
    const bool states[] = {index, middle, ring, little};
    for (int i = 0; i < 4; ++i) {
        const int b = bases[i];
        j[b] = {xs[i], 0.36f};
        if (states[i]) {
            j[b + 1] = {xs[i], 0.54f};
            j[b + 2] = {xs[i], 0.68f};
            j[b + 3] = {xs[i], 0.82f};
        } else {
            j[b + 1] = {xs[i], 0.47f};
            j[b + 2] = {xs[i] - 0.04f, 0.43f};
            j[b + 3] = {xs[i] - 0.05f, 0.36f};
        }
    }
    return j;
}

void translate(Joints& joints, glm::vec2 delta) {
    for (auto& joint : joints) {
        if (joint.x >= 0.f) joint += delta;
    }
}

void resizeAbout(Joints& joints, glm::vec2 centre, float factor) {
    for (auto& joint : joints) {
        if (joint.x >= 0.f)
            joint = centre + (joint - centre) * factor;
    }
}

GestureTrackingResult confirm(GestureTracker& tracker, const Joints& joints) {
    tracker.update(joints);
    tracker.update(joints);
    return tracker.update(joints);
}

} // namespace

int main() {
    {
        GestureTracker tracker;
        Joints open = hand(true, true, true, true);
        auto result = confirm(tracker, open);
        assert(result.activeGesture == GestureEvent::Type::Orbit);

        tracker.update(open); // establish the motion baseline
        translate(open, {0.02f, -0.01f});
        result = tracker.update(open);
        assert(result.event.type == GestureEvent::Type::Orbit);
        assert(result.event.dx > 0.f);
        assert(result.event.dy > 0.f);
    }

    {
        GestureTracker tracker;
        Joints peace = hand(true, true, false, false);
        auto result = confirm(tracker, peace);
        assert(result.activeGesture == GestureEvent::Type::Pan);

        // Tiny landmark movement should be absorbed by the dead zone.
        tracker.update(peace);
        translate(peace, {0.001f, 0.f});
        result = tracker.update(peace);
        assert(std::abs(result.event.dx) < 0.0001f);
    }

    {
        GestureTracker tracker;
        Joints pinch = hand(true, false, false, false);
        pinch[4] = pinch[8] + glm::vec2{-0.02f, 0.f};
        // Curled fingertips are often occluded during a pinch; zoom only needs
        // stable palm joints plus the thumb and index tips.
        pinch[16] = pinch[20] = {-1.f, -1.f};
        auto result = confirm(tracker, pinch);
        assert(result.activeGesture == GestureEvent::Type::Zoom);

        tracker.update(pinch);
        // A hand growing in the image represents movement toward the camera.
        resizeAbout(pinch, pinch[0], 1.10f);
        result = tracker.update(pinch);
        assert(result.event.type == GestureEvent::Type::Zoom);
        assert(result.event.scale > 0.f);

        // Moving away shrinks the hand and must zoom out.
        resizeAbout(pinch, pinch[0], 0.75f);
        result = tracker.update(pinch);
        assert(result.event.scale < 0.f);
        assert(result.activeGesture == GestureEvent::Type::Zoom);
    }

    {
        GestureTracker tracker;
        Joints open = hand(true, true, true, true);
        confirm(tracker, open);
        Joints peace = hand(true, true, false, false);

        // A new mode cannot reuse the previous mode's motion baseline.
        auto result = tracker.update(peace);
        assert(result.event.type == GestureEvent::Type::None);
        result = tracker.update(peace);
        assert(result.event.type == GestureEvent::Type::None);
        result = tracker.update(peace);
        assert(result.activeGesture == GestureEvent::Type::Pan);
        assert(result.event.type == GestureEvent::Type::None);
    }

    std::cout << "gesture tracker tests passed\n";
    return 0;
}

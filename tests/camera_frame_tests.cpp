#include "camera_frame.h"
#include <cmath>
#include <iostream>
#include <stdexcept>

void require(bool value, const char* message) {
    if (!value) throw std::runtime_error(message);
}
int main() {
    // Two camera rows, each containing two BGRA pixels and four padding bytes.
    const uint8_t input[] = {1,2,3,4, 5,6,7,8, 99,99,99,99,
                             9,10,11,12, 13,14,15,16, 99,99,99,99};
    const auto pixels = cameraPixelsForTexture(input, 2, 2, 12);
    require(pixels == std::vector<uint8_t>({9,10,11,12,13,14,15,16,1,2,3,4,5,6,7,8}), "Preview must be upright and discard row padding");
    std::array<glm::vec2, 21> joints;
    joints.fill({-1.f, -1.f});
    joints[0] = {.2f, .7f};
    auto mirrored = cameraJointsForPreview(joints, true);
    require(std::abs(mirrored[0].x - .8f) < .0001f && mirrored[0].y == .7f, "Selfie preview must mirror landmarks exactly once");
    require(mirrored[1] == joints[1], "Missing landmarks must remain missing");
    require(cameraJointsForPreview(joints, false) == joints, "Unmirrored preview must preserve coordinates");
    for (const auto& size : {glm::ivec2(640,480), glm::ivec2(1920,1080), glm::ivec2(480,640)}) {
        const auto rect = cameraPreviewRect(1600, 1000, size.x, size.y, 2.f);
        require(std::abs(rect.width / rect.height - static_cast<float>(size.x) / size.y) < .001f, "Preview must preserve source aspect ratio");
        require(rect.x >= 0 && rect.y >= 0 && rect.x + rect.width <= 1600 && rect.y + rect.height <= 1000, "Preview must fit inside the viewport");
    }
    const auto standard = cameraPreviewRect(1000, 700, 1280, 720, 1.f);
    const auto retina = cameraPreviewRect(2000, 1400, 1280, 720, 2.f);
    require(std::abs(retina.width - standard.width * 2) < .001f, "Preview must retain its point size on Retina displays");
    require(cameraPreviewRect(0, 0, 0, 0, 1).width == 0, "Empty viewports must be safe");
    bool invalid = false;
    try { cameraPixelsForTexture(input, 2, 2, 4); }
    catch (const std::runtime_error&) { invalid = true; }
    require(invalid, "Invalid camera row strides must be rejected");
    std::cout << "Camera frame tests passed\n";
}

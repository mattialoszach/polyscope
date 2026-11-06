#include "camera_frame.h"
#include <algorithm>
#include <cstring>
#include <stdexcept>

std::vector<uint8_t> cameraPixelsForTexture(const uint8_t* pixels, int width,
                                           int height, size_t bytesPerRow) {
    if (!pixels || width <= 0 || height <= 0 || bytesPerRow < static_cast<size_t>(width) * 4)
        throw std::runtime_error("Invalid camera frame");
    const size_t rowSize = static_cast<size_t>(width) * 4;
    std::vector<uint8_t> result(rowSize * height);
    for (int y = 0; y < height; ++y)
        std::memcpy(result.data() + static_cast<size_t>(height - 1 - y) * rowSize,
                    pixels + static_cast<size_t>(y) * bytesPerRow, rowSize);
    return result;
}

std::array<glm::vec2, 21> cameraJointsForPreview(
    std::array<glm::vec2, 21> joints, bool mirrored) {
    if (mirrored) for (auto& joint : joints)
        if (joint.x >= 0.f) joint.x = 1.f - joint.x;
    return joints;
}

PreviewRect cameraPreviewRect(int viewWidth, int viewHeight,
                              int frameWidth, int frameHeight, float scale) {
    if (viewWidth <= 0 || viewHeight <= 0 || frameWidth <= 0 || frameHeight <= 0)
        return {};
    const float margin = std::min(20.f * scale, std::min(viewWidth, viewHeight) * .05f);
    const float aspect = static_cast<float>(frameWidth) / frameHeight;
    float width = std::min(260.f * scale, viewWidth * .32f);
    float height = width / aspect;
    const float maxHeight = std::min(viewHeight * .4f, viewHeight - 2 * margin);
    if (height > maxHeight) { height = maxHeight; width = height * aspect; }
    return {viewWidth - width - margin, margin, width, height};
}

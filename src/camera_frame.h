#pragma once
#include <array>
#include <cstddef>
#include <cstdint>
#include <glm/vec2.hpp>
#include <vector>

struct PreviewRect { float x, y, width, height; };

// Camera buffers have a top-left origin and possibly padded rows. OpenGL
// textures use bottom-left. Mirroring is applied once at display time.
std::vector<uint8_t> cameraPixelsForTexture(const uint8_t* pixels, int width,
                                           int height, size_t bytesPerRow);
std::array<glm::vec2, 21> cameraJointsForPreview(
    std::array<glm::vec2, 21> joints, bool mirrored);
PreviewRect cameraPreviewRect(int viewWidth, int viewHeight,
                              int frameWidth, int frameHeight, float scale);

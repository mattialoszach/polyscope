#pragma once

#include <glm/glm.hpp>
#include <string>
#include <vector>

// A single interleaved vertex: 3 floats position + 3 floats normal = 24 bytes.
struct Vertex {
    glm::vec3 position;
    glm::vec3 normal;
};

// Loads every triangle mesh in a model, applies its scene-node transforms, and
// returns one flattened triangle list. The geometry is centered at the origin
// and scaled to fit the view.
std::vector<Vertex> loadModelVertices(const std::string& path);

// Extensions intentionally enabled in the application build.
const std::vector<std::string>& supportedModelExtensions();

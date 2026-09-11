#include "model_loader.h"

#include <glm/glm.hpp>

#include <cmath>
#include <cstdlib>
#include <iostream>
#include <stdexcept>
#include <string>
#include <vector>

namespace {

void require(bool condition, const std::string& message) {
    if (!condition) throw std::runtime_error(message);
}

void checkModel(const std::string& path, size_t expectedTriangles) {
    const std::vector<Vertex> vertices = loadModelVertices(path);
    require(vertices.size() == expectedTriangles * 3,
            path + ": unexpected triangle count");

    for (const auto& vertex : vertices) {
        require(std::isfinite(vertex.position.x) && std::isfinite(vertex.position.y) &&
                    std::isfinite(vertex.position.z),
                path + ": non-finite position");
        require(std::isfinite(vertex.normal.x) && std::isfinite(vertex.normal.y) &&
                    std::isfinite(vertex.normal.z),
                path + ": non-finite normal");
        require(glm::length(vertex.position) <= 1.01f,
                path + ": geometry was not normalized");
    }
}

} // namespace

int main(int argc, char** argv) {
    try {
        if (argc > 1) {
            const auto vertices = loadModelVertices(argv[1]);
            std::cout << "Loaded " << argv[1] << ": "
                      << vertices.size() / 3 << " triangles\n";
            return EXIT_SUCCESS;
        }

        const std::string fixtures = MODEL_FIXTURE_DIR;
        checkModel(MODEL_3MF_FIXTURE, 1);
        checkModel(fixtures + "/triangle.obj", 1);
        checkModel(fixtures + "/triangle.stl", 1);
        checkModel(fixtures + "/triangle.ply", 1);

        bool rejected = false;
        try {
            loadModelVertices(fixtures + "/triangle.unsupported");
        } catch (const std::runtime_error& error) {
            rejected = std::string(error.what()).find("Supported formats") != std::string::npos;
        }
        require(rejected, "unsupported formats should produce an actionable error");

        std::cout << "Model loader tests passed\n";
        return EXIT_SUCCESS;
    } catch (const std::exception& error) {
        std::cerr << error.what() << '\n';
        return EXIT_FAILURE;
    }
}

#include "model_loader.h"

#include <assimp/Importer.hpp>
#include <assimp/config.h>
#include <assimp/postprocess.h>
#include <assimp/scene.h>

#include <algorithm>
#include <cctype>
#include <filesystem>
#include <initializer_list>
#include <limits>
#include <sstream>
#include <stdexcept>

namespace {

std::string lowercaseExtension(const std::string& path) {
    std::string extension = std::filesystem::path(path).extension().string();
    std::transform(extension.begin(), extension.end(), extension.begin(),
                   [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
    return extension;
}

std::string extensionList() {
    std::ostringstream result;
    const auto& extensions = supportedModelExtensions();
    for (size_t i = 0; i < extensions.size(); ++i) {
        if (i != 0) result << ", ";
        result << extensions[i];
    }
    return result.str();
}

void normalize(std::vector<Vertex>& vertices) {
    glm::vec3 bmin(std::numeric_limits<float>::max());
    glm::vec3 bmax(std::numeric_limits<float>::lowest());
    for (const auto& vertex : vertices) {
        bmin = glm::min(bmin, vertex.position);
        bmax = glm::max(bmax, vertex.position);
    }

    const glm::vec3 center = (bmin + bmax) * 0.5f;
    const float radius = glm::length(bmax - bmin) * 0.5f;
    const float scale = radius > 1e-6f ? 1.f / radius : 1.f;
    for (auto& vertex : vertices)
        vertex.position = (vertex.position - center) * scale;
}

} // namespace

const std::vector<std::string>& supportedModelExtensions() {
    static const std::vector<std::string> extensions = {
        ".3mf", ".dae", ".fbx", ".glb", ".gltf", ".obj", ".ply", ".stl"
    };
    return extensions;
}

std::vector<Vertex> loadModelVertices(const std::string& path) {
    const std::string extension = lowercaseExtension(path);
    const auto& supported = supportedModelExtensions();
    if (std::find(supported.begin(), supported.end(), extension) == supported.end()) {
        throw std::runtime_error("Unsupported model format '" +
                                 (extension.empty() ? std::string("(none)") : extension) +
                                 "'. Supported formats: " + extensionList());
    }

    Assimp::Importer importer;
    importer.SetPropertyInteger(AI_CONFIG_PP_SBP_REMOVE,
                                aiPrimitiveType_POINT | aiPrimitiveType_LINE);

    constexpr unsigned int flags =
        aiProcess_Triangulate |
        aiProcess_JoinIdenticalVertices |
        aiProcess_GenSmoothNormals |
        aiProcess_PreTransformVertices |
        aiProcess_SortByPType |
        aiProcess_ImproveCacheLocality |
        aiProcess_ValidateDataStructure;

    const aiScene* scene = importer.ReadFile(path, flags);
    if (!scene) {
        throw std::runtime_error("Could not load '" + path + "': " +
                                 importer.GetErrorString());
    }

    std::vector<Vertex> vertices;
    size_t triangleCount = 0;
    for (unsigned int i = 0; i < scene->mNumMeshes; ++i)
        triangleCount += scene->mMeshes[i]->mNumFaces;
    vertices.reserve(triangleCount * 3);

    for (unsigned int meshIndex = 0; meshIndex < scene->mNumMeshes; ++meshIndex) {
        const aiMesh* mesh = scene->mMeshes[meshIndex];
        for (unsigned int faceIndex = 0; faceIndex < mesh->mNumFaces; ++faceIndex) {
            const aiFace& face = mesh->mFaces[faceIndex];
            if (face.mNumIndices != 3) continue;

            const aiVector3D& a = mesh->mVertices[face.mIndices[0]];
            const aiVector3D& b = mesh->mVertices[face.mIndices[1]];
            const aiVector3D& c = mesh->mVertices[face.mIndices[2]];
            glm::vec3 fallbackNormal = glm::cross(
                glm::vec3(b.x - a.x, b.y - a.y, b.z - a.z),
                glm::vec3(c.x - a.x, c.y - a.y, c.z - a.z));
            if (glm::length(fallbackNormal) > 1e-6f)
                fallbackNormal = glm::normalize(fallbackNormal);

            for (unsigned int index : {face.mIndices[0], face.mIndices[1], face.mIndices[2]}) {
                const aiVector3D& position = mesh->mVertices[index];
                glm::vec3 normal = fallbackNormal;
                if (mesh->HasNormals()) {
                    const aiVector3D& sourceNormal = mesh->mNormals[index];
                    normal = glm::vec3(sourceNormal.x, sourceNormal.y, sourceNormal.z);
                    if (glm::length(normal) > 1e-6f) normal = glm::normalize(normal);
                }
                vertices.push_back({glm::vec3(position.x, position.y, position.z), normal});
            }
        }
    }

    if (vertices.empty()) {
        throw std::runtime_error("Model contains no triangle geometry: " + path);
    }

    normalize(vertices);
    return vertices;
}

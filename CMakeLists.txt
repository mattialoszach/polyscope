cmake_minimum_required(VERSION 3.20)
project(polyscope LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

include(FetchContent)

# ── GLFW ─────────────────────────────────────────────────────────────────────
FetchContent_Declare(
    glfw
    GIT_REPOSITORY https://github.com/glfw/glfw.git
    GIT_TAG        3.4
    GIT_SHALLOW    TRUE
)
set(GLFW_BUILD_DOCS     OFF CACHE BOOL "" FORCE)
set(GLFW_BUILD_TESTS    OFF CACHE BOOL "" FORCE)
set(GLFW_BUILD_EXAMPLES OFF CACHE BOOL "" FORCE)
FetchContent_MakeAvailable(glfw)

# ── GLM ──────────────────────────────────────────────────────────────────────
FetchContent_Declare(
    glm
    GIT_REPOSITORY https://github.com/g-truc/glm.git
    GIT_TAG        1.0.1
    GIT_SHALLOW    TRUE
)
FetchContent_MakeAvailable(glm)

# ── Executable ───────────────────────────────────────────────────────────────
add_executable(polyscope
    src/main.cpp
    src/mesh.cpp
    src/shader.cpp
    src/camera.cpp
    src/renderer.cpp
)

target_include_directories(polyscope PRIVATE src)

# Embed the source-tree paths for shaders and assets so the binary always
# finds them regardless of the working directory.
target_compile_definitions(polyscope PRIVATE
    SHADER_DIR="${CMAKE_SOURCE_DIR}/shaders"
    ASSET_DIR="${CMAKE_SOURCE_DIR}/assets"
)

target_link_libraries(polyscope PRIVATE glfw glm::glm)

# macOS: link the OpenGL framework directly; no function loader (GLAD) is
# needed because all GL 3.x symbols are exported by OpenGL.framework.
if(APPLE)
    target_link_libraries(polyscope PRIVATE "-framework OpenGL")
    target_compile_definitions(polyscope PRIVATE GL_SILENCE_DEPRECATION)
endif()

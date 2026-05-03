cmake_minimum_required(VERSION 3.20)

# Vision hand-pose API requires macOS 11 (Big Sur)
set(CMAKE_OSX_DEPLOYMENT_TARGET "11.0" CACHE STRING "Minimum macOS deployment target" FORCE)

project(polyscope LANGUAGES CXX OBJCXX)

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
add_executable(polyscope MACOSX_BUNDLE
    src/main.cpp
    src/mesh.cpp
    src/shader.cpp
    src/camera.cpp
    src/renderer.cpp
    src/gesture.mm
)

target_include_directories(polyscope PRIVATE src)

# Embed the source-tree paths for shaders and assets so the binary always
# finds them regardless of the working directory.
target_compile_definitions(polyscope PRIVATE
    SHADER_DIR="${CMAKE_SOURCE_DIR}/shaders"
    ASSET_DIR="${CMAKE_SOURCE_DIR}/assets"
)

target_link_libraries(polyscope PRIVATE glfw glm::glm)

if(APPLE)
    target_link_libraries(polyscope PRIVATE
        "-framework OpenGL"
        "-framework AVFoundation"
        "-framework Vision"
        "-framework CoreVideo"
        "-framework CoreMedia"
    )
    target_compile_definitions(polyscope PRIVATE GL_SILENCE_DEPRECATION)

    set_target_properties(polyscope PROPERTIES
        MACOSX_BUNDLE_GUI_IDENTIFIER    "com.polyscope.viewer"
        MACOSX_BUNDLE_BUNDLE_NAME       "Polyscope"
        MACOSX_BUNDLE_BUNDLE_VERSION    "1.0"
        MACOSX_BUNDLE_SHORT_VERSION_STRING "1.0"
        MACOSX_BUNDLE_INFO_PLIST        "${CMAKE_SOURCE_DIR}/Info.plist"
    )
endif()

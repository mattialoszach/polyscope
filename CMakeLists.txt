cmake_minimum_required(VERSION 3.24)

# Apple Vision hand-pose detection requires macOS 11 (Big Sur).
set(CMAKE_OSX_DEPLOYMENT_TARGET "11.0" CACHE STRING "Minimum macOS deployment target" FORCE)
project(polyscope VERSION 1.0.0 LANGUAGES CXX OBJCXX)

if(NOT APPLE)
    message(FATAL_ERROR "Polyscope requires macOS 11 or newer.")
endif()

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_OBJCXX_STANDARD 17)
set(CMAKE_OBJCXX_STANDARD_REQUIRED ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

include(cmake/Dependencies.cmake)
include(cmake/MacOSBundle.cmake)

# Shared by the viewer and optional documentation tool. Only the app entry
# point differs; bundle resources and native bridge code stay in one place.
add_library(polyscope_runtime STATIC
    src/mesh.cpp
    src/model_loader.cpp
    src/shader.cpp
    src/camera.cpp
    src/renderer.cpp
    src/gesture_tracker.cpp
    src/camera_frame.cpp
    src/macos/gesture.mm
    src/macos/platform.mm
)
target_include_directories(polyscope_runtime PUBLIC "${PROJECT_SOURCE_DIR}/src")
target_compile_definitions(polyscope_runtime PUBLIC GL_SILENCE_DEPRECATION)
# Release short-lived Vision and AppKit objects at the end of autorelease pools.
target_compile_options(polyscope_runtime PRIVATE "$<$<COMPILE_LANGUAGE:OBJCXX>:-fobjc-arc>")
target_link_libraries(polyscope_runtime PUBLIC
    glfw glm::glm assimp::assimp
    "-framework OpenGL"
    "-framework AVFoundation"
    "-framework Vision"
    "-framework CoreVideo"
    "-framework CoreMedia"
    "-framework AppKit"
)

add_executable(polyscope MACOSX_BUNDLE src/main.cpp)
polyscope_configure_bundle(polyscope Polyscope com.polyscope.viewer)

# Resource-only changes do not necessarily relink; re-sign every normal build.
add_custom_target(polyscope_sign ALL
    COMMAND /usr/bin/codesign --force --sign - "$<TARGET_BUNDLE_DIR:polyscope>"
    DEPENDS polyscope
    COMMENT "Signing Polyscope for local use"
    VERBATIM
)
install(TARGETS polyscope BUNDLE DESTINATION . COMPONENT Polyscope)

include(CTest)
if(BUILD_TESTING)
    add_subdirectory(tests)
endif()

option(POLYSCOPE_BUILD_DEMOS "Enable the documentation snapshot target" OFF)
if(POLYSCOPE_BUILD_DEMOS)
    add_subdirectory(tools)
endif()

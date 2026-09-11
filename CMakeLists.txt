cmake_minimum_required(VERSION 3.22)

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

# ── Assimp ────────────────────────────────────────────────────────────────────
# Build only the importers exposed by the viewer. This keeps the application
# much smaller than enabling Assimp's full catalogue of 40+ formats.
set(ASSIMP_BUILD_ALL_IMPORTERS_BY_DEFAULT OFF CACHE BOOL "" FORCE)
set(ASSIMP_BUILD_3MF_IMPORTER     ON CACHE BOOL "" FORCE)
set(ASSIMP_BUILD_COLLADA_IMPORTER ON CACHE BOOL "" FORCE)
set(ASSIMP_BUILD_FBX_IMPORTER     ON CACHE BOOL "" FORCE)
set(ASSIMP_BUILD_GLTF_IMPORTER    ON CACHE BOOL "" FORCE)
set(ASSIMP_BUILD_OBJ_IMPORTER     ON CACHE BOOL "" FORCE)
set(ASSIMP_BUILD_PLY_IMPORTER     ON CACHE BOOL "" FORCE)
set(ASSIMP_BUILD_STL_IMPORTER     ON CACHE BOOL "" FORCE)
set(ASSIMP_BUILD_ALL_EXPORTERS_BY_DEFAULT OFF CACHE BOOL "" FORCE)
set(ASSIMP_NO_EXPORT              ON CACHE BOOL "" FORCE)
set(ASSIMP_BUILD_ASSIMP_TOOLS     OFF CACHE BOOL "" FORCE)
set(ASSIMP_BUILD_SAMPLES          OFF CACHE BOOL "" FORCE)
set(ASSIMP_BUILD_TESTS            OFF CACHE BOOL "" FORCE)
set(ASSIMP_BUILD_DOCS             OFF CACHE BOOL "" FORCE)
set(ASSIMP_INSTALL                OFF CACHE BOOL "" FORCE)
set(ASSIMP_WARNINGS_AS_ERRORS     OFF CACHE BOOL "" FORCE)

FetchContent_Declare(
    assimp
    URL https://github.com/assimp/assimp/archive/refs/tags/v6.0.5.tar.gz
    URL_HASH SHA256=edf3749559c2b7d1f758ffb66fc5bec62186221e623b7f2e8969f17ee46ecb6f
    DOWNLOAD_EXTRACT_TIMESTAMP TRUE
)
FetchContent_MakeAvailable(assimp)

# ── Executable ───────────────────────────────────────────────────────────────
add_executable(polyscope MACOSX_BUNDLE
    src/main.cpp
    src/mesh.cpp
    src/model_loader.cpp
    src/shader.cpp
    src/camera.cpp
    src/renderer.cpp
    src/gesture_tracker.cpp
    src/gesture.mm
)

# gesture.mm creates Objective-C framework objects for every camera frame.
# Compile it with ARC so those short-lived Vision/AVFoundation objects are
# released at the end of the callback's autorelease pool.
set_source_files_properties(src/gesture.mm PROPERTIES
    COMPILE_OPTIONS "-fobjc-arc"
)

target_include_directories(polyscope PRIVATE src)

# Embed the source-tree paths for shaders and assets so the binary always
# finds them regardless of the working directory.
target_compile_definitions(polyscope PRIVATE
    SHADER_DIR="${CMAKE_SOURCE_DIR}/shaders"
    ASSET_DIR="${CMAKE_SOURCE_DIR}/assets"
)

target_link_libraries(polyscope PRIVATE glfw glm::glm assimp::assimp)

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

include(CTest)
if(BUILD_TESTING)
    add_executable(gesture_tracker_tests
        tests/gesture_tracker_tests.cpp
        src/gesture_tracker.cpp
    )
    target_include_directories(gesture_tracker_tests PRIVATE src)
    target_link_libraries(gesture_tracker_tests PRIVATE glm::glm)
    add_test(NAME gesture_tracker COMMAND gesture_tracker_tests)

    add_executable(model_loader_tests
        tests/model_loader_tests.cpp
        src/model_loader.cpp
    )
    target_include_directories(model_loader_tests PRIVATE src)

    set(MODEL_3MF_FIXTURE "${CMAKE_CURRENT_BINARY_DIR}/test-fixtures/triangle.3mf")
    add_custom_command(
        OUTPUT "${MODEL_3MF_FIXTURE}"
        COMMAND ${CMAKE_COMMAND} -E make_directory
                "${CMAKE_CURRENT_BINARY_DIR}/test-fixtures"
        COMMAND ${CMAKE_COMMAND} -E tar cf "${MODEL_3MF_FIXTURE}" --format=zip
                "[Content_Types].xml" "_rels/.rels" "3D/3dmodel.model"
        WORKING_DIRECTORY "${CMAKE_SOURCE_DIR}/tests/fixtures/3mf"
        DEPENDS
            tests/fixtures/3mf/[Content_Types].xml
            tests/fixtures/3mf/_rels/.rels
            tests/fixtures/3mf/3D/3dmodel.model
        VERBATIM
    )
    add_custom_target(model_loader_fixtures DEPENDS "${MODEL_3MF_FIXTURE}")
    add_dependencies(model_loader_tests model_loader_fixtures)

    target_compile_definitions(model_loader_tests PRIVATE
        MODEL_FIXTURE_DIR="${CMAKE_SOURCE_DIR}/tests/fixtures"
        MODEL_3MF_FIXTURE="${MODEL_3MF_FIXTURE}"
    )
    target_link_libraries(model_loader_tests PRIVATE glm::glm assimp::assimp)
    add_test(NAME model_loader COMMAND model_loader_tests)
endif()

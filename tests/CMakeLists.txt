add_executable(workspace_tests workspace_tests.cpp "${PROJECT_SOURCE_DIR}/src/camera.cpp")
target_include_directories(workspace_tests PRIVATE "${PROJECT_SOURCE_DIR}/src")
target_link_libraries(workspace_tests PRIVATE glm::glm)
add_test(NAME workspace COMMAND workspace_tests)

add_executable(camera_frame_tests camera_frame_tests.cpp "${PROJECT_SOURCE_DIR}/src/camera_frame.cpp")
target_include_directories(camera_frame_tests PRIVATE "${PROJECT_SOURCE_DIR}/src")
target_link_libraries(camera_frame_tests PRIVATE glm::glm)
add_test(NAME camera_frame COMMAND camera_frame_tests)

add_test(NAME macos_bundle
    COMMAND ${CMAKE_COMMAND}
        "-DAPP_BUNDLE=$<TARGET_BUNDLE_DIR:polyscope>"
        "-DTEST_ROOT=${CMAKE_CURRENT_BINARY_DIR}/bundle-test"
        -P "${CMAKE_CURRENT_SOURCE_DIR}/macos_bundle_test.cmake"
)
add_executable(gesture_tracker_tests
    gesture_tracker_tests.cpp
    "${PROJECT_SOURCE_DIR}/src/gesture_tracker.cpp"
)
target_include_directories(gesture_tracker_tests PRIVATE "${PROJECT_SOURCE_DIR}/src")
target_link_libraries(gesture_tracker_tests PRIVATE glm::glm)
add_test(NAME gesture_tracker COMMAND gesture_tracker_tests)

add_executable(model_loader_tests
    model_loader_tests.cpp
    "${PROJECT_SOURCE_DIR}/src/model_loader.cpp"
)
target_include_directories(model_loader_tests PRIVATE "${PROJECT_SOURCE_DIR}/src")

set(MODEL_3MF_FIXTURE "${CMAKE_CURRENT_BINARY_DIR}/test-fixtures/triangle.3mf")
add_custom_command(
    OUTPUT "${MODEL_3MF_FIXTURE}"
    COMMAND ${CMAKE_COMMAND} -E make_directory
            "${CMAKE_CURRENT_BINARY_DIR}/test-fixtures"
    COMMAND ${CMAKE_COMMAND} -E tar cf "${MODEL_3MF_FIXTURE}" --format=zip
            "[Content_Types].xml" "_rels/.rels" "3D/3dmodel.model"
    WORKING_DIRECTORY "${CMAKE_CURRENT_SOURCE_DIR}/fixtures/3mf"
    DEPENDS
        fixtures/3mf/[Content_Types].xml
        fixtures/3mf/_rels/.rels
        fixtures/3mf/3D/3dmodel.model
    VERBATIM
)
add_custom_target(model_loader_fixtures DEPENDS "${MODEL_3MF_FIXTURE}")
add_dependencies(model_loader_tests model_loader_fixtures)

target_compile_definitions(model_loader_tests PRIVATE
    MODEL_FIXTURE_DIR="${CMAKE_CURRENT_SOURCE_DIR}/fixtures"
    MODEL_3MF_FIXTURE="${MODEL_3MF_FIXTURE}"
)
target_link_libraries(model_loader_tests PRIVATE glm::glm assimp::assimp)
add_test(NAME model_loader COMMAND model_loader_tests)

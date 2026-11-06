# On-disk asset organization is independent of the installed bundle layout.
set(POLYSCOPE_SHADERS
    "${PROJECT_SOURCE_DIR}/assets/shaders/model.vert"
    "${PROJECT_SOURCE_DIR}/assets/shaders/model.frag"
    "${PROJECT_SOURCE_DIR}/assets/shaders/flat.vert"
    "${PROJECT_SOURCE_DIR}/assets/shaders/flat.frag"
    "${PROJECT_SOURCE_DIR}/assets/shaders/overlay.vert"
    "${PROJECT_SOURCE_DIR}/assets/shaders/overlay.frag"
)
set(POLYSCOPE_STARTER "${PROJECT_SOURCE_DIR}/assets/models/sample.obj")
set(POLYSCOPE_ICON "${PROJECT_SOURCE_DIR}/assets/icons/AppIcon.icns")

function(polyscope_configure_bundle target name identifier)
    target_link_libraries(${target} PRIVATE polyscope_runtime)
    target_sources(${target} PRIVATE
        ${POLYSCOPE_SHADERS} "${POLYSCOPE_STARTER}" "${POLYSCOPE_ICON}"
    )
    # Apply properties in the target's directory (including tools/ targets).
    set_source_files_properties(${POLYSCOPE_SHADERS} TARGET_DIRECTORY ${target}
        PROPERTIES MACOSX_PACKAGE_LOCATION "Resources/shaders"
    )
    set_source_files_properties("${POLYSCOPE_STARTER}" TARGET_DIRECTORY ${target}
        # .obj is also an object-file extension; this is Wavefront model data.
        PROPERTIES HEADER_FILE_ONLY TRUE EXTERNAL_OBJECT FALSE
        MACOSX_PACKAGE_LOCATION "Resources/assets"
    )
    set_source_files_properties("${POLYSCOPE_ICON}" TARGET_DIRECTORY ${target}
        PROPERTIES MACOSX_PACKAGE_LOCATION "Resources"
    )
    set_target_properties(${target} PROPERTIES
        OUTPUT_NAME "${name}"
        # Keep generated apps together, including the optional tools/ target.
        RUNTIME_OUTPUT_DIRECTORY "${PROJECT_BINARY_DIR}"
        MACOSX_BUNDLE_GUI_IDENTIFIER "${identifier}"
        MACOSX_BUNDLE_BUNDLE_NAME "${name}"
        MACOSX_BUNDLE_BUNDLE_VERSION "${PROJECT_VERSION}"
        MACOSX_BUNDLE_SHORT_VERSION_STRING "${PROJECT_VERSION}"
        MACOSX_BUNDLE_ICON_FILE "AppIcon.icns"
        MACOSX_BUNDLE_INFO_PLIST "${PROJECT_SOURCE_DIR}/packaging/macos/Info.plist"
        XCODE_ATTRIBUTE_CODE_SIGN_IDENTITY "-"
    )
endfunction()

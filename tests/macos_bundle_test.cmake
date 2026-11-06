# Run the real executable from a relocated bundle with spaces in its path.
file(REMOVE_RECURSE "${TEST_ROOT}")
file(MAKE_DIRECTORY "${TEST_ROOT}/Moved App")
file(COPY "${APP_BUNDLE}" DESTINATION "${TEST_ROOT}/Moved App")
set(bundle "${TEST_ROOT}/Moved App/Polyscope.app")
foreach(resource IN ITEMS AppIcon.icns assets/sample.obj
        shaders/model.vert shaders/model.frag shaders/flat.vert shaders/flat.frag
        shaders/overlay.vert shaders/overlay.frag)
    if(NOT EXISTS "${bundle}/Contents/Resources/${resource}")
        message(FATAL_ERROR "Missing bundled resource: ${resource}")
    endif()
endforeach()

execute_process(
    COMMAND "${bundle}/Contents/MacOS/Polyscope" --check-resources
    WORKING_DIRECTORY "${TEST_ROOT}"
    RESULT_VARIABLE result OUTPUT_VARIABLE output ERROR_VARIABLE error
)
if(NOT result EQUAL 0)
    message(FATAL_ERROR "Relocated app failed: ${output}${error}")
endif()

execute_process(
    COMMAND /usr/bin/otool -L "${bundle}/Contents/MacOS/Polyscope"
    RESULT_VARIABLE result OUTPUT_VARIABLE libraries
)
if(NOT result EQUAL 0)
    message(FATAL_ERROR "Cannot inspect linked libraries")
endif()
string(REPLACE "\n" ";" lines "${libraries}")
list(REMOVE_AT lines 0)
foreach(line IN LISTS lines)
    string(STRIP "${line}" line)
    if(line AND NOT line MATCHES "^(/System/Library/|/usr/lib/)")
        message(FATAL_ERROR "App depends on a non-system library: ${line}")
    endif()
endforeach()
message(STATUS "${output}Only system dynamic libraries are required.")

# This tool renders only its own window and a still hand image. It never opens
# a camera or captures the desktop, and is not part of the installed app.
add_executable(polyscope_demos EXCLUDE_FROM_ALL MACOSX_BUNDLE render-demos.mm)
target_compile_options(polyscope_demos PRIVATE -fobjc-arc)
polyscope_configure_bundle(polyscope_demos PolyscopeDemos com.polyscope.demos)

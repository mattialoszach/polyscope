#pragma once

// On macOS, OpenGL 3.x function symbols are exported directly by the system
// OpenGL.framework, so no function pointer loader (like GLAD) is needed.
// The GL_SILENCE_DEPRECATION flag is passed via CMake; we re-guard here so
// the header is still usable if included outside the build system.
#ifdef __APPLE__
#  ifndef GL_SILENCE_DEPRECATION
#    define GL_SILENCE_DEPRECATION
#  endif
#  include <OpenGL/gl3.h>
#else
#  error "Add a cross-platform function loader (e.g. GLAD) for non-Apple targets."
#endif

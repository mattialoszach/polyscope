# polyscope
A fast and minimal 3D model viewer written in C++.

## Features
- Loads Wavefront **OBJ** files (positions, normals, polygons)
- **Orbit** · **Pan** · **Zoom** — intuitive mouse controls
- Blinn-Phong shading with a warm/cool two-light setup
- Toggleable XZ **grid** and **wireframe** mode
- Drag-and-drop to swap models at runtime

## Controls

| Input | Action |
|-------|--------|
| Left-drag | Orbit |
| Right-drag | Pan |
| Scroll | Zoom |
| `R` | Reset camera |
| `G` | Toggle grid |
| `W` | Toggle wireframe |
| `Esc` | Quit |

## Building

Requires: **CMake 3.20+**, **Xcode Command Line Tools** (macOS).  
GLFW and GLM are fetched automatically at configure time — no manual installs.

```bash
cmake -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build -j$(nproc)
```

## Running

```bash
# Default sample model
./build/polyscope

# Your own OBJ
./build/polyscope path/to/model.obj
```

You can also **drag and drop** any `.obj` file onto the running window.

## Project Structure

```
polyscope/
├── CMakeLists.txt          # build system
├── shaders/
│   ├── model.vert/frag     # Blinn-Phong lighting
│   └── flat.vert/frag      # flat colour (grid)
├── src/
│   ├── gl.h                # OpenGL header wrapper
│   ├── shader.h/cpp        # GLSL program loader
│   ├── mesh.h/cpp          # OBJ parser + GPU upload
│   ├── camera.h/cpp        # arcball camera
│   ├── renderer.h/cpp      # draw calls
│   └── main.cpp            # window + event loop
└── assets/
    └── sample.obj          # default cube model
```

## Tech Stack

| | |
|-|-|
| OpenGL 3.3 core | GPU rendering |
| GLFW 3 | Window & input |
| GLM | Math (vec3, mat4 …) |

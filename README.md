# polyscope
A fast and minimal 3D model viewer written in C++.

## Features
- Loads Wavefront **OBJ** files (positions, normals, polygons)
- **Orbit** · **Pan** · **Zoom** — intuitive mouse controls
- Blinn-Phong shading with a warm/cool two-light setup
- Toggleable XZ **grid** and **wireframe** mode
- Drag-and-drop to swap models at runtime
- Camera hand controls with live skeleton and gesture feedback (macOS)

## Controls

| Input | Action |
|-------|--------|
| Left-drag | Orbit |
| Right-drag | Pan |
| Scroll | Zoom |
| `R` | Reset camera |
| `G` | Toggle grid |
| `W` | Toggle wireframe |
| `C` | Toggle camera hand controls |
| `Esc` | Quit |

## Hand controls

Keep one hand fully visible in the camera preview. A grey outline means no action
is active; the outline changes colour and the window title names the gesture once
it is confirmed.

| Gesture | Action |
|---------|--------|
| Open palm (3+ fingers) + move | Orbit |
| Peace sign + move | Pan |
| Pinch thumb/index, then move toward/away from camera | Zoom in/out |

Gestures are confirmed over several frames to avoid accidental mode changes. A
closed fist or a single raised finger is idle, so it can be used to reposition
your hand without moving the model.

## Building

Requires: **CMake 3.20+**, **Xcode Command Line Tools** (macOS).  
GLFW and GLM are fetched automatically at configure time — no manual installs.

```bash
cmake -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build --parallel
```

## Running

```bash
# Default sample model
open build/polyscope.app

# Your own OBJ
./build/polyscope.app/Contents/MacOS/polyscope path/to/model.obj
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
│   ├── gesture_tracker.*   # gesture classification + motion filtering
│   ├── gesture.mm          # Apple Vision + camera capture
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

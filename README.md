# polyscope

A small 3D model viewer for macOS, written in C++ and OpenGL. Load an OBJ file
and inspect it with a mouse or hand gestures.

## Features

- Wavefront OBJ loading, including polygons and normals
- Orbit, pan and zoom controls
- Shaded and wireframe views with an optional ground grid
- Drag-and-drop model loading
- Hand controls powered by Apple Vision

## Build

You need macOS 11 or newer, CMake 3.20+, and the Xcode Command Line Tools.
GLFW and GLM are downloaded automatically.

```bash
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build --parallel
```

## Run

Open the bundled sample model:

```bash
open build/polyscope.app
```

To open a particular OBJ file:

```bash
open build/polyscope.app --args path/to/model.obj
```

You can also drag an OBJ file onto the viewer while it is running.

## Mouse and keyboard

| Input | Action |
|-------|--------|
| Left-drag | Orbit |
| Right-drag | Pan |
| Scroll | Zoom |
| `R` | Reset the camera |
| `G` | Show or hide the grid |
| `W` | Toggle wireframe mode |
| `C` | Turn hand controls on or off |
| `Esc` | Quit |

## Hand controls

Hand controls start automatically. Keep one hand fully visible in the preview;
the window title shows which gesture is active.

| Gesture | Action |
|---------|--------|
| Open palm, then move your hand | Orbit |
| Peace sign, then move your hand | Pan |
| Pinch thumb and index finger, then move closer to the camera | Zoom in |
| Keep pinching and move away from the camera | Zoom out |
| Closed fist or one raised finger | Pause and reposition |

Hold a pose briefly until it is recognised before moving. For a long orbit or
pan, make the idle pose, move your hand back to a comfortable position, then
resume the gesture. This works like lifting and repositioning a mouse.

For steadier tracking, face your palm toward the camera and avoid letting your
hand leave the preview. On first launch, macOS will ask for camera permission.

## Tests

```bash
ctest --test-dir build --output-on-failure
```

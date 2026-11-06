# Polyscope

<img src="assets/AppIcon.png" alt="Polyscope app icon: a mint and cyan cube on a dark rounded tile" width="160">

A small 3D model viewer for macOS, written in C++ and OpenGL. Load a model and
inspect it with a mouse or hand gestures.

## Features

- 3MF, STL, OBJ, PLY, glTF/GLB, FBX, and Collada model loading
- Orbit, pan and zoom controls
- Shaded and wireframe views with an optional ground grid
- Drag-and-drop model loading
- Native macOS file picker with `⌘O`
- Hand controls powered by Apple Vision

## Build and install

You need macOS 11 or newer, CMake 3.24+, and the Xcode Command Line Tools.
Install Apple's tools once if you do not have Xcode:

```bash
xcode-select --install
```

Then, from this checkout:

```bash
make setup    # checks tools; installs CMake through Homebrew if needed
make install  # builds and installs /Applications/Polyscope.app
```

If Homebrew is unavailable, install [CMake](https://cmake.org/download/) and make
sure `cmake` is on your `PATH`. GLFW, GLM, and Assimp download automatically on
the first build. Later builds reuse them. The app contains its shaders, sample
model, icon, and statically linked dependencies, so it runs independently of the
checkout. Builds target the current Mac's architecture.

Launch **Polyscope** from Applications or Spotlight. You can also run:

```bash
open /Applications/Polyscope.app
```

To install in your own Applications folder:

```bash
make install APPLICATIONS_DIR="$HOME/Applications"
```

Quit Polyscope before replacing an installed version. Installation validates a
staged copy before replacing the existing app. If `/Applications` is not writable,
use the per-user command above; building does not require `sudo`.

## Update

From this checkout:

```bash
make update
```

This runs `git pull --ff-only` on the current branch, rebuilds, and replaces
`/Applications/Polyscope.app`. It requires a clean checkout and a branch with a
Git upstream. Commit or stash changes first. To rebuild and install your local
changes without pulling, use `make install`. For a per-user installation, pass
`APPLICATIONS_DIR="$HOME/Applications"` to `make update` too.

## Build or run without installing

```bash
make build    # build/Polyscope.app
make run      # build and launch the bundled sample
```

To open a particular model file:

```bash
open /Applications/Polyscope.app --args /absolute/path/to/model.3mf
```

Press `⌘O` to choose a model, or drag any supported file onto the running viewer.
The viewer imports geometry and normals; model materials, textures, cameras, and
animations are not rendered yet.

The underlying CMake commands remain available:

```bash
cmake -S . -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build --parallel
cmake --install build --prefix /Applications --component Polyscope
```

The app is signed locally with an ad hoc signature. Distribution to other Macs
with a Developer ID and notarization is a separate release step.

## App icon

The icon uses a simple three-plane cyan cube on a dark rounded tile. The
1024px preview and full-resolution `.icns` are checked in, so a regular build
needs no icon tools. Edit `scripts/generate-icon.swift` and run `make icon` to
regenerate all standard and Retina sizes using AppKit and `iconutil`.

## Mouse and keyboard

| Input | Action |
|-------|--------|
| Left-drag | Orbit |
| Right-drag | Pan |
| Scroll | Zoom |
| `⌘O` | Open a model |
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
make test
```

Tests cover gesture tracking, model import, and running a relocated bundle from
a path with spaces. The bundle check also rejects non-system dynamic libraries.
For a quick rendering check without opening the camera:

```bash
build/Polyscope.app/Contents/MacOS/Polyscope --smoke-test
```

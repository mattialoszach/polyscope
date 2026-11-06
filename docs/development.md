# Development

Run commands from the repository root. `make build` creates a Release app;
`make test` also runs the model, workspace, gesture, camera-frame, and relocated
bundle checks. Dependencies download into the build directory on first use.

## Layout

| Directory | Contents |
| --- | --- |
| `src/` | Viewer logic, rendering, model loading, and shared headers |
| `src/macos/` | AppKit interface and AVFoundation/Vision camera implementation |
| `assets/` | Runtime shaders, starter model, and app icons |
| `packaging/macos/` | App bundle metadata |
| `cmake/` | Dependency configuration and shared bundle setup |
| `tests/` | Test targets, small model fixtures, and bundle validation |
| `tools/` | Optional documentation renderer |
| `scripts/` | Build/install commands and icon generator |
| `docs/` | Developer notes and README demo images |
| `build/` | Generated apps, dependencies, logs, and test output; ignored by Git |

The C++ files stay together while the project is small. Platform-specific
Objective-C++ code lives in `src/macos/`. Screenshots belong in `docs/demos/`;
they are not bundled with the app.

## Build targets

The app and documentation renderer link the same `polyscope_runtime` library.
Bundle resources and metadata are configured once in `cmake/MacOSBundle.cmake`.
Tests declare their own targets in `tests/CMakeLists.txt` and can run without
camera permission.

For a separate Debug build:

```bash
cmake -S . -B build-debug -DCMAKE_BUILD_TYPE=Debug -DBUILD_TESTING=ON
cmake --build build-debug --parallel
ctest --test-dir build-debug --output-on-failure
```

`make install BUILD_DIR=build-debug` rebuilds that directory as Release before
installing. Use the CMake commands above when you want to keep a Debug build.

The optional `polyscope_demos` target is excluded from normal builds and installs.
See [demo sources and export instructions](demos/README.md) to refresh its images.
Run `make icon` after editing `scripts/generate-icon.swift` to update
`assets/icons/AppIcon.png` and `AppIcon.icns`.

## Before committing

Run `make test` for code, build, packaging, or asset changes. For native interface
or renderer changes, also run the built app's `--ui-smoke-test` and
`--smoke-test` checks; neither uses the camera. The separate
`--camera-smoke-test` check uses a live camera if permission is already granted.
Keep generated files in a build directory and commit the source assets needed
to rebuild the bundle.

GitHub Actions builds and runs the automated suite on an Apple Silicon macOS
runner. It also compiles the documentation tool; live camera tests stay local.

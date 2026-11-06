# Demo images

The snapshots use Polyscope's native interface and OpenGL renderer with these
SO101 models:

- `Prusa_Follower_SO101.stl`
- `Wrist_Cam_Mount_32x32_UVC_Module_SO101.stl`

The STL files are not included here. `model-tabs.webp` shows ordinary viewing;
`hand-controls.webp` demonstrates the preview with a still image. Apple Vision
detects the sample's 21 hand joints, and Polyscope classifies its open palm as
the orbit gesture. The export tool uses neither a webcam nor a desktop capture.

The hand comes from **[Human-Hands-Front-Back](https://commons.wikimedia.org/wiki/File:Human-Hands-Front-Back.jpg)**
by **Evan-Amos**, licensed under **[CC BY-SA 3.0](https://creativecommons.org/licenses/by-sa/3.0/)**.
It was cropped to the palm-side hand, resized, placed on a wider background,
mirrored in the preview, and overlaid with detected landmarks.
`hand-sample.webp` and `hand-controls.webp` are distributed under the same
CC BY-SA 3.0 license. The photographer does not endorse Polyscope.

To refresh the snapshots, build the optional export target and pass in the two
STLs. The `dwebp` and `cwebp` tools are part of WebP (`brew install webp`).

```bash
cmake -S . -B build -DPOLYSCOPE_BUILD_DEMOS=ON
cmake --build build --target polyscope_demos --parallel
mkdir -p build/demos
dwebp docs/demos/hand-sample.webp -o build/demos/hand.png
build/PolyscopeDemos.app/Contents/MacOS/PolyscopeDemos \
  build/demos build/demos/hand.png \
  /path/to/Prusa_Follower_SO101.stl \
  /path/to/Wrist_Cam_Mount_32x32_UVC_Module_SO101.stl
cwebp -lossless -z 9 -exact build/demos/model-tabs.png -o docs/demos/model-tabs.webp
cwebp -lossless -z 9 -exact build/demos/hand-controls.png -o docs/demos/hand-controls.webp
```

The exporter in `tools/render-demos.mm` lives outside the installed app and
renders only its own hidden window. It does not change Polyscope's saved
preferences. The final snapshots
use lossless WebP to keep labels and model edges sharp.

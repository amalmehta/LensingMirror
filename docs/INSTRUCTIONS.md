# Instructions

## Set up

You need macOS 14 or later, Xcode 15 or later and a Metal-capable GPU. [XcodeGen](https://github.com/yonaskolb/XcodeGen) is only needed if you change `project.yml`.

The Xcode project is generated from `project.yml`. To regenerate it:

```bash
xcodegen generate
```

The Metal shader ships as source (`LensShaders.msl`) and is compiled at launch, so Xcode's separate Metal Toolchain download isn't needed.

## Run

Open `LensingMirror.xcodeproj` and press ⌘R. Or build from the terminal:

```bash
xcodebuild -project LensingMirror.xcodeproj -scheme "Lensing Mirror" -configuration Release -derivedDataPath build build
```

```bash
open "build/Build/Products/Release/Lensing Mirror.app"
```

The first launch asks for camera access. Video stays on your Mac. If you say no, or there's no camera, you'll see the built-in test pattern instead and a banner with a link to Privacy settings.

## Use

| Control | What it does |
|---|---|
| **Mass** | Size of the black hole. Bigger means a bigger shadow and stronger bending. |
| **Spin** | Kerr spin a/M, from 0 (Schwarzschild, no spin) to 0.998. Spin flattens one side of the shadow and drags the image around. |
| **Distance** | How far you are from the hole. The caption shows it in units of M, never closer than 6 M. |
| Compare (⌘D) | Side by side: no spin on the left, your spin on the right, with the same mass and distance. |
| Overlay (⌘L) | Marks the **Einstein ring** (gold, dashed), where the point straight behind the hole appears, and the **photon sphere** (orange), the edge of the shadow, where light can orbit. |
| Snapshot (⌘T) | Saves a PNG. |
| Record GIF (⌘R) | Records a short looping GIF (3 s by default). Click again to cancel. |
| Settings (⌘,) | Every preference, in one place (below). |
| Feedback tab | On the window's right edge. Saves a note on this Mac (Bug / Idea / Other). Nothing is sent. |

When you move a slider, the picture goes soft for a moment and then sharpens. While you drag it shows a quick preview, and the full-resolution version is traced in the background.

Snapshots and GIFs go to `~/Pictures/Lensing Mirror/`. Each save shows a toast with **Show in Finder**.

### Settings

- **Camera:** which camera; use the test pattern instead; flip the camera left-right like a mirror (the test pattern is never flipped); ask the camera for 60 fps.
- **Lens:** how far behind the hole the camera image sits (further back means a wider Einstein ring); field of view; ray resolution (Low / Standard / High); ray accuracy (Fast / Balanced / Precise); show frame rate and GPU time.
- **Export:** folder; include the overlay; GIF length, frame rate and width.
- **Reset to Defaults** puts everything back.

## Test

```bash
xcodebuild -project LensingMirror.xcodeproj -scheme "Lensing Mirror" -derivedDataPath build test
```

The suite has 20 tests: physics, GPU against the CPU tracer, overlay, the frame loop, timing and export. A 21st test renders the README images and is skipped unless asked. Timing lines are printed as `lens map …` and `composite …`.

If the project lives in Desktop, Documents or Downloads, macOS may ask whether the test host can access that folder (it reads its debug symbols when a test fails). To avoid that, put the build output somewhere else, such as `/tmp`:

```bash
xcodebuild -project LensingMirror.xcodeproj -scheme "Lensing Mirror" -derivedDataPath /tmp/LensingMirrorBuild test
```

To regenerate the README images (written by the real shader using the test pattern), render them to a temporary folder, then copy them in:

```bash
TEST_RUNNER_DOC_IMAGES_DIR=/tmp/LensingMirrorImages xcodebuild -project LensingMirror.xcodeproj -scheme "Lensing Mirror" -derivedDataPath /tmp/LensingMirrorBuild test -only-testing:LensingMirrorTests/DocImageTests
```

```bash
cp /tmp/LensingMirrorImages/*.png docs/images/
```

The test creates the folder if needed. `docs/images/window.png` is a screenshot of the app window and isn't generated.

## Troubleshooting

- **Test pattern instead of your face:** check System Settings → Privacy & Security → Camera, or Settings → Camera in the app.
- **Low frame rate:** turn on *Show frame rate* in Settings → Lens. If the GPU time is low but the frame rate isn't 60, the Mac may be thermally throttled. Lowering *Ray resolution* makes the picture sharpen sooner after a slider moves.

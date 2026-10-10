# File structure

```
Lensing Mirror/
├── README.md                     What it is, pictures, links
├── Lensing Mirror.md             The project brief (deliverables, assumptions, changelog)
├── project.yml                   XcodeGen spec → LensingMirror.xcodeproj
├── LensingMirror.xcodeproj/      Generated Xcode project
├── Sources/
│   ├── App/
│   │   ├── LensingMirrorApp.swift    App entry, window, Settings scene, Mirror menu and shortcuts
│   │   ├── AppModel.swift            Sliders, toggles, source status, exports, toasts
│   │   ├── Preferences.swift         Every preference (UserDefaults), reset to defaults
│   │   └── Info.plist                Bundle info and camera usage text (generated from project.yml)
│   ├── Physics/
│   │   └── Kerr.swift                Kerr–Schild ray equation, static-observer camera, CPU ray tracer
│   ├── Rendering/
│   │   ├── LensShaders.msl           Metal: lens-map kernel and composite shaders (compiled at launch)
│   │   ├── GPUTypes.swift            Swift twins of the shader's parameter structs
│   │   ├── LensEngine.swift          Pipelines, map building (whole or in bands), composite, readback
│   │   └── MirrorRenderer.swift      MTKView delegate: the 60 fps loop, previews, snapshots, GIF frames
│   ├── Camera/
│   │   ├── CameraSource.swift        Webcam → Metal textures (AVFoundation + CVMetalTextureCache)
│   │   └── TestPattern.swift         Built-in picture when there's no camera
│   ├── Overlay/
│   │   ├── LensCurves.swift          Einstein ring + photon sphere found in a lens map; paths
│   │   └── OverlayLayer.swift        Pane layout, on-screen overlay and legend, overlay in exports
│   ├── Export/
│   │   └── Exporter.swift            PNG and GIF writing, GIF frame pacing
│   └── UI/
│       ├── ContentView.swift         The window: mirror, overlay, pane labels, banners, frame rate
│       ├── ControlBar.swift          Mass / Spin / Distance sliders and action buttons
│       ├── SettingsView.swift        Settings window (Camera, Lens, Export)
│       ├── FeedbackTab.swift         Feedback tab and its local store
│       └── Palette.swift             Colour families for labels, overlay and feedback kinds
├── Tests/
│   ├── PhysicsTests.swift            Closed forms, camera frame, Hamiltonian, shadow, ring, lens equation
│   ├── GPUTests.swift                Shader vs CPU, overlay accuracy, timings, export; support tests
│   ├── RendererTests.swift           The real frame loop: preview → full, compare, snapshot, GIF
│   └── DocImageTests.swift           Renders docs/images (only when asked)
└── docs/
    ├── INSTRUCTIONS.md               Set up, run, use, test
    ├── SYSTEM-DESIGN.md              Architecture, flows, decisions, testing, limits
    ├── FILE-STRUCTURE.md             This file
    └── images/                       README pictures
```

`build/` (local build output) is git-ignored and isn't part of the project.

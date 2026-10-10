# Lensing Mirror

A live webcam mirror that bends your face through a black hole, spinning (Kerr) or not (Schwarzschild), ray-traced in Metal at 60 fps.

![Lensing Mirror: the built-in test pattern seen through a Kerr black hole with spin 0.7, with the Einstein ring and photon sphere marked](docs/images/window.png)

| No spin vs spin 0.95, side by side (Compare, ⌘D) |
|---|
| ![Schwarzschild and Kerr panes side by side](docs/images/compare.png) |

| Spin 0 | Spin 0.5 | Spin 0.9 | Spin 0.998 |
|---|---|---|---|
| ![spin 0](docs/images/spin-0.000.png) | ![spin 0.5](docs/images/spin-0.500.png) | ![spin 0.9](docs/images/spin-0.900.png) | ![spin 0.998](docs/images/spin-0.998.png) |

Gold dashes mark the **Einstein ring** (where the point straight behind the hole shows up). Orange marks the **photon sphere** (the shadow's edge). As spin rises, the shadow shifts and flattens on one side.

```mermaid
flowchart LR
  CAM[Webcam] --> MIX
  S[Mass · Spin · Distance] --> MAP[Metal: trace one ray per pixel<br/>Kerr–Schild geodesics → lens map]
  MAP --> MIX[Metal: look up every pixel<br/>in the map, 60 fps]
  MAP --> OV[Einstein ring + photon sphere]
  MIX --> WIN[Window] & EXP[PNG · GIF]
  OV --> WIN
```

## Links

- [Instructions](docs/INSTRUCTIONS.md): set up, run, use, test
- [System design](docs/SYSTEM-DESIGN.md): how it works and why
- [File structure](docs/FILE-STRUCTURE.md): what's where
- Builds on [Black Hole Simulator](https://amalmehta.github.io/BlackHoleSimulator/)

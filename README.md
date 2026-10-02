# Morning Monk

iOS app that coaches the morning routine with on-device pose estimation. Full product spec in [SPEC.md](SPEC.md).

## Run it

Needs a Mac with Xcode 15+ and a real iPhone (the simulator has no camera).

```sh
brew install xcodegen
xcodegen generate
open MorningMonk.xcodeproj
```

In Xcode, pick your team under Signing & Capabilities for the MorningMonk target, select your phone, and run. The `.xcodeproj` is generated from `project.yml` and not committed, so rerun `xcodegen generate` after pulling changes that add files.

Tests: `Cmd+U` in Xcode, or CI runs them on every push (`.github/workflows/ios.yml`).

## Status

**M1: Camera + pose** (current). The app opens straight into the pose debug screen:

- Front camera, portrait, 30fps, mirrored like a selfie.
- Vision body pose on every frame; drops to every 2nd frame if the average exceeds 20ms.
- Joints under 0.3 confidence are dropped, the rest go through a One Euro filter.
- Skeleton overlay: blue = your left side, orange = your right, white = center. Faded dots are 0.3-0.5 confidence.
- HUD: camera fps, pose fps, ms per frame, stride, joint count.
- "Joints" toggle shows raw confidence for all 19 joints, including dropped ones.

### M1 review checklist (on device)

1. Skeleton tracks smoothly while you do slow arm swings, no visible jitter when standing still.
2. Raise your **left** arm: the blue arm should move. If orange moves, left/right labels are flipped.
3. HUD shows ~30 pose fps and stride 1 on your phone. Note the ms number.
4. Step back until your feet are in frame: ankles should go green in the Joints panel.
5. Try baggy clothes and dim light, watch which joints drop.

## Layout

```
MorningMonk/
  App/              entry point
  Features/Debug/   M1 pose debug screen
  Pose/             camera, Vision, PoseFrame, smoothing
MorningMonkTests/   filter, normalization, geometry tests
```

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

The app opens to a debug menu while the real screens don't exist yet.

**M1: Camera + pose** (done, awaiting on-device check). "Pose tracking" in the menu:

- Front camera, portrait, 30fps, mirrored like a selfie.
- Vision body pose on every frame; drops to every 2nd frame if the average exceeds 20ms.
- Joints under 0.3 confidence are dropped, the rest go through a One Euro filter.
- Skeleton overlay: blue = your left side, orange = your right, white = center. Faded dots are 0.3-0.5 confidence.
- HUD: camera fps, pose fps, ms per frame, stride, joint count. "Joints" shows raw confidence for all 19 joints.

**M2: Arm swings end to end** (current). "Arm Swings" in the menu:

- Detector counts swings and scores form. Faults: arms above shoulder height, bent elbows, no knee bounce for 8 swings. A fault has to hold for 1.5s before it counts.
- Coach speaks one cue at most every 6s, worst fault first, rotates phrasings, praises a fix, goes quiet after 15s of clean form.
- Panel shows live metrics (wrist peak, elbow and knee angles, swings since last bounce), each fault's state (yellow = condition true now, red = active), and the last cues.
- **Record** captures pose frames; **Stop** then the share button exports them as JSON. These recordings are what we tune thresholds against.
- All thresholds and cue lines live in `MorningMonk/Moves/moves.json` and `MorningMonk/Coach/coach.json`.

### On-device checklist

1. Pose tracking: skeleton tracks smoothly, no jitter standing still.
2. Raise your **left** arm: the blue arm should move. If orange moves, left/right labels are flipped.
3. Note pose fps (want ~30) and ms per frame (budget: under 20ms).
4. Arm swings, standing at ~45° with your whole body in frame:
   - Swing normally with a small knee bounce every few swings: reps count, no cues.
   - Swing above your head: "Shoulder height, no higher."
   - Swing with bent elbows: "Let the arms hang loose."
   - Swing with locked knees for ~12s: "Soft knees, small bounce."
5. Record one clip of each (good, too high, bent, no bounce) and send me the JSON files.

## Layout

```
MorningMonk/
  App/              entry point
  Features/Debug/   debug menu, pose and move debug screens
  Pose/             camera, Vision, PoseFrame, smoothing, recordings
  Moves/            moves.json, detector protocol and shared machinery
  Moves/Detectors/  one detector per move
  Coach/            coach engine, line bank, speech
MorningMonkTests/   unit tests, synthetic pose generator, detector harness
```

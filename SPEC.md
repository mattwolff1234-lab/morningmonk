# Morning Monk: Build Prompt (v1)

Working title: **Morning Monk**.

---

## What we're building

An iOS app that guides users through the viral "Chinese morning routine" (Shuai Shou Gong arm swings, lymphatic hops, trunk twists, etc.). The user props their phone up, the front camera watches them, on-device pose estimation scores their form in real time, and a monk mascot coaches them through each move with short cues. Every finished session produces a shareable "Day X" card. Subscription business.

Core loop: open app in the morning → 9 minutes, 9 moves, 60 seconds each → monk corrects form live → session score + streak → share card.

## Stack (do not deviate without asking)

- **SwiftUI**, iOS 17+, Swift 5.9+
- **AVFoundation** for the camera feed
- **Apple Vision**: `VNDetectHumanBodyPoseRequest` (2D, 19 joints) as the primary pose source. Evaluate `VNDetectHumanBodyPose3DRequest` for moves where depth matters (arm swings, trunk twists), but ship on 2D if 3D is too slow or noisy.
- **Rive** (rive-ios runtime) for the monk mascot's animated state machine. Placeholder: a simple SwiftUI shape/emoji monk until real art exists.
- **AVSpeechSynthesizer** for spoken cues in v1 (swap for recorded voice lines later)
- **StoreKit 2** + **RevenueCat** for subscriptions
- **SwiftData** for local persistence (sessions, streaks, settings)
- No backend in v1. Everything runs on-device. No video is stored or uploaded unless the user explicitly records a share clip.

## Architecture

```
App/
  MorningMonkApp.swift
Features/
  Onboarding/
  Home/                 // streak, start button, routine picker
  Session/              // the live workout screen
  Results/              // score breakdown + share card
  Paywall/
Pose/
  CameraManager.swift   // AVCaptureSession, front camera, 30fps
  PoseEstimator.swift   // runs Vision on frames, outputs PoseFrame
  PoseFrame.swift       // joint positions + confidences, normalized
  Smoothing.swift       // One Euro filter on joints to kill jitter
Moves/
  MoveDefinition.swift  // data model loaded from JSON
  MoveDetector.swift    // protocol: consume PoseFrames, emit reps/phases/faults
  Detectors/            // one detector per move
  moves.json            // move library: names, durations, thresholds, cue text
Coach/
  CoachEngine.swift     // decides WHEN to speak/animate (rate limiting, priority)
  MonkState.swift       // idle, encouraging, correcting, celebrating, resting
Data/
  SessionRecord.swift   // SwiftData models
  StreakService.swift
Share/
  ShareCardRenderer.swift  // ImageRenderer -> PNG for IG Stories / TikTok
```

Key rule: **move logic is data-driven.** Thresholds and cue text live in `moves.json` so they can be tuned without touching detector code.

## Pose pipeline

1. Camera at 30fps, front-facing, portrait.
2. Run Vision on every frame (drop to every 2nd frame if CPU > budget).
3. Discard joints below 0.3 confidence. Normalize coordinates relative to shoulder width so thresholds work regardless of distance from camera.
4. Smooth with a One Euro filter.
5. Feed `PoseFrame` to the active move's detector.

**Calibration step before each session:** user must be fully in frame (head to ankles visible, confidence > 0.5 on ankles, hips, shoulders, wrists) for 2 seconds. Monk says "Step back until I can see your feet." Do not start the timer until calibrated.

**Camera angle per move:** some moves read badly from straight on. Each move in `moves.json` declares `"facing": "front" | "side" | "angle45"`. During the 10-second transition between moves, the monk tells the user which way to turn.

## Move library (v1: the 9-move "Classic Morning" routine)

Each detector outputs: rep count (or hold time), a 0-100 form score, and fault events. Each fault maps to one short spoken cue. Starting thresholds below are guesses; expose them all in JSON for tuning.

| # | Move | Facing | What we measure | Faults → Cues |
|---|------|--------|-----------------|---------------|
| 1 | Lymphatic hops | front | Hip y-oscillation cadence (target 120-160/min), both feet leave together | Too slow → "Lighter and quicker" / Uneven → "Both feet together" |
| 2 | Body waves | side | Sequential forward movement: hips, then chest, then head (phase lag between hip x, shoulder x, nose x) | No sequence → "Roll it up from the hips" |
| 3 | Trunk twists | front | Projected shoulder width shrinks on rotation (target < 70% of baseline) while hip width stays > 90% of baseline | Hips turning → "Keep your hips facing me" / Shallow → "Turn further" |
| 4 | Arm swings (Shuai Shou Gong) | angle45 | Wrist oscillation, peak wrist height near shoulder height, elbow angle > 150° (relaxed straight), knee dip every ~5th swing | Arms too high → "Shoulder height, no higher" / Bent elbows → "Let the arms hang loose" / No bounce → "Soft knees, small bounce" |
| 5 | Dead arms | front | Shoulder elevation and drop (shoulder y vs neck), arms limp (elbow angle stays wide) | Tense → "Let them drop, heavy" |
| 6 | Golf swings | front | Wrists cross body midline side to side, peak above shoulder line, torso rotation present | Arms only → "Turn your chest with it" |
| 7 | Ballet squats | front | Knee angle at bottom (target 90-120°), knees tracking outward (knee x outside ankle x), torso upright (shoulder-hip line within 20° of vertical) | Knees caving → "Knees out over your toes" / Leaning → "Chest up" / Shallow → "A little lower" |
| 8 | Marches | front | Knee lift: knee y reaches hip y, alternating legs, opposite arm swing | Low knees → "Knees up to hip height" |
| 9 | Horse stance (hold) | front | Ankle spread > 1.5x shoulder width, knee angle 100-140°, torso vertical, hold time | Too high → "Sink lower" / Leaning → "Stack your spine" |

Form score per move = time-weighted % of frames with zero active faults, plus cadence/depth bonuses. Session score = average of move scores.

**Important:** these are flowing, loose movements, not precise lifts. Bias toward encouraging. A user doing it roughly right should land 70-85. Only flag a fault after it persists for 1.5+ seconds.

## Coach engine (the monk)

The monk is the product's personality. Calm, warm, a little dry. Never preachy, never fitness-bro.

- **Rate limit:** max one spoken cue per 6 seconds. Corrections outrank encouragement. Never repeat the same cue twice in a row; after the second time, switch to a different phrasing from the cue's variants list.
- **States:** `idle`, `demonstrating` (shows the move during transition), `encouraging`, `correcting` (gentle gesture toward the fault), `celebrating` (end of move with score > 80), `resting` (transition).
- **Line bank:** each cue in JSON has 3+ variants. Plus a general pool: openers ("The sun is up. So are you."), mid-move encouragement ("Good. Breathe."), streak lines ("Day 12. The river doesn't stop either.").
- When form is clean for 15+ seconds, the monk goes quiet and just nods. Silence is a reward.

## Screens

1. **Onboarding (3 screens + paywall):** meet the monk, pick goal (energy / stiffness / calm), camera permission with a plain explanation ("Your camera stays on your phone. Nothing is recorded or uploaded."), then paywall with free trial.
2. **Home:** streak flame/counter, today's routine, big Start button, monk idle animation.
3. **Session:** full-screen camera with optional skeleton overlay (toggle), monk in a corner, current move name, 60s ring timer, live form meter, next-move preview during transitions. Pause button.
4. **Results:** session score, per-move breakdown, streak update, "Share Day X" button.
5. **Share card:** 9:16 image. "Day X" big, session score, the monk in a celebrating pose, app name small. Optional: 3-second clip of the user's best moment with skeleton overlay (only if they opt in to recording for share).
6. **Settings:** voice on/off, skeleton overlay on/off, routine length (5 / 9 min), reminders.

## Monetization

- Free: one routine (Classic Morning), streak tracking.
- Pro ($4.99/wk or $29.99/yr, 3-day trial): all routines (De-puff, Desk Neck & Shoulders, 5-Minute Express, Tai Chi Walk audio mode), detailed form history, custom monk outfits.
- Hard paywall after onboarding with trial; soft paywall on locked routines.

## App Store constraints

No medical or weight-loss claims anywhere in the app or listing. No "lymphatic drainage," "detox," "burns belly fat." Use "energy," "mobility," "morning routine," "feel looser."

## Build milestones (do these in order, stop after each for review)

**M1: Camera + pose.** Front camera feed, Vision pose running, skeleton overlay drawn on screen, FPS counter, joint confidence debug view. Done when skeleton tracks smoothly on device.

**M2: One move end-to-end.** Arm swings only. Detector, rep counter, form score, 3 faults with spoken cues, rate-limited coach engine. Add a debug screen that prints live joint angles and active faults. Done when Matthew can do arm swings badly on purpose and get the right cue every time.

**M3: Calibration + session runner.** Calibration gate, 60s timer, 10s transitions with facing instructions, session state machine (ready → move → transition → ... → done).

**M4: Remaining 8 detectors.** One at a time, each with its own debug view. Thresholds from moves.json.

**M5: Monk.** Placeholder monk with all states wired to the coach engine. Line bank in JSON. Swap in Rive file when art is ready.

**M6: Persistence + streaks + results screen.**

**M7: Share card.**

**M8: Onboarding + paywall (RevenueCat).**

**M9: Polish.** Haptics on rep milestones, sounds, reminders, app icon.

## Testing

- Record short clips of each move done correctly and incorrectly. Build a test harness that runs saved `PoseFrame` sequences (export from the debug screen as JSON) through each detector and asserts the expected faults fire. Tune thresholds against these recordings, not vibes.
- Test with different body types, lighting, and distances. Test with baggy clothes (joint confidence drops).
- Performance budget: pose + detection under 20ms per frame on iPhone 12.

## Open questions for Matthew (don't block on these, use the default)

- App name final? (Default: Morning Monk)
- Monk art style? (Default: placeholder; target is a round, chunky 2D character, Duolingo-level simplicity)
- Voice: TTS or recorded actor? (Default: TTS in v1)

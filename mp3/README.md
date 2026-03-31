# Audio Repeater (Spotify Loop Studio) - App Context

## Overview
This is a Flutter-based mobile application designed to help users (such as musicians, transcribers, or language learners) isolate, loop, and save specific segments of local audio files. The app provides a precise scrubbing interface, an interactive waveform, and a library system to remember previously imported tracks and their saved segments.

## Key Features
1. **Audio Import**: Users can import local audio files (`mp3`, `wav`, `m4a`, `aac`, `ogg`, `flac`) using the device's native file picker.
2. **Interactive Waveform**: Generates a fast visual representation of the audio amplitudes. The waveform highlights the current loop region and allows users to tap to seek.
3. **A/B Looping**: 
   - Precise control over loop start and end boundaries using a dual-thumb range slider, dedicated "Set Start / Set End" buttons, or +/- 5s shifting.
   - Auto-looping functionality built on top of `just_audio` by listening to position streams and seeking back to the start when the end margin is reached.
4. **Segment Bookmarking**: Users can name and save their currently selected loop range as a segment. 
5. **Audio Library Manager**: Saves metadata (file paths, names, and associated segments) into local storage device data using JSON within `shared_preferences`.
6. **Dedicated Segment Player**: Tapping on a saved segment opens a modern, "Spotify-style" player screen (`SegmentPlayerScreen`) focused solely on playing that specific loop, featuring play/pause, skip controls, and loop toggles.

## Tech Stack & Dependencies
* **Framework**: Flutter / Dart
* **Audio Playback**: `just_audio` (handles core playback, position/duration streams, seeking)
* **File Management**: `file_picker` (for selecting local media files)
* **Persistence**: `shared_preferences` (for saving the library list, segments, and last-opened file)
* **Theming**: `google_fonts` (specifically using the Inter font for UI elements)

## Architecture & Core Models
Currently, the core logic is predominantly centralized in `lib/main.dart` to allow fast iteration.

### Data Models
* **`LoopBookmark`**: Represents a single saved loop. Stores a unique string `id`, `name`, `start` (Duration), and `end` (Duration).
* **`SavedAudioEntry`**: Represents an imported track. Stores the absolute `path`, a display `name`, and a list of `segments` (`LoopBookmark`s).

### Main UI Components
1. **`AudioLooperScreen` (Main Entry)**:
   - **Header**: Shows current track info, an `Import` button, and a hamburger menu to open the Audio Library panel.
   - **SegmentWaveform & Player Controls**: Displays the custom waveform, Range Slider, Timestamps, and primary playback manipulation buttons (Play/Pause, Loop toggle, segment shifting).
   - **List Section**: A scrollable list of `LoopBookmark` objects bound to the current track.
2. **`SegmentPlayerScreen`**: 
   - A dedicated "Now Playing" page styled dynamically from design files (e.g., `test.pen`).
   - Plays the isolated segment with a clean visual hierarchy, including an Album Art placeholder, track progress, and loop playback rules.
3. **`SegmentWaveform` (Custom Painter)**:
   - A custom-painted widget (`_WaveformPainter`) that reads sampled double values (0.0 to 1.0) and draws vertical bars, highlighting the bars that fall inside the `loopStart` and `loopEnd` percentages.

## Data Flow
- **Audio Loading**: When an audio file is picked, `_generateWaveformFromFile` reads and downsamples the byte data to generate a low-res array of 96 values for instant waveform rendering.
- **Progress Tracking**: `_positionSubscription` tracks the live playtime. When the position exceeds `_loopEnd` while looping is enabled, the app natively triggers a `seek` back to `_loopStart` to prevent playback stoppage.
- **Storage**: Any changes to names, saved loops, or newly imported files trigger `_upsertAudioEntry` which updates the in-memory array and serializes the state down to `SharedPreferences` instantly.

## UI/UX Design & User Experience

The application deeply mirrors the design language of popular music streaming apps (specifically Spotify), emphasizing a dark, moody environment with vibrant, high-contrast accent colors and touch-friendly controls.

### 1. Visual Language & Theming
- **Color Palette**: 
  - **Backgrounds**: Deep blacks and dark greys (`#121212`, `#0C0D10`, `#181818`), creating a cinematic feel and saving battery on OLED screens.
  - **Accent**: "Spotify Green" (`#1DB954` and `#1ED760`), used for active states, play buttons, the active loop timeframe, and progress bars.
  - **Text**: Bright whites (`#FFFFFF`, `#F7F7F7`) for primary text and muted greys (`#A8ADB5`, `#9FA4AB`) for secondary information (timestamps, subtitles).
- **Typography**: Uses the `Inter` font consistently for a clean, modern, and highly legible geometric sans-serif aesthetic.

### 2. Main Screen Flow (`AudioLooperScreen`)
The main screen is divided into two distinct zones to facilitate heavy interaction while ensuring navigation remains clear:
- **Upper Workspace (Scrollable Area)**:
  - **Sticky Header**: Shows track context alongside a distinct `Import` button and library toggle.
  - **Segment List**: A sleek, scrollable list acting as the focal point. Each segment card features inline "Delete" and "Modify"(rename) actions so users do not have to dive into deep menus to manage their workspaces.
- **Lower Control Deck (Fixed Bottom Bar)**:
  - **Visual Waveform**: Built into a rounded, gradient-backed card, it draws direct visual focus. The active loop boundary is heavily highlighted in green over the dark grey waveform, making the "A/B constraint" instantly readable.
  - **Precision Scrubbing**: Directly beneath the waveform is a dual-thumb range slider, allowing physical manipulation of the loop barriers seamlessly.
  - **Button Deck**: Organized spatially. Micro-adjustments (`-5s Segment`, `+5s Segment`) sit above core boundary markers (`Set Start`, `Set End`), which flank a massive, unmissable Play/Pause button.

### 3. Segment Playing Experience (`SegmentPlayerScreen`)
When a user taps a saved segment, they are launched into an immersive "Now Playing" page styled from a dedicated `.pen` file mockup. 
- **Focus**: The UI strips away the complex timeline editors and focuses solely on the isolated loop.
- **Components**:
  - **Album Art Placeholder**: A large, central gradient block reserving space for future cover art.
  - **Focused Progress Bar**: Instead of showing the entire track's timeline, the progress bar zeroes in *only* on the segment's length. The timer displays time elapsed *within* the loop, rather than the absolute track time.
  - **Media Controls**: A dedicated control strip with a heavily emphasized Play button, accompanied by 'Skip Back', 'Skip Forward', and a 'Loop' toggle to break or enforce the loop rule.

### 4. Interactive Details & Micro-Interactions
- **Haptic Feedback**: The app utilizes `HapticFeedback.selectionClick()` and `HapticFeedback.mediumImpact()` liberally to give physical weight to slider snaps, boundary-setting, and loop toggles. 
- **Seamless Recovery**: If an audio track completes naturally, the listener stream catches the `completed` state and instantly bounces the user back to the loop's start edge to provide unbroken playback.
- **Modals**: Naming tracks/segments opens a high-contrast dark alert dialog, and accessing the library slides up a stylized Bottom Sheet covering 72% of the screen, mimicking modern iOS/Android native sheet behaviors.
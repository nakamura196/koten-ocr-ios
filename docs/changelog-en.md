---
lang: en
home_url: /en.html
image: /assets/ogp/ogp-en.png
title: Changelog
eyebrow: KotenOCR
lead: What changed in each version. Newest first.
alternate: { title: 日本語, url: changelog.html, lang: ja }
nav:
  - { title: Home, url: en.html }
  - { title: GitHub, url: "https://github.com/nakamura196/koten-ocr-ios" }
footer: "Contact: nakamura.satoru@mail.u-tokyo.ac.jp"
---

> If automatic updates are off, update from the App Store's Updates list.
{: .point }

Dates are in Japan time. The latest version is 2.1 (1 November 2026).


### 2.1 (1 November 2026)

- Added Auto-correct on the crop screen: finds the page corners and straightens a page photographed at an angle; Undo restores the original
- Added a Confidence slider on the result screen: raising it hides the least certain lines (display only; the results themselves are kept)
- Line numbers on thin lines (such as side notes) are now legible, and overlapping numbers are moved apart
- Modern mode reads short lines such as headings with the short-line models, as NDLOCR-Lite does; box coordinates and the detection threshold now match NDLOCR-Lite
- Reading order: fragments of one column are now kept top to bottom
- Fixed rotating 16-bit grayscale images, and image orientation handling
- History is saved more reliably (files are written atomically)
- Update notices no longer block the app
- The translation API key is now stored on this device only (re-enter it after moving to a new device or restoring a backup)
- Added a privacy manifest and updated the privacy policy to describe what the app actually does

### 2.0.1 (30 October 2026)

- The first-run guide now mentions that you can also choose a photo, not only take one
- The rotate button on the crop screen now shows a "Rotate" label

### 2.0 (30 October 2026)

- Added "Try a sample page" on the home screen: three bundled pages (Taketori Monogatari and The Tale of Genji for Classical, an NDL document for Modern) that read straight away
- Line numbers on the result screen now sit outside the box (above vertical lines, left of horizontal ones) so they no longer hide the first characters; two-digit numbers no longer wrap
- Line numbers have a white rim and are slightly transparent, the selected one solid and on top; box lines follow the line thickness, and small numbers keep a clear gap from their box
- Fixed corners moved in four-corner crop sometimes snapping back when automatic page detection finished late
- Modern mode no longer drops one-line headings and figure captions; it now reads the same lines as NDL's NDLOCR-Lite
- Pages with more than 100 lines, such as newspapers, are now read in full (no cap, as in NDL's official OCR)
- The confirm screen remembers the mode you last chose; trying a sample does not change it
- Added a home (start) screen on launch with Take Photo, Choose from Photos, History and Settings, instead of opening straight into the camera
- Added a Home button on the camera screen
- Fixed translations sometimes being saved to the wrong history item
- Fixed manual text edits not being saved to history
- Fixed rotation being lost on Skip in the crop screen, and the crop box accelerating while dragged
- Camera: prevent double capture, show an error when capture fails, and show guidance with an Open Settings button when access is denied
- OCR errors now show a readable localized message with a Retake button
- Faster history list using small thumbnails; added delete confirmation
- Accessibility: history rows include date and first line, visible edit button for recognized text, label for the reset-zoom button
- Export file names now include date and time
- Added missing localized strings and localized permission descriptions
- Added Scan document on the camera screen (VisionKit): detects page edges and corrects perspective; remembers the last used capture mode
- Added a tilt guide on the camera (level indicator and a "hold parallel" hint), switchable in Settings
- Added a four-corner crop mode that corrects keystone distortion
- Automatic small-angle deskew (within ±10°) before line detection, reducing overlapping boxes and text leaking from adjacent lines on tilted pages
- Added "Auto-correct tilt" setting (on by default)
- Result, history and export now use the deskewed image that OCR actually ran on
- Classical mode now handles lines that lean by different amounts (pages shot at an angle): leaning lines are read from crops that follow the line, so neighbouring text no longer leaks in. Duplicate lines from detecting the same column twice, and lines that read only as "□□□□", are dropped
- New design: documents and recognized text use washi paper colours, Mincho type and vermilion (朱) accents; controls use Liquid Glass on iOS 26 and solid white / 朱 plates on iOS 16–25
- App icon recoloured to washi, ink and 朱, with dark and tinted variants
- Home shows up to three recent scans; tap one to open it
- While reading, a vermilion beam follows the progress and found lines appear in reading order; a seal stamp and haptic mark completion
- The first-run introduction replays a real recognition result (boxes and text) on a manuscript page; one-time hints on the shutter and the crop corner (can be shown again from Settings)
- Added an empty-history illustration, tips when no text is found, and a camera-unavailable screen
- After cropping, choose Classical or Modern and tap Read; Copy is a floating button with a short “Copied” toast
- Reduce Motion replaces movement with cross-fades; layouts adapt to Dynamic Type including accessibility sizes
- Added Edit Boxes on the result screen: select, move, resize, delete, add, split and merge line boxes, then Re-read only the changed boxes and re-run reading order; with Undo and Cancel, saved to history
- Fixed a crash when analysing the 2nd or later image: memory grew with every analysis (line detection ran on a different thread each time and each thread kept ~100 MB of scratch memory). Photos are now taken in at most 4096 px on the long side, and the previous page's images are released before a new capture

### 1.3.2 (24 March 2026)

- Reduced memory usage: lazy model loading (only selected mode at startup)
- Optimized DEIMDetector preprocessing (peak memory 63MB → 2.4MB)
- Limited parallel recognition to 4-batch (prevents memory spikes)
- Auto-release unused models on memory warning
- Added MetricKit crash diagnostics
- Additional crash fixes (IoU bounds check, division-by-zero guard, force unwrap removal)

### 1.3.1 (23 March 2026)

- Improved Modern OCR detection accuracy by adding NMS (IoU=0.2) to remove duplicate detections
- Filter to line_* classes only for OCR recognition (matching ndlocr-lite behavior)
- Aligned detection parameters with upstream (scoreThreshold=0.2, maxDetections=100)

### 1.3.0 (22 March 2026)

- Added NDLOCR-Lite (modern printed text OCR). Switch between Classical and Modern OCR modes
- Added DEIMv2 detector and cascade PARSeq recognizer (30/50/100 char models)
- One-tap OCR mode selection on confirm screen
- Back from result returns to confirm screen for easy model comparison
- Parallel recognition (1.4x for Classical, 6.7x for Modern)
- Added splash screen with app icon and tagline
- Added feedback email with device info
- Fixed crash risks (safe array access, removed force unwraps)

### 1.2.2 (19 March 2026)

- Updated App Store marketing screenshots (device frames, JA/EN)
- Added screenshot automation pipeline
- Fixed force unwraps in ReadingOrder, CameraView
- Added error logging to empty catch blocks
- Standardized localization to `String(localized:)` pattern

### 1.2.1 (14 March 2026)

- Added Tip Jar (in-app tips via StoreKit 2)

### 1.2.0 (13 March 2026)

- Added modern translation (local AI / cloud API)
- Added crop confirmation screen
- Added camera save option

### 1.1.0 (10 March 2026)

- Improved camera permission flow
- Added camera permission management to settings
- Added unit tests

### 1.0 (4 March 2026)

- Initial release
- Kuzushiji OCR using NDL Koten OCR-Lite models
- Camera capture and photo library OCR
- Text editing and export (TXT/PDF)
- Scan history
- Dark/Light theme
- Japanese/English support

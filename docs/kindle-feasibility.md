# Running Hearth Reader on a Kindle: feasibility study

*October 2026*

## Summary

"Kindle" covers two very different kinds of device:

| Device family | OS | Can Hearth run? | Effort |
|---|---|---|---|
| **Fire tablets** (Fire 7 / HD 8 / HD 10 / Max 11) | Fire OS, which is Android-based | **Yes.** Install the existing APK. | Very low |
| **E-ink Kindles** (Paperwhite, Oasis, Scribe, Colorsoft, Basic) | Amazon's own embedded Linux | **Not realistically.** | Very high, and it needs a jailbreak |

**Recommendation:** support Fire tablets now, since they already work. For e-ink
Kindles, don't port Flutter. If e-ink reading matters, use KOReader on a
jailbroken Kindle and, if needed later, sync progress between it and Hearth
(see [Option C](#option-c-sync-with-koreader-instead-of-porting)).

---

## 1. Fire tablets: works today

Fire OS 7 is based on Android 9 (API 28) and Fire OS 8 on Android 11 (API 30).
Our release APK has these properties:

- **Minimum Android version:** `minSdk 24` (Android 7.0, Flutter's default), so
  every Fire tablet sold in the last several years meets it.
- **Native libraries:** it ships `armeabi-v7a`, `arm64-v8a` and `x86_64`
  libraries, which covers both the 32-bit and 64-bit ARM chips Amazon uses.
- **Dependencies:** it relies on nothing from Google Play Services. The plugins
  are `pdfrx` (bundled PDFium), `sqflite`, `file_picker` and `path_provider`,
  and all of them work with plain Android APIs.

**How to install:**

1. On the tablet, go to *Settings → Security & Privacy → Apps from Unknown
   Sources* and allow your file manager or browser to install apps.
2. Copy `dist/hearth_reader.apk` to the tablet (USB, cloud drive, or e-mail),
   open it, and install.

**Things to check on a real device (untested so far):**

- **Importing books:** the file picker goes through Android's Storage Access
  Framework. Fire OS supports it, but its *Docs* app is the default provider.
  Check that importing from *Downloads* works.
- **Performance:** cheaper models (Fire 7, Fire HD 8) have weak GPUs. The fairy
  lights on the shelf animate continuously. Consider a "reduce motion" setting
  if scrolling the shelf stutters.
- **Amazon Appstore:** publishing there would need a release keystore. The APK
  is currently debug-signed, which is fine for sideloading only.

## 2. E-ink Kindles: why it isn't practical

### 2.1 The platform

- **Operating system:** a Linux kernel with a minimal userspace. Recent
  firmware moved to a hard-float `armhf` userspace; older firmware is
  soft-float `armel`.
- **User interface:** Amazon's own framework. Older firmware uses a Java
  "KPP/Booklet" layer; newer firmware draws on an X11 + GTK2-era stack with
  WebKit-based components.
- **Running your own code:** **impossible without a jailbreak.** Jailbreaks
  exist only for particular firmware windows, Amazon patches them, and using
  one may breach the device terms.

### 2.2 Blockers for Flutter

| Requirement | Kindle reality |
|---|---|
| **A supported Flutter target.** Linux desktop builds are x64 and arm64 only; embedded embedders such as flutter-pi and flutter-elinux mainly target arm64. | **32-bit ARM userspace.** We would have to cross-compile the Flutter engine for armhf ourselves, and the engine doesn't officially support that for Linux. |
| **A GTK3 desktop runner.** That is what `flutter build linux` produces. | **No GTK3.** We'd need a custom embedder that renders straight to the framebuffer. |
| **GPU rendering with OpenGL ES or Vulkan.** | **No GPU exposed to apps.** We'd need the embedder's software renderer, which is slow on the Kindle's low-power cores. |
| **A display that updates continuously at 60 fps.** | **E-ink.** The screen only redraws when told to, through the EPDC/`mxcfb` (i.MX) or MediaTek-specific `ioctl` calls. The embedder would have to work out what changed and choose full or partial refresh modes, or the screen ghosts and smears. |
| **Touch, keyboard and wheel input.** | Raw `evdev` touch events, which we'd have to read and translate ourselves. |
| **sqflite FFI against the system SQLite, and PDFium.** | Both would have to be cross-compiled and bundled for armhf. |

### 2.3 Product fit

Even if all of that worked, the app is designed for an LCD:

- **Animations:** the fairy lights, glowing progress strips and animated page
  transitions would make an e-ink panel refresh constantly, flicker and drain
  the battery.
- **Colours:** the dark "espresso" theme and smart-inverted PDFs are
  meaningless on a greyscale panel. Readers there want black on white.
- **Overlap with the built-in reader:** the Kindle already has a good EPUB
  reader, and KOReader handles PDFs better.

**Estimated effort:** many weeks of low-level work, including a custom
embedder, a cross-compiled engine and e-ink refresh handling, all for a
jailbroken-only audience. **Not recommended.**

## 3. Options

### Option A: Fire tablets only *(recommended, available now)*

Sideload the existing APK. Optionally:
- add a reduce-motion toggle;
- add a release keystore;
- publish on the Amazon Appstore.

### Option B: native port to e-ink *(not recommended)*

Build a custom Flutter embedder (software rendering, framebuffer, `evdev`
input, e-ink refresh `ioctl` calls) for armhf, plus an e-ink theme. It would
need a jailbreak, could break with any firmware update, and would take weeks.

### Option C: sync with KOReader instead of porting

KOReader runs on jailbroken e-ink Kindles, reads EPUB and PDF, and already has
reading statistics and progress sync. Hearth could:

1. read and write KOReader's `.sdr` sidecar files to swap reading position and
   highlights for each book; or
2. talk to a KOReader-compatible progress sync server, matching books by file
   hash. Hearth already stores a SHA-256 for each book, but KOReader uses a
   partial MD5, so we would have to compute that too.

That way you keep reading on e-ink, and Hearth stays the place for library,
notes and stats on your phone, tablet or desktop. The effort is moderate
(roughly days, not weeks), and the Kindle only needs KOReader, not our code.

### Option D: Send-to-Kindle

The simplest bridge: add a "Send to Kindle" action that e-mails the EPUB to the
user's `@kindle.com` address. It needs no jailbreak, but progress and notes
don't come back to Hearth.

## 4. Next steps

1. Install `dist/hearth_reader.apk` on a Fire tablet and run through the
   checks in §1.
2. If e-ink reading is important, prototype Option C by reading a KOReader
   `.sdr` file and mapping its position onto Hearth's `ReadingPosition`.

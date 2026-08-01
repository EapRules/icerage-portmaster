# Technical deep dive

**How a 2013 Android NativeActivity game runs natively on ARM Linux — no
emulator, no Android runtime.**

The reference device is the R36S, but nothing here is device-specific: the
techniques apply to any armhf-capable ARM Linux system with 32-bit GPU
libraries, and to the whole class of `android_native_app_glue` games whose
source is gone.

## The execution model

Ice Rage ships a single `armeabi-v7a` library built against Android's NDK.
Unlike JNI-driven engines, a NativeActivity game brings its own main loop: it
imports `libandroid.so`, expects an `ALooper`, an `AInputQueue` and an
`ANativeWindow`, and runs itself. The port maps the library with a
bionic-compatible ELF loader (gmloader-next lineage) and implements the
Android surface around it by hand: the activity lifecycle, the looper and
poll source, the input queue, EGL/GLES, OpenSL ES, and the handful of JNI
calls the engine makes back into "Java".

Every one of those pieces fails loudly rather than approximately: the loader
refuses to run with unresolved imports, and lifecycle ordering is enforced —
the window-creation command must be the *last* one the activity receives, or
the engine starts against a surface it is about to lose.

## Runtime symbol lookup: the trap static analysis cannot see

The game's PLT does not import `AMotionEvent_getAxisValue`, so reading the
import table says joystick axes are never used. False: the string sits next
to `dlsym` in the binary. The function arrived in API 9 — later than this
2013 build's minimum target — so the engine resolves it *at runtime* and
caches the pointer, calling it unchecked. A `dlsym` that misses returns
NULL, and the first stick movement jumps to `pc = 0`.

The lesson generalizes: for binaries of this era, the import table is only
the static half of the ABI surface. Everything the game ever passes to
`dlsym` is part of the contract too, and the loader's symbol tables must
answer it.

## Input archaeology: this build has no touch mode

This is the OUYA release — a console build for a device with no touchscreen.
The engine discards synthetic touch events at the source:

```text
[W/native-activity] WARNING: Unknown input source (4098)!
```

`4098` is `AINPUT_SOURCE_TOUCHSCREEN`. No amount of synthetic fingers can
select a menu item, which is why the port drives the game as a *controller*
— the input model this binary was written for.

The key handling needed disassembly-level care: the engine's handler is a
jump table over keycodes 19..107. Android's BACK (4) falls through to the
default case, and so would `BUTTON_START` (108), one past the end. Grepping
the disassembly for the keycode constant finds nothing — a jump table
compares nothing; it has to be read by index. Start therefore sends MENU
(82), which has a real entry.

## Audio: verify the claim, not the warning

The engine asks OpenSL ES for a player fed by a compressed stream, which
Android would decode in-platform and this port does not. An early release
concluded "music is silent" from that warning. Wrong: the game decodes its
own Ogg and reaches the speakers through the same PCM path the sound
effects use. The warning now states exactly what it observed and explicitly
disclaims being a statement about audible output — because a message about
an unused code path is not a fact about what the player hears, and the
difference only shows up on hardware.

## Logging on a device with no terminal

A reproducible segfault once produced a log with everything *except* the
FATAL block. Two independent causes, both in the port's own plumbing:

- the launcher piped output through `tee`, and PortMaster's exit path kills
  every process before the pipe's buffer flushes — writing straight to the
  file removes the second process entirely;
- unbuffering was delegated to `stdbuf`, which works by `LD_PRELOAD`ing
  `libstdbuf.so`; on the device that library is 64-bit and the port is
  32-bit, so it was silently rejected on every single run
  (`wrong ELF class: ELFCLASS64`). `setvbuf` in `main()` does the same job
  with no external dependency.

Screenshots follow the same privilege logic: PortMaster's own tool uses
ffmpeg's `kmsgrab`, which wants `CAP_SYS_ADMIN` a port launcher does not
have. Reading `/dev/fb0` needs no privileges, so the port carries its own
`grab_screen.sh`.

## Shipping discipline

- The release zip contains no game content; the user supplies the exact APK
  (`net.mountainsheep.icerage` 1.8, OUYA build — the Play build is
  touch-only and unportable by design, see above).
- The game's own 1920x1080 splash is letterboxed on a 4:3 panel, so the
  loading screen is replaced through an asset-override mechanism rather
  than by touching the APK.
- Bundled ARM libraries are collected by an allowlist: glibc, the dynamic
  linker and anything GPU-related must come from the device, never from the
  zip.
- A qemu-arm + llvmpipe harness reports which startup milestone the binary
  reaches without touching an SD card — with the explicit caveat that it
  has no joystick, no Mali and no KMSDRM, and hardware remains the arbiter.

None of this is specific to ice hockey. The loader, the hand-built Android
surface, the runtime-dlsym rule, the controller-first input mapping and the
fail-loud packaging form a repeatable path for the rest of this generation
of Android-native games.

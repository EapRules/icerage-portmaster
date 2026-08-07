#!/bin/bash
#
# Ice Rage — PortMaster launcher.
#
# Modelled on ports/half-life/Half-Life.sh from PortMaster-New: same
# controlfolder probe, same control.txt / tasksetter / device_info.txt
# sourcing, same $GPTOKEYB + $TASKSET invocation, same "/$directory/ports"
# base. The differences are all forced by what this port is:
#
#   * armhf only. The game ships one native library, armeabi-v7a, and the
#     bionic ELF loader has to map it into a process of the same word size,
#     so there is no $DEVICE_ARCH switch here — the binary is always armhf.
#   * The game data is the user's own APK. It is never bundled with the port
#     and it is passed to the loader as argv[1].
#   * ICERAGE_DATA_DIR is where the engine writes its savegames. On Android
#     that is /data/data/<pkg>/files and it always exists before onCreate;
#     here it has to be created, because the engine treats a failed open of
#     its save directory as fatal rather than as "no save yet".

# control.txt and the files it pulls in live on the device, not in this repo,
# so shellcheck can neither follow them (SC1090/SC1091) nor see that they are
# what define $directory, $sdl_controllerconfig, $ESUDO, $GPTOKEYB and
# $TASKSET (SC2154). Every other class of finding stays on.
# shellcheck disable=SC1090,SC1091,SC2154

XDG_DATA_HOME=${XDG_DATA_HOME:-$HOME/.local/share}

if [ -d "/opt/system/Tools/PortMaster/" ]; then
  controlfolder="/opt/system/Tools/PortMaster"
elif [ -d "/opt/tools/PortMaster/" ]; then
  controlfolder="/opt/tools/PortMaster"
elif [ -d "$XDG_DATA_HOME/PortMaster/" ]; then
  controlfolder="$XDG_DATA_HOME/PortMaster"
else
  controlfolder="/roms/ports/PortMaster"
fi

source "$controlfolder/control.txt"

# The game ships one native library, armeabi-v7a, so this port is 32-bit and
# there is no aarch64 build to fall back to. The CFW mod files below read this
# flag to set up a 32-bit environment, so it has to be exported before them.
export PORT_32BIT="Y"

# Half-Life.sh sources these three unconditionally. They only exist on newer
# PortMaster installs, and an old one is a plausible thing to meet in the
# wild, so ask first: a missing tasksetter must not take the port down with
# "No such file or directory" before it has printed anything.
[ -f "$controlfolder/tasksetter" ]          && source "$controlfolder/tasksetter"
[ -f "$controlfolder/device_info.txt" ]     && source "$controlfolder/device_info.txt"
[ -f "$controlfolder/mod_${CFW_NAME}.txt" ] && source "$controlfolder/mod_${CFW_NAME}.txt"

get_controls

GAMEDIR="/$directory/ports/icerage"
cd "$GAMEDIR" || exit 1

# Everything from here on lands in log.txt, which is the only diagnostic
# anyone gets off the console.
#
# Written straight to the file rather than through `tee`. A pipe adds a second
# process with its own buffer, and on a crash PortMaster's exit path pkills
# everything before that buffer is flushed - so the log ends mid-sentence and
# loses exactly the part naming the fault. That happened here: a reproducible
# segfault produced a log with no FATAL block in it at all.
#
# The handheld has no visible terminal, so nothing is lost by not echoing.
: > "$GAMEDIR/log.txt"
exec > "$GAMEDIR/log.txt" 2>&1

# Put the cover where the frontend looks for it.
#
# PortMaster is supposed to merge our gameinfo.xml into ports/gamelist.xml when
# it installs, and on some versions it does. That merge is skipped, silently and
# without a log line, whenever harbourmaster does not recognise the OS name -
# any fork or re-release lands on PlatformBase, whose gamelist_file() returns
# None, and gamelist_backup() then yields None and returns. Nothing fails, no
# port is broken, the artwork simply never arrives. Since it is the frontend's
# own convention that every other title on the card relies on
# (ports/images/<the launcher's name>.png), the port can satisfy it itself
# rather than depend on which PortMaster the user happens to run.
#
# Copy only, once, and never overwrite: a user who put their own artwork there
# chose it on purpose.
_ir_img_dir="/$directory/ports/images"
if [ -f "$GAMEDIR/cover.png" ] && [ ! -e "$_ir_img_dir/Ice Rage.png" ]; then
  mkdir -p "$_ir_img_dir" 2>/dev/null
  cp "$GAMEDIR/cover.png" "$_ir_img_dir/Ice Rage.png" 2>/dev/null \
    && echo "Artwork installed to ports/images/Ice Rage.png"
fi

# ...and point the frontend's own index at it.
#
# Dropping the file in images/ is only half of it: EmulationStation reads
# ports/gamelist.xml. Deliberately conservative: never touch a gamelist that
# does not exist (muOS, TrimUI and RetroDECK do not use one), never overwrite an
# <image> the user already has, back up before writing, and only install the
# result if it still parses as the same document plus our line.
_ir_gamelist="/$directory/ports/gamelist.xml"
if [ -e "$_ir_img_dir/Ice Rage.png" ] && [ -s "$_ir_gamelist" ]; then
  _ir_tmp="$GAMEDIR/.gamelist.$$"
  if awk -v P="./Ice Rage.sh" -v IMG="./images/Ice Rage.png" \
         -v NAME="Ice Rage" '
      { L[++n] = $0 }
      END {
        s = 0; found = 0; hasimg = 0; ins = 0; pad = "\t\t"
        for (i = 1; i <= n; i++) {
          if (L[i] ~ /<game>/) { s = i }
          if (L[i] ~ /<\/game>/ && s > 0) {
            hit = 0; img = 0; pl = 0
            for (j = s; j <= i; j++) {
              if (index(L[j], "<path>" P "</path>") > 0) { hit = 1; pl = j }
              if (L[j] ~ /<image>/) { img = 1 }
            }
            if (hit == 1) { found = 1; hasimg = img; ins = pl }
            s = 0
          }
        }
        if (found == 1 && hasimg == 1) { exit 1 }
        if (found == 1) {
          match(L[ins], /^[ \t]*/)
          pad = substr(L[ins], 1, RLENGTH)
          for (i = 1; i <= n; i++) {
            print L[i]
            if (i == ins) { print pad "<image>" IMG "</image>" }
          }
          exit 0
        }
        done = 0
        for (i = 1; i <= n; i++) {
          if (L[i] ~ /<\/gameList>/ && done == 0) {
            print "\t<game>"
            print "\t\t<path>" P "</path>"
            print "\t\t<name>" NAME "</name>"
            print "\t\t<image>" IMG "</image>"
            print "\t</game>"
            done = 1
          }
          print L[i]
        }
        if (done == 0) { exit 1 }
        exit 0
      }' "$_ir_gamelist" > "$_ir_tmp" 2>/dev/null; then
    # Only swap it in if the result is a sane, complete document.
    if [ -s "$_ir_tmp" ] \
       && grep -q "</gameList>" "$_ir_tmp" \
       && grep -q "images/Ice Rage.png" "$_ir_tmp"; then
      cp "$_ir_gamelist" "$_ir_gamelist.bak" 2>/dev/null
      if cp "$_ir_tmp" "$_ir_gamelist" 2>/dev/null; then
        echo "Artwork registered in ports/gamelist.xml"
      fi
    fi
  fi
  rm -f "$_ir_tmp" 2>/dev/null
fi
unset _ir_img_dir _ir_gamelist _ir_tmp

export LD_LIBRARY_PATH="$GAMEDIR/libs.armhf:$LD_LIBRARY_PATH"
export SDL_GAMECONTROLLERCONFIG="$sdl_controllerconfig"

# Fire goes on the button the player reads as "A". Which SDL button that is
# depends on the silkscreen, not on SDL: these handhelds are lettered Nintendo
# style, with A on the right, and that is the default. A device lettered Xbox
# style, with A at the bottom, wants "xbox" here.
export ICERAGE_FACE_LAYOUT="${ICERAGE_FACE_LAYOUT:-nintendo}"

# How the game is fitted to this screen.
#
# The engine reads its resolution from the EGL surface and lays itself out for
# whatever it is given - measured under the harness at 1280x720, where it
# issued a full-screen 1280x720 viewport of its own accord and painted the
# whole panel. So the port opens the window at the device's real size and
# leaves the engine alone, which is what "native" means here and why it is the
# default on every device, 4:3 or not.
#
# "scaled" is the break-glass alternative: render at the original 640x480 and
# letterbox that onto the panel (ICERAGE_SCALE = fit / stretch / integer). It
# exists for a screen where the engine's own layout turns out wrong, which no
# device available to this port has shown.
#
# ICERAGE_PANEL_W/H force a panel size on a firmware that reports the wrong
# one; unset, SDL's desktop mode decides.
export ICERAGE_RENDER="${ICERAGE_RENDER:-native}"
export ICERAGE_SCALE="${ICERAGE_SCALE:-fit}"

# Audio routing is decided by what the device actually runs, never by CFW name -
# the same principle as the display above: detect the capability, adapt to it.
# If a user audio server is present (PipeWire, or a PulseAudio socket), the
# 32-bit game must route through it or it grabs a PCM nobody is listening to and
# plays silence. If none is found, fall back to ALSA dmix: ALSA hands out one
# exclusive handle and EmulationStation's menu music is likely holding it, which
# is why the first device build had no sound at all, and dmix mixes in software
# so several processes can share the card. No device or firmware is named.
_ir_pw=""
for _pw in /usr/lib32/pipewire-0.3 /usr/lib/arm-linux-gnueabihf/pipewire-0.3; do
  [ -d "$_pw" ] && { _ir_pw="$_pw"; break; }
done
for _xrd in "${XDG_RUNTIME_DIR:-}" /run/user/0 /var/run/user/0; do
  [ -n "$_xrd" ] && [ -d "$_xrd" ] && { export XDG_RUNTIME_DIR="$_xrd"; break; }
done
_ir_pulse=""
for _pulse in "${XDG_RUNTIME_DIR:-}/pulse/native" /run/pulse/native /var/run/pulse/native; do
  [ -n "$_pulse" ] && [ -S "$_pulse" ] && { _ir_pulse="$_pulse"; break; }
done
if [ -n "$_ir_pw" ] || [ -n "$_ir_pulse" ]; then
  unset AUDIODEV ALSA_CONFIG_PATH SDL_AUDIO_DEVICE_NAME ALSA_CARD
  export SDL_AUDIODRIVER=alsa
  export ALSOFT_DRIVERS=alsa
  export SDL_AUDIO_ALSA_SET_BUFFER_SIZE=1
  for _spa in /usr/lib32/spa-0.2 /usr/lib/arm-linux-gnueabihf/spa-0.2; do
    [ -d "$_spa" ] && { export SPA_PLUGIN_DIR="$_spa"; break; }
  done
  [ -n "$_ir_pw" ] && export PIPEWIRE_MODULE_DIR="$_ir_pw"
  if [ -n "$_ir_pulse" ]; then
    export PULSE_SERVER="unix:$_ir_pulse"
  else
    unset PULSE_SERVER
  fi
  echo "Audio: routing through the device's audio server (PipeWire/Pulse), dmix bypassed"
else
  export AUDIODEV="${AUDIODEV:-plug:dmix}"
  export SDL_AUDIODRIVER="${SDL_AUDIODRIVER:-alsa}"
  echo "Audio: ALSA dmix (no audio server detected)"
fi
unset _ir_pw _ir_pulse _pw _pulse _xrd _spa

CUR_TTY=/dev/tty0
[ -w "$CUR_TTY" ] || CUR_TTY=/dev/tty1

# The user's own APK. Without it there is nothing to run, and a handheld shows
# no terminal, so this has to reach the screen: a silent exit back to the menu
# is indistinguishable from a crash.
if [ ! -f "$GAMEDIR/icerage.apk" ]; then
  $ESUDO chmod 666 "$CUR_TTY" 2>/dev/null
  printf "\033c" > "$CUR_TTY"
  {
    echo ""
    echo "  Ice Rage - missing game file"
    echo ""
    echo "  Put your own copy of the game here:"
    echo "    $GAMEDIR/icerage.apk"
    echo ""
    echo "  It is the Android APK, package"
    echo "  net.mountainsheep.icerage"
    echo ""
    echo "  See README.md in the port folder."
    echo ""
  } > "$CUR_TTY"
  sleep 10
  printf "\033c" > "$CUR_TTY"
  pm_finish
  exit 1
fi

# Say something useful about the wrong APK, because the alternative is awful.
#
# The loader binds to symbols in this exact build of libicerage.so. Hand it a
# repacked "MOD" APK, an XAPK renamed to .apk, or a split install, and it dies
# somewhere deep with a stack trace nobody can act on - the port looks broken
# when the file was.
#
# So two questions get asked here, cheaply, before anything else runs:
# does the native library exist at all, and does the manifest still carry the
# version this port was built against? The first is fatal; the second is only a
# warning, because a future repack might still work and refusing to start would
# be worse than letting someone try.
#
# unzip is not guaranteed on every CFW. If it is missing, both checks are
# skipped in silence rather than blocking a launch that would have worked.
show_screen() {
  $ESUDO chmod 666 "$CUR_TTY" 2>/dev/null
  printf "\033c" > "$CUR_TTY"
  cat > "$CUR_TTY"
  sleep "${1:-10}"
  printf "\033c" > "$CUR_TTY"
}

if command -v unzip >/dev/null 2>&1; then
  if ! unzip -l "$GAMEDIR/icerage.apk" 2>/dev/null | grep -q "lib/armeabi-v7a/libicerage.so"; then
    echo "APK check: lib/armeabi-v7a/libicerage.so is not in the APK"
    show_screen 12 <<EOF

  Ice Rage - wrong game file

  That APK has no armeabi-v7a library
  inside, so there is nothing to run.

  Common causes:
    - it is an XAPK or APKM renamed
      to .apk (those are archives that
      hold the real APK inside)
    - it is a split install, arm64 only

  You need the plain single APK of
  net.mountainsheep.icerage

EOF
    pm_finish
    exit 1
  fi

  # AndroidManifest.xml is binary XML holding its strings as UTF-16, so the
  # version reads as "1.8" only once the padding bytes are gone. Reducing it
  # to printable characters does that and, just as importantly, stops grep from
  # treating the stream as binary - a binary match with -q reports nothing found
  # and the check would reject every APK, including the right one.
  if ! unzip -p "$GAMEDIR/icerage.apk" AndroidManifest.xml 2>/dev/null \
       | LC_ALL=C tr -cd '[:print:]\n' | LC_ALL=C grep -q "net\.mountainsheep\.icerage"; then
    echo "APK check: this does not look like net.mountainsheep.icerage - continuing anyway"
    show_screen 8 <<EOF

  Ice Rage - unexpected APK

  This port was built against the OUYA
  release of net.mountainsheep.icerage
  (v1.8, October 2013), and your file
  does not look like it.

  Other builds may still work, but the
  Play version is touch-only and this
  port drives the game as a controller.

  Starting anyway - if it crashes or
  the menus do not respond, this is the
  first thing to suspect.

EOF
  else
    echo "APK check: net.mountainsheep.icerage, native library present"
  fi
fi

# SDL must create its context through the device's own 32-bit GL stack.
#
# On the tested hardware libEGL.so.1 resolves through glvnd to Mesa while
# libGLESv2.so.2 is the Mali blob. Mixing the two yields a context that looks
# valid and then reports null for every GL string, so the game renders nothing.
# The fix is to decide the whole stack here and put it first on the path.
#
# Which stack that is depends on the device, not on the firmware's name, so it
# is found by capability:
#
#   1. A unified Mali blob - one .so exporting EGL and GLESv2. Try the exact
#      tested filenames first (fast, known-good), then any Mali build in the
#      32-bit library directories, because every distribution names it
#      differently: versioned upstream names on Debian-style CFWs
#      (libmali-bifrost-g31-*.so), an unversioned libmali.so.1 on Buildroot
#      ones, libMali.so where a firmware symlinks it. The blob is then linked
#      to every name the game asks for.
#   2. No blob, but a real 32-bit EGL/GLES set - a Mesa/glvnd userland, which
#      is what a Panfrost-only device ships. Each entry point is linked under
#      its own name, taken from the one directory that provides libEGL, since a
#      set assembled from two userlands would not be one working stack.
#   3. Neither. Say so on screen instead of leaving the user with a black
#      panel: without a 32-bit provider SDL either falls back to something that
#      never reaches the framebuffer, or fails to create a window at all.
#
# Directories are architecture-scoped, so a 64-bit library can never be picked:
# the multiarch triplet dir and lib32 are 32-bit by definition, and the bare
# /usr/lib and /lib are only consulted on a pure-armhf rootfs.
#
# The shim has to be built at runtime under /tmp: the SD card is exFAT, which
# has no symlinks, so one shipped inside the port would arrive as broken files.
GL_DIRS="/usr/lib/arm-linux-gnueabihf /usr/lib/arm-linux-gnueabihf/mali \
/lib/arm-linux-gnueabihf /usr/lib32/mali /usr/lib32"
if [ "${DEVICE_ARCH:-}" = "armhf" ]; then
  GL_DIRS="$GL_DIRS /usr/lib /lib"
fi

MALI_BLOB=""
for candidate in \
    /usr/lib/arm-linux-gnueabihf/libmali-bifrost-g31-rxp0-gbm.so \
    /usr/lib/arm-linux-gnueabihf/libMali.so \
    /usr/lib/arm-linux-gnueabihf/libmali.so.1; do
  [ -e "$candidate" ] && { MALI_BLOB="$candidate"; break; }
done
if [ -z "$MALI_BLOB" ]; then
  for _gldir in $GL_DIRS; do
    [ -d "$_gldir" ] || continue
    for _cand in "$_gldir"/libmali-*.so "$_gldir"/libmali.so.* \
                 "$_gldir"/libmali.so "$_gldir"/libMali.so*; do
      [ -e "$_cand" ] && { MALI_BLOB="$_cand"; break; }
    done
    [ -n "$MALI_BLOB" ] && break
  done
fi

GL_SHIM="/tmp/icerage-gl"
rm -rf "$GL_SHIM"
GL_READY=""
if [ -n "$MALI_BLOB" ]; then
  if mkdir -p "$GL_SHIM" \
     && ln -sf "$MALI_BLOB" "$GL_SHIM/libEGL.so.1" \
     && ln -sf "$MALI_BLOB" "$GL_SHIM/libGLESv2.so.2" \
     && ln -sf "$MALI_BLOB" "$GL_SHIM/libmali.so.1"; then
    GL_READY="y"
    echo "GL: using Mali blob $MALI_BLOB"
  else
    echo "GL: failed to create $GL_SHIM, using system libraries"
  fi
else
  GL_EGL=""
  mkdir -p "$GL_SHIM" 2>/dev/null
  for _gldir in $GL_DIRS; do
    [ -e "$_gldir/libEGL.so.1" ] || continue
    for _soname in libEGL.so.1 libGLESv2.so.2; do
      [ -e "$_gldir/$_soname" ] && ln -sf "$_gldir/$_soname" "$GL_SHIM/$_soname"
    done
    [ -e "$GL_SHIM/libEGL.so.1" ] && { GL_EGL="$_gldir/libEGL.so.1"; break; }
  done
  if [ -n "$GL_EGL" ]; then
    GL_READY="y"
    echo "GL: no Mali blob; using the device's 32-bit EGL/GLES set ($GL_EGL)"
  fi
fi

if [ -n "$GL_READY" ]; then
  export LD_LIBRARY_PATH="$GL_SHIM:$LD_LIBRARY_PATH"
else
  rm -rf "$GL_SHIM"
  echo "GL: no 32-bit GL provider found; searched: $GL_DIRS"
  show_screen 12 <<EOF

  Ice Rage - no 32-bit GPU driver

  This firmware ships no 32-bit Mali
  blob and no 32-bit EGL/GLES set, so
  the game cannot open a window.

  The screen will stay black or the
  game will exit. See log.txt.

EOF
fi

# The engine's writable storage. Kept inside the port directory so the port
# stays self-contained and uninstalls cleanly.
export ICERAGE_DATA_DIR="$GAMEDIR/gamedata"

# Drop a file in here to replace the APK asset of the same name. The game's own
# splash is 1920x1080 and this panel is 640x480, so splash.jpg is the one worth
# replacing: a 4:3 image fills the screen instead of sitting letterboxed. The
# port ships a 1440x1080 one.
export ICERAGE_ASSET_OVERRIDE="$GAMEDIR/assets"
mkdir -p "$ICERAGE_ASSET_OVERRIDE"
mkdir -p "$ICERAGE_DATA_DIR"

# The zip may arrive off a filesystem with no permission bits.
$ESUDO chmod +x "$GAMEDIR/icerage"

# gptokeyb is here for one thing only: so the standard PortMaster exit
# combination can terminate the game by name. Every button is deliberately
# left unbound in icerage.gptk, because this port reads the pad itself
# through SDL_GameController (android/platform.cpp) and translating the same
# physical presses into keystrokes as well would double every input.
$GPTOKEYB "icerage" -c "$GAMEDIR/icerage.gptk" &

# Whatever the CFW needs done between gptokeyb starting and the game running.
# Older PortMaster installs do not define it, so it is called only if present.
if command -v pm_platform_helper >/dev/null 2>&1; then
  pm_platform_helper "$GAMEDIR/icerage"
fi

# A crash was taking the log with it: tee buffers, and a segfault discards
# whatever has not been flushed - exactly the part naming the fault. stdbuf
# fixes that, but it is coreutils and this firmware may not carry it, so it is
# used only if present. Never let a debugging aid decide whether the game
# starts.
#
# Present is not the same as usable. stdbuf works by LD_PRELOADing
# libstdbuf.so, and on this device that library is 64-bit while the port is
# 32-bit, so the loader rejects it on every command it wraps:
#
#   ERROR: ld.so: object '/usr/libexec/coreutils/libstdbuf.so' from LD_PRELOAD
#   cannot be preloaded (wrong ELF class: ELFCLASS64): ignored.
#
# It says "ignored" and the command still runs, so nothing breaks - but the
# buffering stays unfixed and the message lands at the top of the log looking
# like a real fault. Running stdbuf once and checking whether it complains is
# cheaper and more portable than reading the ELF class ourselves.
USE_STDBUF=""
if command -v stdbuf >/dev/null 2>&1; then
  if [ -z "$(stdbuf -o0 true 2>&1)" ]; then
    USE_STDBUF="stdbuf -o0 -e0"
  else
    echo "stdbuf: present but not usable from a 32-bit process, skipping it"
  fi
fi

$USE_STDBUF $TASKSET "$GAMEDIR/icerage" "$GAMEDIR/icerage.apk"

$ESUDO kill -9 "$(pidof gptokeyb)" 2>/dev/null
rm -rf /tmp/icerage-gl
unset LD_LIBRARY_PATH SDL_GAMECONTROLLERCONFIG ICERAGE_DATA_DIR

pm_finish

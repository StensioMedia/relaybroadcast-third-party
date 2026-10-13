# relaybroadcast-third-party

Source code and build scripts for the third-party components shipped with
RelayBroadcast (FFmpeg, x264, SRT, GStreamer and others).

## What is here

- `scripts/win-ffmpeg/` builds the `ffmpeg.exe` and `ffprobe.exe` that ship with
  RelayBroadcast for Windows: a narrow build under the GPL, version 2 or later.
  See `scripts/win-ffmpeg/README.md`.
- `.github/workflows/build-ffmpeg-windows.yml` runs that build on GitHub Actions.
  It is started by hand.

## Releases

There is one release per RelayBroadcast version, tagged `v<version>`. Each
release holds the binaries, the complete corresponding source code, the build
scripts, the licenses and SHA-256 checksums for that version.

Releases are never deleted, and files in them are never replaced. A release is
only ever added to.

RelayBroadcast's `LICENSES/SOURCE-OFFER.md` points here.

# FFmpeg for RelayBroadcast on Windows

This folder builds the `ffmpeg.exe` and `ffprobe.exe` that ship with
RelayBroadcast for Windows (x86_64). It is meant for the public repository
`StensioMedia/relaybroadcast-third-party`, which publishes the exact source code
and build scripts for every RelayBroadcast release.

It is a narrow build: only what RelayBroadcast uses, licensed as GPL version 2
or later, the same as the macOS build.

## What is built

| Component | Version | License | How it is pinned |
|---|---|---|---|
| FFmpeg | 9.0.2 | GPL version 2 or later (built with `--enable-gpl`) | SHA-256 and the FFmpeg release signature |
| x264 | commit `b35605a…` (branch `stable`) | GPL version 2 or later | git commit |
| SRT | 1.5.7 | Mozilla Public License 2.0 | git commit |
| Mbed TLS | 3.6.7 (LTS) | Apache-2.0 OR GPL-2.0-or-later; used under GPL-2.0-or-later | SHA-256 |
| nv-codec-headers | 13.1.15.1 (commit `eddcea9…`) | MIT | git commit |
| AMF headers | 1.5.2 (commit `6277e35…`) | MIT | git commit |
| libvpl | 2.17.0 (commit `674d015…`) | MIT | git commit |
| dav1d | 1.5.4 (commit `9711965…`) | BSD-2-Clause | git commit |
| opus | commit `503d81b…` | BSD-3-Clause | git commit |
| zlib | 1.3.2.1 (commit `767c4c9…`) | Zlib | git commit |
| libxml2 | 2.16.0 (commit `91586dc…`) | MIT | git commit |
| mingw-w64 | the version in Ubuntu 24.04 (see `TOOLCHAIN.txt`) | ZPL-2.1, MIT, public domain | its source is included |

Exact versions and checksums: `versions.env`. Never built with
`--enable-nonfree` or `--enable-version3` (`--enable-mbedtls` needs version3, so
Mbed TLS only comes in through SRT).

The binaries are linked statically and depend only on Windows' own DLLs. The
build checks this with `objdump -p`. `check.ps1` then runs on Windows and checks
the license line, every encoder, decoder, filter, device, hardware acceleration,
protocol and format RelayBroadcast uses, and SRT with a passphrase end to end.

## How to run

- **GitHub Actions:** `.github/workflows/build-ffmpeg-windows.yml` (the copy here
  is `build-ffmpeg-windows.yml`). Run it by hand.
  - Job 1 (Ubuntu 24.04) cross-compiles with mingw-w64.
  - Job 2 (Windows Server 2025) runs `check.ps1`.
  - Job 3 runs only when *publish_release* is ticked. It adds
    `windows-ffmpeg-<version>.zip`, `windows-ffmpeg-source-<version>.tar` and
    `windows-SHA256SUMS` to the release `v<app version>`, and creates the
    release if it does not exist yet.
- **On Ubuntu 24.04:** install `mingw-w64 clang lld nasm cmake meson
  ninja-build pkg-config gnupg`, then run `./build.sh`. The result is in `ut/`.
  To check it on Windows, run `check.ps1 -Mapp <folder>`.

## Source code offer

Each release of this repository contains the complete source code for the
binaries it holds, and the scripts used to build them. Releases are never
deleted, and files in them are never replaced. RelayBroadcast's
`LICENSES/SOURCE-OFFER.md` points here.

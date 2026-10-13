#!/usr/bin/env bash
# ===========================================================================
# WINDOWS-APPENS FFMPEG (2026-10-13, licensbyggplanen uppgift 3)
# ---------------------------------------------------------------------------
# Korskompilerar ffmpeg.exe och ffprobe.exe för Windows x86_64 på Linux med
# mingw-w64: GPL version 2 eller senare, med bara det appen använder —
# x264, SRT (kryptering via Mbed TLS), NVIDIA (nvenc/nvdec/cuvid/cuda),
# Intel (libvpl/qsv), AMD (amf), Media Foundation, d3d11va/dxva2, schannel,
# opus, dav1d, zlib och libxml2. I stället för BtbN:s ~85 bibliotek
# (docs/research/svar-licenstexter-2-0-0-2026-10-11.md §B3, Anders beslut
# 2026-10-13). Förlaga: scripts/mac-ffmpeg/build.sh.
#
#   ALDRIG --enable-nonfree. ALDRIG --enable-version3.
#   (--enable-mbedtls kräver version3; Mbed TLS kommer bara in via SRT.)
#
# Körs av GitHub Actions (build-ffmpeg-windows.yml) på ubuntu-24.04, eller för
# hand på en Ubuntu 24.04 med paketen i README.md:
#
#   ./build.sh            → ut/ med binärerna, källkoden, licenserna och CONFIGURE.txt
#
# Allt hämtas med låst version och kontrolleras (versions.env); en avvikelse
# stoppar bygget. Binärerna länkas statiskt — inget beroende utom Windows egna
# DLL:er, och det kontrolleras med objdump efteråt. Kontrollerna som kräver
# Windows (kodare, filter, SRT på riktigt) gör check.ps1 i nästa jobb.
# ===========================================================================
set -euo pipefail

ROT="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=versions.env
source "$ROT/versions.env"

ARB="$ROT/arbete"        # källkod och byggen
P="$ARB/prefix"          # där biblioteken installeras
UT="$ROT/ut"             # det som laddas upp
rm -rf "$ARB" "$UT"
mkdir -p "$ARB/src" "$P" "$UT/source" "$UT/licenses"

VARD=x86_64-w64-mingw32
# Trådmodellen posix: SRT använder std::thread. Allt byggs med samma kompilator.
CC_X="$VARD-gcc-posix"
CXX_X="$VARD-g++-posix"
export PKG_CONFIG_PATH="$P/lib/pkgconfig"
export PKG_CONFIG_LIBDIR="$P/lib/pkgconfig"   # inga Linux-bibliotek via pkg-config
JOBB="$(nproc)"

steg() { printf '\n=== %s ===\n' "$*"; }
fel() { printf 'FEL: %s\n' "$*" >&2; exit 1; }

[ "$(uname -s)" = "Linux" ] || fel "bygget görs på Linux (mingw-w64)"
command -v "$CC_X" >/dev/null || fel "$CC_X saknas (paketet mingw-w64)"
command -v "$CXX_X" >/dev/null || fel "$CXX_X saknas (paketet mingw-w64)"

kontrollsumma() {   # fil, förväntad SHA-256
  local fick
  fick="$(sha256sum "$1" | awk '{print $1}')"
  [ "$fick" = "$2" ] || fel "$1: SHA-256 $fick, väntade $2"
  echo "ok  $1 SHA-256"
}

git_vid_commit() {   # adress, commit, mapp
  git init -q "$3"
  git -C "$3" remote add origin "$1"
  # De flesta servrar lämnar ut en commit direkt; annars hela historiken.
  if git -C "$3" fetch -q --depth 1 origin "$2" 2>/dev/null; then
    git -C "$3" checkout -q FETCH_HEAD
  else
    git -C "$3" fetch -q origin
    git -C "$3" checkout -q "$2"
  fi
  local fick
  fick="$(git -C "$3" rev-parse HEAD)"
  [ "$fick" = "$2" ] || fel "$1: commit $fick, väntade $2"
  echo "ok  $1 @ $2"
}

# Verktygskedjan för cmake och meson.
cat > "$ARB/mingw.cmake" <<EOF
set(CMAKE_SYSTEM_NAME Windows)
set(CMAKE_SYSTEM_PROCESSOR x86_64)
set(CMAKE_C_COMPILER $CC_X)
set(CMAKE_CXX_COMPILER $CXX_X)
set(CMAKE_RC_COMPILER $VARD-windres)
set(CMAKE_FIND_ROOT_PATH /usr/$VARD $P)
set(CMAKE_FIND_ROOT_PATH_MODE_PROGRAM NEVER)
set(CMAKE_FIND_ROOT_PATH_MODE_LIBRARY ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_INCLUDE ONLY)
set(CMAKE_FIND_ROOT_PATH_MODE_PACKAGE ONLY)
EOF
cat > "$ARB/mingw.meson" <<EOF
[binaries]
c = '$CC_X'
cpp = '$CXX_X'
ar = '$VARD-ar'
strip = '$VARD-strip'
windres = '$VARD-windres'
pkg-config = 'pkg-config'
nasm = 'nasm'

[host_machine]
system = 'windows'
cpu_family = 'x86_64'
cpu = 'x86_64'
endian = 'little'
EOF
CMAKE_GEMENSAMT=(-DCMAKE_TOOLCHAIN_FILE="$ARB/mingw.cmake" -DCMAKE_BUILD_TYPE=Release
  -DCMAKE_INSTALL_PREFIX="$P" -DCMAKE_PREFIX_PATH="$P" -DCMAKE_INSTALL_LIBDIR=lib -DBUILD_SHARED_LIBS=OFF)

# --- 1. Källkoden ----------------------------------------------------------
steg "Hämtar källkoden"
cd "$ARB/src"

curl -fsSLO "https://ffmpeg.org/releases/ffmpeg-$FFMPEG_VERSION.tar.xz"
curl -fsSLO "https://ffmpeg.org/releases/ffmpeg-$FFMPEG_VERSION.tar.xz.asc"
kontrollsumma "ffmpeg-$FFMPEG_VERSION.tar.xz" "$FFMPEG_SHA256"
if command -v gpg >/dev/null 2>&1; then
  export GNUPGHOME="$(mktemp -d)"; chmod 700 "$GNUPGHOME"
  curl -fsSL https://ffmpeg.org/ffmpeg-devel.asc -o ffmpeg-devel.asc
  gpg --batch --quiet --import ffmpeg-devel.asc
  gpg --batch --with-colons --fingerprint | grep "^fpr:::::::::$FFMPEG_KEY_FINGERPRINT:" >/dev/null \
    || fel "FFmpegs nyckel har inte fingeravtrycket $FFMPEG_KEY_FINGERPRINT"
  gpg --batch --status-fd 1 --verify "ffmpeg-$FFMPEG_VERSION.tar.xz.asc" "ffmpeg-$FFMPEG_VERSION.tar.xz" \
    | grep "^\[GNUPG:\] VALIDSIG $FFMPEG_KEY_FINGERPRINT " >/dev/null || fel "ffmpeg-tarbollens signatur stämmer inte"
  echo "ok  ffmpeg-$FFMPEG_VERSION.tar.xz signatur ($FFMPEG_KEY_FINGERPRINT)"
else
  fel "gpg saknas — signaturen måste kontrolleras (paketet gnupg)"
fi

curl -fsSLO "https://github.com/Mbed-TLS/mbedtls/releases/download/mbedtls-$MBEDTLS_VERSION/mbedtls-$MBEDTLS_VERSION.tar.bz2"
kontrollsumma "mbedtls-$MBEDTLS_VERSION.tar.bz2" "$MBEDTLS_SHA256"

git_vid_commit https://code.videolan.org/videolan/x264.git "$X264_COMMIT" x264
git_vid_commit https://github.com/Haivision/srt.git "$SRT_COMMIT" srt
git_vid_commit https://github.com/FFmpeg/nv-codec-headers.git "$NVCODEC_COMMIT" nv-codec-headers
git_vid_commit https://github.com/GPUOpen-LibrariesAndSDKs/AMF.git "$AMF_COMMIT" amf
git_vid_commit https://github.com/intel/libvpl.git "$LIBVPL_COMMIT" libvpl
git_vid_commit https://code.videolan.org/videolan/dav1d.git "$DAV1D_COMMIT" dav1d
git_vid_commit https://github.com/xiph/opus.git "$OPUS_COMMIT" opus
git_vid_commit https://github.com/madler/zlib.git "$ZLIB_COMMIT" zlib
git_vid_commit https://gitlab.gnome.org/GNOME/libxml2.git "$LIBXML2_COMMIT" libxml2

# Exakt den källkod som byggs, för releasen (GPL: "the complete corresponding
# source code"). Git-källorna som git archive av den låsta commiten. Ur AMF
# används bara huvudfilerna, och bara de följer med.
cp "ffmpeg-$FFMPEG_VERSION.tar.xz" "ffmpeg-$FFMPEG_VERSION.tar.xz.asc" "mbedtls-$MBEDTLS_VERSION.tar.bz2" "$UT/source/"
arkiv() { git -C "$1" archive --format=tar.gz --prefix="$1-$2/" -o "$UT/source/$1-$2.tar.gz" HEAD "${@:3}"; }
arkiv x264 "$X264_COMMIT"
arkiv srt "$SRT_VERSION"
arkiv nv-codec-headers "$NVCODEC_COMMIT"
arkiv amf "$AMF_COMMIT" amf/public/include LICENSE.txt
arkiv libvpl "$LIBVPL_COMMIT"
arkiv dav1d "$DAV1D_COMMIT"
arkiv opus "$OPUS_COMMIT"
arkiv zlib "$ZLIB_COMMIT"
arkiv libxml2 "$LIBXML2_COMMIT"
# Byggskripten hör till källkoden (GPLv2 §3: "the scripts used to control
# compilation and installation").
mkdir -p "$UT/source/build-scripts"
cp "$ROT/build.sh" "$ROT/versions.env" "$ROT/check.ps1" "$UT/source/build-scripts/"
for yml in "$ROT/build-ffmpeg-windows.yml" "$ROT/../../.github/workflows/build-ffmpeg-windows.yml"; do
  if [ -f "$yml" ]; then cp "$yml" "$UT/source/build-scripts/"; break; fi
done

# Verktygskedjan: vilken mingw-w64, och dess egen källkod (C-körbiblioteket
# och winpthreads länkas in statiskt).
{
  echo "Toolchain used to build ffmpeg.exe and ffprobe.exe"
  echo
  dpkg -s mingw-w64-common | grep -E '^(Package|Version):'
  echo
  "$CC_X" --version | head -1
  "$CXX_X" --version | head -1
} > "$UT/source/TOOLCHAIN.txt"
MINGW_UPSTREAM="$(dpkg-query -W -f='${Version}' mingw-w64-common | sed -E 's/^[0-9]+://; s/-[^-]*$//; s/[+~].*$//')"
curl -fsSL "https://github.com/mingw-w64/mingw-w64/archive/refs/tags/v$MINGW_UPSTREAM.tar.gz" \
  -o "$UT/source/mingw-w64-v$MINGW_UPSTREAM.tar.gz" || fel "mingw-w64 v$MINGW_UPSTREAM: källkoden gick inte att hämta"
echo "ok  mingw-w64 v$MINGW_UPSTREAM (källkod)"

tar -xf "ffmpeg-$FFMPEG_VERSION.tar.xz"
tar -xf "mbedtls-$MBEDTLS_VERSION.tar.bz2"

# --- 2. Huvudfilerna (nvidia, amd) -----------------------------------------
steg "nv-codec-headers och AMF"
make -C nv-codec-headers PREFIX="$P" install
mkdir -p "$P/include/AMF"
cp -r amf/amf/public/include/. "$P/include/AMF/"

# --- 3. zlib ---------------------------------------------------------------
steg "zlib"
( cd zlib && CC="$CC_X" AR="$VARD-ar" RANLIB="$VARD-ranlib" ./configure --prefix="$P" --static \
  && make -j "$JOBB" && make install )

# --- 4. libxml2 ------------------------------------------------------------
steg "libxml2"
cmake -S libxml2 -B "$ARB/bygg-libxml2" "${CMAKE_GEMENSAMT[@]}" \
  -DLIBXML2_WITH_PYTHON=OFF -DLIBXML2_WITH_TESTS=OFF -DLIBXML2_WITH_PROGRAMS=OFF \
  -DLIBXML2_WITH_ICONV=OFF -DLIBXML2_WITH_ICU=OFF -DLIBXML2_WITH_LZMA=OFF -DLIBXML2_WITH_ZLIB=ON
cmake --build "$ARB/bygg-libxml2" -j "$JOBB"
cmake --install "$ARB/bygg-libxml2"

# --- 5. opus ---------------------------------------------------------------
steg "opus"
cmake -S opus -B "$ARB/bygg-opus" "${CMAKE_GEMENSAMT[@]}" \
  -DOPUS_BUILD_PROGRAMS=OFF -DOPUS_BUILD_TESTING=OFF -DOPUS_STACK_PROTECTOR=OFF -DOPUS_FORTIFY_SOURCE=OFF
cmake --build "$ARB/bygg-opus" -j "$JOBB"
cmake --install "$ARB/bygg-opus"

# --- 6. dav1d --------------------------------------------------------------
steg "dav1d"
meson setup "$ARB/bygg-dav1d" dav1d --cross-file "$ARB/mingw.meson" --prefix="$P" --libdir=lib \
  --buildtype=release -Ddefault_library=static -Denable_tools=false -Denable_tests=false -Denable_examples=false
ninja -C "$ARB/bygg-dav1d" install

# --- 7. libvpl -------------------------------------------------------------
steg "libvpl"
cmake -S libvpl -B "$ARB/bygg-libvpl" "${CMAKE_GEMENSAMT[@]}" \
  -DBUILD_TOOLS=OFF -DBUILD_EXAMPLES=OFF -DBUILD_TESTS=OFF -DINSTALL_EXAMPLES=OFF -DINSTALL_DEV=ON -DBUILD_EXPERIMENTAL=OFF
cmake --build "$ARB/bygg-libvpl" -j "$JOBB"
cmake --install "$ARB/bygg-libvpl"

# --- 8. Mbed TLS -----------------------------------------------------------
steg "Mbed TLS $MBEDTLS_VERSION"
cmake -S "mbedtls-$MBEDTLS_VERSION" -B "$ARB/bygg-mbedtls" "${CMAKE_GEMENSAMT[@]}" \
  -DENABLE_TESTING=OFF -DENABLE_PROGRAMS=OFF -DGEN_FILES=OFF \
  -DUSE_SHARED_MBEDTLS_LIBRARY=OFF -DUSE_STATIC_MBEDTLS_LIBRARY=ON
cmake --build "$ARB/bygg-mbedtls" -j "$JOBB"
cmake --install "$ARB/bygg-mbedtls"

# --- 9. SRT ----------------------------------------------------------------
steg "SRT $SRT_VERSION (kryptering via Mbed TLS)"
cmake -S srt -B "$ARB/bygg-srt" "${CMAKE_GEMENSAMT[@]}" \
  -DENABLE_SHARED=OFF -DENABLE_STATIC=ON -DENABLE_APPS=OFF \
  -DENABLE_ENCRYPTION=ON -DUSE_ENCLIB=mbedtls -DENABLE_STDCXX_SYNC=ON
cmake --build "$ARB/bygg-srt" -j "$JOBB"
cmake --install "$ARB/bygg-srt"

# --- 10. x264 --------------------------------------------------------------
steg "x264 $X264_COMMIT"
( cd x264 && CC="$CC_X" ./configure --prefix="$P" --host="$VARD" --cross-prefix="$VARD-" \
    --enable-static --disable-cli --disable-opencl \
  && make -j "$JOBB" && make install )

# --- 11. FFmpeg ------------------------------------------------------------
steg "FFmpeg $FFMPEG_VERSION"
cd "$ARB/src/ffmpeg-$FFMPEG_VERSION"
./configure --prefix="$P" --target-os=mingw32 --arch=x86_64 --cross-prefix="$VARD-" \
  --cc="$CC_X" --cxx="$CXX_X" --pkg-config=pkg-config --pkg-config-flags=--static \
  --extra-cflags="-I$P/include -DLIBXML_STATIC" \
  --extra-ldflags="-L$P/lib -static -static-libgcc -static-libstdc++" \
  --extra-libs="-lstdc++ -lbcrypt -lws2_32 -lole32 -luuid" \
  --enable-gpl --enable-libx264 --enable-libsrt \
  --enable-ffnvcodec --enable-nvenc --enable-nvdec --enable-cuvid --enable-cuda-llvm \
  --enable-libvpl --enable-amf --enable-mediafoundation --enable-d3d11va --enable-dxva2 \
  --enable-schannel --enable-libopus --enable-libdav1d --enable-zlib --enable-libxml2 \
  --disable-ffplay --disable-doc --disable-debug --disable-shared --enable-static
make -j "$JOBB"
cp ffmpeg.exe ffprobe.exe "$UT/"

# Konfigurationsraden, samma text som `ffmpeg -buildconf` (check.ps1 jämför).
sed -n 's/^#define FFMPEG_CONFIGURATION "\(.*\)"$/\1/p' config.h > "$UT/CONFIGURE.txt"
[ -s "$UT/CONFIGURE.txt" ] || fel "FFMPEG_CONFIGURATION saknas i config.h"

# Licenstexterna, ordagrant ur källkoden.
cp COPYING.GPLv2 "$UT/licenses/GPL-2.0.txt"
cp COPYING.LGPLv2.1 "$UT/licenses/LGPL-2.1.txt"
cp LICENSE.md "$UT/licenses/FFmpeg-LICENSE.md"
S="$ARB/src"
cp "$S/x264/COPYING" "$UT/licenses/x264-COPYING.txt"
cp "$S/srt/LICENSE" "$UT/licenses/SRT-MPL-2.0.txt"
cp "$S/mbedtls-$MBEDTLS_VERSION/LICENSE" "$UT/licenses/MbedTLS-LICENSE.txt"
# nv-codec-headers har ingen licensfil; MIT-texten står överst i huvudfilen.
sed -n '1,/\*\//p' "$S/nv-codec-headers/include/ffnvcodec/nvEncodeAPI.h" > "$UT/licenses/nv-codec-headers-MIT.txt"
cp "$S/amf/LICENSE.txt" "$UT/licenses/AMF-LICENSE.txt"
cp "$S/libvpl/LICENSE" "$UT/licenses/libvpl-LICENSE.txt"
cp "$S/dav1d/COPYING" "$UT/licenses/dav1d-COPYING.txt"
cp "$S/opus/COPYING" "$UT/licenses/opus-COPYING.txt"
cp "$S/zlib/LICENSE" "$UT/licenses/zlib-LICENSE.txt"
cp "$S/libxml2/Copyright" "$UT/licenses/libxml2-Copyright.txt"
cp /usr/share/doc/mingw-w64-common/copyright "$UT/licenses/mingw-w64-copyright.txt"
# GCC:s körbibliotek (libgcc, libstdc++) länkas in statiskt under GCC Runtime
# Library Exception; texten följer med.
for d in gcc-mingw-w64-base gcc-mingw-w64-x86-64-posix-runtime; do
  if [ -f "/usr/share/doc/$d/copyright" ]; then cp "/usr/share/doc/$d/copyright" "$UT/licenses/gcc-runtime-copyright.txt"; break; fi
done

# --- 12. Kontroller som går på Linux ----------------------------------------
steg "Kontroller"
cd "$UT"
grep -q -- '--enable-gpl' CONFIGURE.txt || fel "--enable-gpl saknas"
! grep -q -- '--enable-nonfree' CONFIGURE.txt || fel "--enable-nonfree får aldrig vara med"
! grep -q -- '--enable-version3' CONFIGURE.txt || fel "--enable-version3 får aldrig vara med"
echo "ok  konfigurationen: GPL, varken nonfree eller version3"

# Bara Windows egna DLL:er: inget ur GCC, inget ur byggets prefix.
EGNA="$(find "$P" -iname '*.dll' -printf '%f\n' 2>/dev/null | tr 'A-Z' 'a-z' | sort -u)"
for bin in ffmpeg.exe ffprobe.exe; do
  DLLER="$("$VARD-objdump" -p "$bin" | sed -n 's/^\s*DLL Name: //p' | tr 'A-Z' 'a-z' | sort -u)"
  echo "$bin importerar: $(echo "$DLLER" | tr '\n' ' ')"
  if echo "$DLLER" | grep -E '^(libgcc_s|libstdc\+\+|libwinpthread)' >/dev/null; then
    fel "$bin importerar GCC:s körbibliotek (ska vara statiskt länkat)"
  fi
  for dll in $DLLER; do
    if echo "$EGNA" | grep -qx "$dll"; then fel "$bin importerar $dll ur byggets prefix (ska vara statiskt länkat)"; fi
  done
done
echo "ok  bara Windows egna DLL:er (objdump -p)"

find ffmpeg.exe ffprobe.exe CONFIGURE.txt source licenses -type f ! -name SHA256SUMS -print0 | sort -z | xargs -0 sha256sum > SHA256SUMS
steg "Klart"
cat SHA256SUMS

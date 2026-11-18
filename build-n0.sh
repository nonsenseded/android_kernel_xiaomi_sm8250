#!/usr/bin/env bash
#
# Build the "milkii" kernel for munch (POCO F4), from ~/n0kernel.
# Base: EmanuelCN N0Kernel 4.19.246 -- the kernel the ROM actually ships.
# Defaults: BakaSU enabled (manual hook), no LTO, output in out-ksu.
#
# Usage:
#   ./build-n0.sh                 # BakaSU (manual hook), no LTO  [default]
#   KSU=0 ./build-n0.sh           # vanilla, no KSU
#   LTO=1 ./build-n0.sh           # keep ThinLTO (not tested with distro clang)
#   OUT=out-foo ./build-n0.sh     # build somewhere else
#
set -euo pipefail
cd "$(dirname "$(readlink -f "$0")")"

OUT="${OUT:-out-ksu}"
JOBS="${JOBS:-8}"
KSU="${KSU:-1}"
LTO="${LTO:-0}"

# Identity shown by uname -r and /proc/version.
export KBUILD_BUILD_USER="${KBUILD_BUILD_USER:-milk}"
export KBUILD_BUILD_HOST="${KBUILD_BUILD_HOST:-milkpc}"
export KBUILD_BUILD_VERSION="${KBUILD_BUILD_VERSION:-1}"

export ARCH=arm64
export LLVM=1
export CC=clang
export CROSS_COMPILE=aarch64-linux-gnu-
export CLANG_TRIPLE=aarch64-linux-gnu-
export DTC_EXT="${DTC_EXT:-/usr/bin/dtc}"

MAKE=(make O="$OUT" ARCH=arm64 LLVM=1 CC=clang CROSS_COMPILE="$CROSS_COMPILE" CLANG_TRIPLE="$CLANG_TRIPLE")

echo ">> defconfig: vendor/munch_defconfig"
"${MAKE[@]}" vendor/munch_defconfig

# Branding: fork name plus the git revision.
# This tree ignores CONFIG_LOCALVERSION_AUTO, so the suffix is added here.
FORK_NAME="${FORK_NAME:-milkii}"
GIT_SHORT="$(git rev-parse --short=8 HEAD 2>/dev/null || true)"
LOCALVER="-$FORK_NAME"
if [ -n "$GIT_SHORT" ]; then
  LOCALVER="$LOCALVER-g$GIT_SHORT"
  git diff-index --quiet HEAD -- 2>/dev/null || LOCALVER="$LOCALVER-dirty"
fi
scripts/config --file "$OUT/.config" --set-str LOCALVERSION "$LOCALVER"

if [ "$KSU" = "1" ]; then
  # stock ROM kernel has KALLSYMS_ALL; BakaSU needs it (otherwise it demands
  # exported SELinux internals). The dependency on DEBUG_KERNEL is dropped
  # below, because this tree's sched debug code does not compile as-is.
  scripts/config --file "$OUT/.config" \
    -e KALLSYMS_ALL \
    -e KSU -e KSU_MANUAL_HOOK -d KSU_TRACEPOINT_HOOK -e KSU_MULTI_MANAGER_SUPPORT \
    -e KSU_MANUAL_HOOK_AUTO_SETUID_HOOK -e KSU_MANUAL_HOOK_AUTO_INITRC_HOOK \
    -e KSU_MANUAL_HOOK_AUTO_INPUT_HOOK
else
  scripts/config --file "$OUT/.config" -d KSU -d KSU_MANUAL_HOOK
fi
if [ "$LTO" = "0" ]; then
  scripts/config --file "$OUT/.config" -d LTO_CLANG -d LTO_CLANG_THIN -e LTO_NONE
fi

"${MAKE[@]}" olddefconfig
"${MAKE[@]}" syncconfig

echo ">> release: $("${MAKE[@]}" -s kernelrelease 2>/dev/null || true)"
echo ">> building Image -j$JOBS"
"${MAKE[@]}" -j"$JOBS" Image

echo ">> done: $OUT/arch/arm64/boot/Image"
ls -la "$OUT/arch/arm64/boot/Image"

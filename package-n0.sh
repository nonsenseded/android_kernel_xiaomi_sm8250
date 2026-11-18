#!/usr/bin/env bash
#
# Package the milkii munch kernel into an AnyKernel3 zip, shaped like the
# community builds:
#   <Kernel>_<ROM>_<device>_<flavor>_<date>_<time>_anykernel3_<hash>.zip
#
# The zip replaces ONLY the kernel inside the existing boot image, so the
# OrangeFox ramdisk (recovery-in-boot on munch) is preserved.
#
# Usage:
#   ./package-n0.sh
#   COPYTO=/mnt/c/Users/milk/Downloads ./package-n0.sh
#   KERNEL_NAME=foo FLAVOR=bar ./package-n0.sh
#
set -euo pipefail

cd "$(dirname "$(readlink -f "$0")")"

OUT="${OUT:-out-ksu}"
DIST="${DIST:-dist}"
AK3_DIR="${AK3_DIR:-$HOME/android_kernel_xiaomi_sm8250/AnyKernel3}"

KERNEL_NAME="${KERNEL_NAME:-milkii}"
ROM_TYPE="${ROM_TYPE:-AOSP}"
DEVICE="${DEVICE:-munch}"
FLAVOR="${FLAVOR:-BakaSU}"

IMG="$OUT/arch/arm64/boot/Image"
die() { echo "error: $*" >&2; exit 1; }
[ -f "$IMG" ] || die "no Image under $OUT -- build first"

if [ -s "$OUT/include/config/kernel.release" ]; then
  RELEASE="$(cat "$OUT/include/config/kernel.release")"
else
  RELEASE="unknown"
fi

HASH="$(git rev-parse --short=8 HEAD 2>/dev/null || echo 00000000)"
STAMP="$(date +%Y%m%d_%H%M%S)"
ZIPNAME="${KERNEL_NAME}_${ROM_TYPE}_${DEVICE}_${FLAVOR}_${STAMP}_anykernel3_${HASH}.zip"

echo ">> Release: $RELEASE"
echo ">> Image:   $IMG ($(du -h "$IMG" | cut -f1))"

[ -d "$AK3_DIR/tools" ] || die "AnyKernel3 template not found at $AK3_DIR"

STAGE="$DIST/.stage"
rm -rf "$STAGE"
mkdir -p "$STAGE/kernels/aosp"
cp -a "$AK3_DIR/META-INF" "$AK3_DIR/tools" "$STAGE/"
cp -f "$AK3_DIR/LICENSE" "$AK3_DIR/README.md" "$STAGE/"
cp -f "$IMG" "$STAGE/kernels/aosp/Image"

cat > "$STAGE/anykernel.sh" <<'AK3EOF'
### AnyKernel3 Ramdisk Mod Script - munch (POCO F4 / Redmi K40S)

properties() { '
kernel.string=__KERNEL_NAME__ (__RELEASE__) for munch - __FLAVOR__
do.devicecheck=1
do.modules=0
do.systemless=1
do.cleanup=1
do.cleanuponabort=0
device.name1=munch
device.name2=munchg
device.name3=POCOF4
device.name4=RedmiK40S
device.name5=
supported.versions=
supported.patchlevels=
supported.vendorpatchlevels=
'; } # end properties

### AnyKernel install
# boot shell variables
BLOCK=boot;
IS_SLOT_DEVICE=auto;
RAMDISK_COMPRESSION=auto;
PATCH_VBMETA_FLAG=auto;

# import functions/variables and setup patching - see for reference (DO NOT REMOVE)
. tools/ak3-core.sh;

ui_print " ";
ui_print "  __KERNEL_NAME__ for munch";
ui_print "  __RELEASE__";
ui_print " ";
ui_print "  OrangeFox ramdisk is kept (kernel-only patch).";
ui_print " ";

# Kernel-only install: split the image, swap the kernel, leave the ramdisk
# (and therefore OrangeFox recovery) untouched.
split_boot;

if [ -f $AKHOME/kernels/aosp/Image ]; then
  mv $AKHOME/kernels/aosp/Image $AKHOME/Image;
else
  abort "no kernel image in this zip!";
fi;

flash_boot;
## end boot install

ui_print " ";
ui_print "  done - reboot to system.";
ui_print " ";
AK3EOF

sed -i -e "s|__KERNEL_NAME__|$KERNEL_NAME|g" \
       -e "s|__FLAVOR__|$FLAVOR|g" \
       -e "s|__RELEASE__|$RELEASE|g" "$STAGE/anykernel.sh"

mkdir -p "$DIST"
ZIP="$(readlink -f "$DIST")/$ZIPNAME"
rm -f "$ZIP"
( cd "$STAGE" && zip -r9 "$ZIP" . -x '*.git*' >/dev/null )
rm -rf "$STAGE"

echo ">> Wrote $ZIP ($(du -h "$ZIP" | cut -f1))"
sha256sum "$ZIP"

if [ -n "${COPYTO:-}" ]; then
  mkdir -p "$COPYTO"
  cp -f "$ZIP" "$COPYTO/"
  echo ">> Copied to $COPYTO/$ZIPNAME"
fi

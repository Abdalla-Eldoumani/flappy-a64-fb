#!/usr/bin/env bash
# Builds DIR/vmlinuz and DIR/initramfs.cpio.gz from the packages fetch.sh put in DIR/dl: a static
# busybox, the six kernel modules the display and the keyboard need (decompressed, since
# busybox's insmod takes plain .ko files), the game and vm/init. The packages are only unpacked
# here; nothing in them runs on this machine.
# usage: bash vm/initramfs.sh DIR GAME
set -eu
dir=$1
game=$2
here=$(cd "$(dirname "$0")" && pwd)
kver=6.12.113+deb13-arm64
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
dpkg-deb -x "$dir/dl/linux-image-${kver}_6.12.113-1_arm64.deb" "$work/k"
dpkg-deb -x "$dir/dl/busybox-static_1.37.0-6+b9_arm64.deb" "$work/b"
r=$work/root
mkdir -p "$r/bin" "$r/dev" "$r/proc" "$r/sys" "$r/lib/modules"
cp "$work/b/usr/bin/busybox" "$r/bin/busybox"
m=$work/k/usr/lib/modules/$kver/kernel/drivers
for f in gpu/drm/drm gpu/drm/drm_kms_helper gpu/drm/drm_shmem_helper virtio/virtio_dma_buf \
  gpu/drm/virtio/virtio-gpu virtio/virtio_input; do
  xz -dc "$m/$f.ko.xz" > "$r/lib/modules/${f##*/}.ko"
done
cp "$game" "$r/flappy"
cp "$here/init" "$r/init"
chmod 755 "$r/init" "$r/flappy" "$r/bin/busybox"
python3 "$here/newc.py" "$r" | gzip -9 > "$dir/initramfs.cpio.gz"
cp "$work/k/boot/vmlinuz-$kver" "$dir/vmlinuz"
echo "$dir/vmlinuz $dir/initramfs.cpio.gz"

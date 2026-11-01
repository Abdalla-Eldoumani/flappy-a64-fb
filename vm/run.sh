#!/usr/bin/env bash
# Boots the VM in a window: the game on a virtio display with a virtio keyboard, the kernel's
# messages in this terminal. Any further arguments go to the game, for example --seed 3.
# q in the game, or closing the window, ends it.
# usage: bash vm/run.sh DIR [game arguments]
set -eu
dir=$1
shift
exec qemu-system-aarch64 -M virt -cpu max -m 256 \
  -kernel "$dir/vmlinuz" -initrd "$dir/initramfs.cpio.gz" \
  -append "console=ttyAMA0 quiet -- $*" \
  -device virtio-gpu-pci -device virtio-keyboard-pci \
  -serial stdio -monitor tcp:127.0.0.1:5555,server,nowait

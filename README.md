# flappy-a64-fb

The same game as [flappy-a64](https://github.com/Abdalla-Eldoumani/flappy-a64), drawn straight
to a Linux framebuffer, `/dev/fb0`, instead of a terminal. The game itself lives in flappy-a64,
which this repository includes as the `core` submodule. This repository adds the part that
writes pixels and a small QEMU virtual machine to play it in.

## Run it

On Windows, inside WSL (Ubuntu or Debian):

```
sudo apt install make m4 gcc-aarch64-linux-gnu libc6-dev-arm64-cross qemu-user qemu-system-arm curl xz-utils python3
git clone --recurse-submodules https://github.com/Abdalla-Eldoumani/flappy-a64-fb
cd flappy-a64-fb
make play
```

`make play` builds the game, downloads two Debian packages (an arm64 kernel and busybox, about
94 MB, each checked against its sha256), packs them with the game into a small initramfs and
boots it in a QEMU window. The keys are the terminal version's: Space flaps, P pauses, Q quits
and powers the VM off. To pass the game arguments, boot it by hand:
`bash vm/run.sh build/vm --seed 3`.

The release carries the static binary, `flappy-fb-linux-arm64`. On an aarch64 Linux machine
with a framebuffer it runs from a text console (not from inside a desktop session), where it
switches the console to graphics until it quits.

## How it works

**The presenter.** `src/fb.asm` takes the place of core's terminal presenter. It asks the
framebuffer for its size, pixel layout and line length with two ioctls, picks the largest whole
scale k that fits the 144 by 256 picture, and centres it. Each frame it compares every row with
the frame before and writes only the rows that changed: each pixel k wide, each row k times,
with `lseek` and `write`. While it runs, the console is in graphics mode, so its text and cursor
stay off the picture.

**The VM.** QEMU's `virt` machine with a virtio display and a virtio keyboard. Debian's arm64
kernel builds both drivers as modules, so `vm/initramfs.sh` takes the kernel, the six modules
those two need and a static busybox from the downloaded packages, and adds the game and
`vm/init`. That script mounts `/dev`, `/proc` and `/sys`, loads the modules, runs the game on
the first virtual console and powers the machine off when it ends.

## Build and test

- `make` builds `build/flappy-fb`. `make bundle` writes the whole program as one file,
  `dist/flappy-fb-bundle.asm`.
- `make test` runs:
  - goldens: core's recorded headless runs must match this build byte for byte, and the
    one-file bundle's.
  - vmcheck: boots the VM without a window and checks it through QEMU's monitor. The title on
    the screen must equal one of the terminal build's own title frames for the same seed, pixel
    for pixel, at k times the size and centred. Space must bring up get ready, and Q must end
    the game with status 0 and power the VM off.

## Credits

The gameplay is Dong Nguyen's Flappy Bird; everything else comes from flappy-a64.

## License

MIT. See [LICENSE](LICENSE). The kernel and busybox the VM downloads are GPL software from
Debian. They are not part of this repository or its releases; `vm/` fetches them from Debian
at build time.

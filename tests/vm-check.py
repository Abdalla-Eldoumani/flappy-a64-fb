#!/usr/bin/env python3
# Boots the VM without a window and checks it through QEMU's monitor. The title on the screen
# must equal, pixel for pixel, one of the terminal build's own title frames for the same seed,
# each pixel a k x k block, centred on one border colour. Space must leave the title for get
# ready, and q must end the game with status 0 and power the VM off.
# usage: python3 tests/vm-check.py VMDIR REFERENCE_BINARY [runner]
import os
import shutil
import socket
import subprocess
import sys
import tempfile
import time

LOG_W, LOG_H = 144, 256
SEED = "3"
# the title loops with the bird's bob, its wing and the ground, all well inside 200 ticks
TICKS = 200
PORT = 5555
WORD, WHITE = bytes([252, 168, 48]), bytes([255, 255, 255])

vmdir, ref = os.path.abspath(sys.argv[1]), os.path.abspath(sys.argv[2])
runner = sys.argv[3:]
bad = 0


def report(ok, what):
    global bad
    print(("PASS " if ok else "FAIL ") + what)
    if not ok:
        bad = 1


def ppm(path):
    d = open(path, "rb").read()
    head, rest = d.split(b"\n", 1)
    assert head == b"P6", path
    dims, rest = rest.split(b"\n", 1)
    w, h = map(int, dims.split())
    _, px = rest.split(b"\n", 1)
    return w, h, px


# the terminal build's title frames: render-out draws every tick, and a press never comes
refdir = tempfile.mkdtemp(prefix="vmref-")
ticks = ",".join(str(t) for t in range(1, TICKS + 1))
subprocess.run(runner + [ref, "--render-out", "--ticks", str(TICKS), "--seed", SEED, "--size",
                         "144x128", "--dump-frames", ticks, "--dump-dir", refdir],
               cwd=refdir, stdout=subprocess.DEVNULL, check=True, timeout=600)
titles = {ppm(os.path.join(refdir, f"{t}.ppm"))[2] for t in range(1, TICKS + 1)}
shutil.rmtree(refdir)


def picture(path):
    # the logical picture back from the screen, or None when it is not a clean k x k upscale
    # centred on a border of one colour
    w, h, px = ppm(path)
    k = min(w // LOG_W, h // LOG_H)
    if k == 0:
        return None
    ox, oy = (w - LOG_W * k) // 2, (h - LOG_H * k) // 2
    at = lambda x, y: px[(y * w + x) * 3:(y * w + x) * 3 + 3]
    out = bytearray()
    for y in range(LOG_H):
        for x in range(LOG_W):
            p = at(ox + x * k, oy + y * k)
            if at(ox + x * k + k - 1, oy + y * k + k - 1) != p:
                return None
            out += p
    border = {at(0, 0), at(w - 1, h - 1), at(ox - 1, oy), at(ox + LOG_W * k, oy + LOG_H * k - 1)}
    if ox and oy and len(border) != 1:
        return None
    return bytes(out)


class Monitor:
    def __init__(self):
        deadline = time.monotonic() + 60
        while True:
            try:
                self.s = socket.create_connection(("127.0.0.1", PORT), timeout=10)
                break
            except OSError:
                if time.monotonic() > deadline:
                    raise
                time.sleep(0.5)
        self.read()

    def read(self):
        data = b""
        while not data.endswith(b"(qemu) "):
            chunk = self.s.recv(4096)
            if not chunk:
                break
            data += chunk
        return data

    def cmd(self, text):
        self.s.sendall(text.encode() + b"\n")
        return self.read()


serial = os.path.join(vmdir, "serial.log")
shot = os.path.join(vmdir, "shot.ppm")
qemu = subprocess.Popen(
    ["qemu-system-aarch64", "-M", "virt", "-cpu", "max", "-m", "256",
     "-kernel", os.path.join(vmdir, "vmlinuz"), "-initrd", os.path.join(vmdir, "initramfs.cpio.gz"),
     "-append", f"console=ttyAMA0 quiet -- --seed {SEED}",
     "-device", "virtio-gpu-pci", "-device", "virtio-keyboard-pci", "-display", "none",
     "-serial", f"file:{serial}", "-monitor", f"tcp:127.0.0.1:{PORT},server,nowait"],
    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
try:
    mon = Monitor()

    # wait_for(test, seconds): screenshots once a second until one passes the test; a shot taken
    # while a frame is being written mixes two frames and is not a clean picture, so it never does
    def wait_for(test, seconds):
        seen, deadline = None, time.monotonic() + seconds
        while time.monotonic() < deadline and not (seen is not None and test(seen)):
            time.sleep(1)
            mon.cmd(f"screendump {shot}")
            if os.path.exists(shot):
                seen = picture(shot)
        return seen is not None and test(seen)

    def ready(seen):
        top = WHITE in {seen[i:i + 3] for i in range(0, LOG_W * 40 * 3, 3)}
        word = WORD in {seen[i:i + 3] for i in range(0, len(seen), 3)}
        return seen not in titles and top and word

    # boot, drivers and the first frames take a while under emulation
    report(wait_for(lambda seen: seen in titles, 180),
           f"title: the screen is one of the {TICKS} reference title frames, k times larger and centred")
    mon.cmd("sendkey spc")
    report(wait_for(ready, 20),
           "space: the title gives way to get ready (its words and the score at the top)")

    mon.cmd("sendkey q")
    try:
        qemu.wait(timeout=60)
        ended = "the game ended with status 0" in open(serial, errors="replace").read()
        report(ended and qemu.returncode == 0, "q: the game ends with status 0 and the VM powers off")
    except subprocess.TimeoutExpired:
        report(False, "q: the VM was still running a minute later")
finally:
    if qemu.poll() is None:
        qemu.kill()
        qemu.wait()
sys.exit(bad)

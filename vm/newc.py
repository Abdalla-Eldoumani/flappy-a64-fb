#!/usr/bin/env python3
# Writes the tree under DIR to stdout as a newc cpio archive, the format the kernel unpacks an
# initramfs from, so building one needs no cpio tool. Every entry belongs to root.
# usage: python3 vm/newc.py DIR > archive.cpio
import os
import stat
import sys

root = sys.argv[1]
out = sys.stdout.buffer
ino = 0


def entry(name, mode, data=b"", nlink=1):
    # 110 bytes of header: the magic, then 13 fields of 8 hex digits; header and name, and the
    # data, each pad to a multiple of 4
    global ino
    ino += 1
    name = name.encode() + b"\0"
    fields = (ino, mode, 0, 0, nlink, 0, len(data), 0, 0, 0, 0, len(name), 0)
    head = b"070701" + b"".join(b"%08X" % v for v in fields)
    out.write(head + name + b"\0" * (-(len(head) + len(name)) % 4))
    out.write(data + b"\0" * (-len(data) % 4))


for d, dirs, files in os.walk(root):
    dirs.sort()
    files.sort()
    rel = os.path.relpath(d, root)
    if rel != ".":
        entry(rel, stat.S_IFDIR | 0o755, nlink=2)
    for f in files:
        path = os.path.join(d, f)
        name = os.path.normpath(os.path.join(rel, f))
        st = os.lstat(path)
        if stat.S_ISLNK(st.st_mode):
            entry(name, stat.S_IFLNK | 0o777, os.readlink(path).encode())
        else:
            entry(name, stat.S_IFREG | (st.st_mode & 0o777), open(path, "rb").read())
entry("TRAILER!!!", 0)

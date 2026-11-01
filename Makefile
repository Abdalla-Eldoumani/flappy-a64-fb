# The game from core/ (the terminal version, a submodule) with src/fb.asm in place of its
# terminal presenter, so it draws to /dev/fb0. It cross-builds to a static aarch64 binary on
# x86_64 Linux, and vm/ boots it in QEMU on a tiny Linux built from pinned Debian packages.

CORE := core
MODS := main tty sim art gfx save
CSRC := $(MODS:%=$(CORE)/src/%.asm)
ASM := $(MODS:%=build/%.s) build/fb.s
DEFS := $(CORE)/src/defs.m4

# the VM has no C library, so the binary is static wherever it is built
CC := aarch64-linux-gnu-gcc
ifeq ($(shell uname -m),aarch64)
CC := gcc
RUN :=
else
RUN := qemu-aarch64
endif
CFLAGS := -static -Wa,--fatal-warnings

VM := build/vm

.PHONY: all bundle m4gate goldens bundlecheck vm vmcheck test play clean

all: build/flappy-fb

build dist:
	mkdir -p $@

build/%.s: $(CORE)/src/%.asm $(DEFS) | build
	m4 $(DEFS) $< > $@

build/fb.s: src/fb.asm $(DEFS) | build
	m4 $(DEFS) $< > $@

build/flappy-fb: $(ASM)
	$(CC) $(CFLAGS) $^ -o $@

# one file: the definitions once, the game's sources in core's order, then this presenter
bundle: dist/flappy-fb-bundle.asm
dist/flappy-fb-bundle.asm: $(DEFS) $(CSRC) src/fb.asm | dist
	cat $^ > $@

build/flappy-fb-bundle: dist/flappy-fb-bundle.asm | build
	m4 $< > build/flappy-fb-bundle.s
	$(CC) $(CFLAGS) build/flappy-fb-bundle.s -o $@

m4gate:
	@d=$$(grep -ho 'define([A-Za-z0-9_]*' $(CSRC) src/fb.asm $(DEFS) | sort | uniq -d); \
	if [ -n "$$d" ]; then echo "m4 gate: duplicate names: $$d"; exit 1; fi; \
	echo "m4 gate: every name defined once"

# the game itself is core's: its headless runs must still match core's recorded runs
goldens: build/flappy-fb
	cd build && bash ../$(CORE)/tests/goldens.sh $(RUN) ./flappy-fb

bundlecheck: build/flappy-fb-bundle
	cd build && bash ../$(CORE)/tests/goldens.sh $(RUN) ./flappy-fb-bundle

# the kernel, its modules and busybox from pinned packages, and the initramfs that holds them
vm: $(VM)/initramfs.cpio.gz

$(VM)/initramfs.cpio.gz: build/flappy-fb vm/fetch.sh vm/initramfs.sh vm/init
	bash vm/fetch.sh $(VM)
	bash vm/initramfs.sh $(VM) build/flappy-fb

# boots the VM without a window, checks the picture through QEMU's monitor against core's own
# frames, flaps, then quits
vmcheck: vm build/flappy-ref
	python3 tests/vm-check.py $(VM) build/flappy-ref $(RUN)

# core's terminal build renders the reference frames; it follows core's sources, so moving the
# submodule rebuilds it
build/flappy-ref: $(CSRC) $(CORE)/src/term.asm $(DEFS) | build
	$(MAKE) -C $(CORE) build/flappy
	cp $(CORE)/build/flappy $@

test: m4gate goldens bundlecheck vmcheck

# the game in a QEMU window with a keyboard; the window closing ends it
play: vm
	bash vm/run.sh $(VM)

clean:
	rm -rf build dist
	if [ -f $(CORE)/Makefile ]; then $(MAKE) -C $(CORE) clean; fi

// fb_: the framebuffer presenter. The game draws its whole 144 x 256 picture, and every display
// row that changed goes to /dev/fb0 k times, each pixel k wide, with lseek and write.
// It stands in for the terminal presenter, so it exports what main reads from one: the three
// present_ functions and the bench counters under the terminal presenter's names.

define(fb_back_r, x19)
define(fb_front_r, x20)
define(fb_y_r, x21)
define(fb_k_r, x22)
define(fb_j_r, x23)
define(fb_stride_r, x25)
define(fb_len_r, x26)
define(fb_w_r, x19)
define(fb_h_r, x20)
define(fb_bw_r, x19)
define(fb_bh_r, x20)
define(fb_bp_r, x21)
define(fb_by_r, x22)
define(fb_bo_r, x23)
define(fb_be_r, x24)
define(fb_bl_r, x25)
define(fb_br_r, x26)

// the two ioctls and the fields read here, from include/uapi/linux/fb.h
FB_VSCREENINFO = 0x4600
FB_FSCREENINFO = 0x4602
FB_VINFO_BYTES = 160
FB_FINFO_BYTES = 80
FB_V_XRES = 0
FB_V_YRES = 4
FB_V_BPP = 24
FB_V_RED = 32
FB_V_RED_LEN = 36
FB_V_GREEN = 44
FB_V_GREEN_LEN = 48
FB_V_BLUE = 56
FB_V_BLUE_LEN = 60
FB_V_TRANSP = 68
FB_V_TRANSP_LEN = 72
FB_F_LINE = 48
FB_BPP = 32
FB_PIXEL = 4
FB_CHANNEL_BITS = 8
// the console's mode, from include/uapi/linux/kd.h: graphics keeps its text off the picture
FB_KDSETMODE = 0x4B3A
FB_KD_TEXT = 0
FB_KD_GRAPHICS = 1
FB_O_RDWR = 2
FB_SEEK_SET = 0
FB_STDIN = 0
FB_STDERR = 2
FB_EXIT_NO_FB = 2
// shortcut: k stops at 8 (a 1152 x 2048 picture) and the border is drawn 4096 pixels at a time;
// raise them for a larger screen
FB_K_MAX = 8
FB_ROW_MAX = LOG_W * FB_K_MAX * FB_PIXEL
FB_LINE_PX = 4096
FB_LINE_MAX = FB_LINE_PX * FB_PIXEL
FB_PIX_BYTES = SLOT_COUNT * FB_PIXEL
FB_ROW_WORDS = LOG_W / 8
FB_ROW1 = LOG_W * FB_PIXEL
FB_BORDER_PIX = SLOT_BORDER * FB_PIXEL
present_frame_alloc = -(16 + 64) & -16
present_frame_dealloc = 0 - present_frame_alloc
present_open_alloc = -(16 + 16) & -16
present_open_dealloc = 0 - present_open_alloc
fb_seek_write_alloc = -(16 + 16) & -16
fb_seek_write_dealloc = 0 - fb_seek_write_alloc
fb_seek_write_buf = 16
fb_seek_write_len = 24

        .section .rodata
fb_s_dev:   .asciz  "/dev/fb0"
fb_e_open:
        .ascii  "flappy: no usable /dev/fb0 (it must be 32 bits a pixel)"
        .byte   10
fb_e_open_end:
FB_E_OPEN_LEN = fb_e_open_end - fb_e_open

        .bss
        .balign 16
fb_row:     .skip   FB_ROW_MAX
fb_line:    .skip   FB_LINE_MAX
fb_vinfo:   .skip   FB_VINFO_BYTES
fb_finfo:   .skip   FB_FINFO_BYTES
// the palette as framebuffer pixels, one word per slot
fb_pix:     .skip   FB_PIX_BYTES
        .balign 8
fb_fd:      .skip   8
fb_opened:  .skip   8
fb_k:       .skip   8
fb_ox:      .skip   8
fb_oy:      .skip   8
fb_pitch:   .skip   8
fb_xres:    .skip   8
fb_yres:    .skip   8
fb_last:    .skip   8
fb_full:    .skip   8
fb_bframe:  .skip   8
// the console mode last set, KD_TEXT until a picture is drawn
fb_kd:      .skip   8
        .balign 8
        .global term_total
        .global term_bench
        .global term_bsplit
term_total: .skip   8
term_bench: .skip   8
term_bsplit: .skip  TERM_SPLIT_BYTES

        .text

// fb_fail(): no usable framebuffer: one line on stderr, then exit 2; never returns
        .balign 4
fb_fail:
        stp     fp, lr, [sp, -16]!
        mov     fp, sp
        mov     w0, FB_STDERR
        ldr     x1, =fb_e_open
        mov     x2, FB_E_OPEN_LEN
        bl      tty_write_all
        mov     w0, FB_EXIT_NO_FB
        bl      main_exit

// fb_seek_write(x0 = byte offset in the framebuffer, x1 = buf, x2 = len): one run of pixels;
// a bench counts the bytes instead
        .balign 4
fb_seek_write:
        stp     fp, lr, [sp, fb_seek_write_alloc]!
        mov     fp, sp
        str     x1, [sp, fb_seek_write_buf]
        str     x2, [sp, fb_seek_write_len]
        ldr     x9, =term_total
        ldr     x10, [x9]
        add     x10, x10, x2
        str     x10, [x9]
        ldr     x9, =fb_bframe
        ldr     x10, [x9]
        add     x10, x10, x2
        str     x10, [x9]
        ldr     x9, =term_bench
        ldr     x9, [x9]
        cbnz    x9, fb_seek_write_done
        mov     x1, x0
        ldr     x9, =fb_fd
        ldr     x0, [x9]
        mov     x2, FB_SEEK_SET
        mov     x8, SYS_LSEEK
        svc     0
        ldr     x9, =fb_fd
        ldr     w0, [x9]
        ldr     x1, [sp, fb_seek_write_buf]
        ldr     x2, [sp, fb_seek_write_len]
        bl      tty_write_all
fb_seek_write_done:
        ldp     fp, lr, [sp], fb_seek_write_dealloc
        ret

// present_open(x0 = logical w, x1 = logical h) -> w0 = 1, the scale the game draws at, or 0
// when the framebuffer is smaller than the picture
        .balign 4
        .global present_open
present_open:
        stp     fp, lr, [sp, present_open_alloc]!
        mov     fp, sp
        stp     x19, x20, [sp, 16]
        mov     fb_w_r, x0
        mov     fb_h_r, x1
        ldr     x9, =fb_opened
        ldr     x10, [x9]
        cbnz    x10, present_open_fit
        mov     x0, AT_FDCWD
        ldr     x1, =fb_s_dev
        mov     x2, FB_O_RDWR
        mov     x3, 0
        mov     x8, SYS_OPENAT
        svc     0
        tbnz    x0, 63, present_open_bad
        ldr     x9, =fb_fd
        str     x0, [x9]
        mov     x1, FB_VSCREENINFO
        ldr     x2, =fb_vinfo
        mov     x8, SYS_IOCTL
        svc     0
        tbnz    x0, 63, present_open_bad
        ldr     x9, =fb_fd
        ldr     x0, [x9]
        mov     x1, FB_FSCREENINFO
        ldr     x2, =fb_finfo
        mov     x8, SYS_IOCTL
        svc     0
        tbnz    x0, 63, present_open_bad
        ldr     x9, =fb_vinfo
        ldr     w10, [x9, FB_V_BPP]
        cmp     w10, FB_BPP
        b.ne    present_open_bad
        ldr     w10, [x9, FB_V_XRES]
        ldr     x11, =fb_xres
        str     x10, [x11]
        ldr     w10, [x9, FB_V_YRES]
        ldr     x11, =fb_yres
        str     x10, [x11]
        ldr     x9, =fb_finfo
        ldr     w10, [x9, FB_F_LINE]
        ldr     x11, =fb_pitch
        str     x10, [x11]
        ldr     x9, =fb_opened
        mov     x10, 1
        str     x10, [x9]
present_open_fit:
        // the largest whole k that fits both ways, centred
        ldr     x9, =fb_xres
        ldr     x9, [x9]
        udiv    x10, x9, fb_w_r
        ldr     x11, =fb_yres
        ldr     x11, [x11]
        udiv    x12, x11, fb_h_r
        cmp     x10, x12
        csel    x10, x10, x12, lt
        mov     x12, FB_K_MAX
        cmp     x10, x12
        csel    x10, x10, x12, lt
        ldr     x12, =fb_k
        str     x10, [x12]
        cbz     x10, present_open_none
        mul     x12, fb_w_r, x10
        sub     x12, x9, x12
        lsr     x12, x12, 1
        ldr     x13, =fb_ox
        str     x12, [x13]
        mul     x12, fb_h_r, x10
        sub     x12, x11, x12
        lsr     x12, x12, 1
        ldr     x13, =fb_oy
        str     x12, [x13]
        ldr     x9, =fb_full
        mov     x10, 1
        str     x10, [x9]
        mov     x0, FB_KD_GRAPHICS
        bl      fb_mode
        mov     w0, 1
        b       present_open_done
present_open_none:
        // the game shows why on the console, which must be text again to show it
        mov     x0, FB_KD_TEXT
        bl      fb_mode
        mov     w0, 0
present_open_done:
        ldp     x19, x20, [sp, 16]
        ldp     fp, lr, [sp], present_open_dealloc
        ret
present_open_bad:
        bl      fb_fail

// fb_mode(x0 = KD_TEXT or KD_GRAPHICS): the console's mode, so its text and cursor stay off the
// picture while the game draws and come back when it stops; a bench draws nothing, so it
// leaves the console alone. A failure only means stdin is not a virtual console.
        .balign 4
fb_mode:
        stp     fp, lr, [sp, -16]!
        mov     fp, sp
        ldr     x9, =term_bench
        ldr     x9, [x9]
        cbnz    x9, fb_mode_done
        ldr     x9, =fb_kd
        ldr     x10, [x9]
        cmp     x10, x0
        b.eq    fb_mode_done
        str     x0, [x9]
        mov     x2, x0
        mov     x0, FB_STDIN
        ldr     x1, =FB_KDSETMODE
        mov     x8, SYS_IOCTL
        svc     0
fb_mode_done:
        ldp     fp, lr, [sp], 16
        ret

// fb_pixels(x0 = palette): each slot's R, G, B as a pixel in the framebuffer's own layout
// shortcut: a channel keeps its top length bits, so channels wider than 8 bits come out
// wrong; every 32 bits a pixel framebuffer met so far uses 8
        .balign 4
fb_pixels:
        stp     fp, lr, [sp, -16]!
        mov     fp, sp
        ldr     x9, =fb_vinfo
        ldr     x10, =fb_pix
        // a field the framebuffer marks as transparency is set to all ones: opaque
        ldr     w14, [x9, FB_V_TRANSP]
        ldr     w15, [x9, FB_V_TRANSP_LEN]
        mov     w7, 1
        lsl     w7, w7, w15
        sub     w7, w7, 1
        lsl     w7, w7, w14
        mov     x11, 0
fb_pixels_slot:
        mov     w12, w7
        ldrb    w13, [x0]
        ldr     w14, [x9, FB_V_RED]
        ldr     w15, [x9, FB_V_RED_LEN]
        mov     w1, FB_CHANNEL_BITS
        sub     w1, w1, w15
        lsr     w13, w13, w1
        lsl     w13, w13, w14
        orr     w12, w12, w13
        ldrb    w13, [x0, 1]
        ldr     w14, [x9, FB_V_GREEN]
        ldr     w15, [x9, FB_V_GREEN_LEN]
        mov     w1, FB_CHANNEL_BITS
        sub     w1, w1, w15
        lsr     w13, w13, w1
        lsl     w13, w13, w14
        orr     w12, w12, w13
        ldrb    w13, [x0, 2]
        ldr     w14, [x9, FB_V_BLUE]
        ldr     w15, [x9, FB_V_BLUE_LEN]
        mov     w1, FB_CHANNEL_BITS
        sub     w1, w1, w15
        lsr     w13, w13, w1
        lsl     w13, w13, w14
        orr     w12, w12, w13
        str     w12, [x10], FB_PIXEL
        add     x0, x0, FB_PIXEL
        add     x11, x11, 1
        cmp     x11, SLOT_COUNT
        b.lt    fb_pixels_slot
        ldp     fp, lr, [sp], 16
        ret

// fb_border(): the border colour around the picture, whole lines above and below it and the
// two bands beside it, so the picture never shows the border colour while it is redrawn
fb_border_alloc = -(16 + 64) & -16
fb_border_dealloc = 0 - fb_border_alloc
        .balign 4
fb_border:
        stp     fp, lr, [sp, fb_border_alloc]!
        mov     fp, sp
        stp     x19, x20, [sp, 16]
        stp     x21, x22, [sp, 32]
        stp     x23, x24, [sp, 48]
        stp     x25, x26, [sp, 64]
        ldr     x9, =fb_pix
        ldr     w10, [x9, FB_BORDER_PIX]
        ldr     x9, =fb_xres
        ldr     fb_bw_r, [x9]
        mov     x11, FB_LINE_PX
        cmp     fb_bw_r, x11
        csel    fb_bw_r, fb_bw_r, x11, lt
        ldr     x9, =fb_line
        mov     x11, fb_bw_r
fb_border_px:
        str     w10, [x9], FB_PIXEL
        subs    x11, x11, 1
        b.ne    fb_border_px
        mov     x9, FB_PIXEL
        mul     fb_bw_r, fb_bw_r, x9
        ldr     x9, =fb_yres
        ldr     fb_bh_r, [x9]
        ldr     x9, =fb_pitch
        ldr     fb_bp_r, [x9]
        // the picture's rows and, in bytes, where the bands beside it end and start
        ldr     x9, =fb_k
        ldr     x9, [x9]
        ldr     x10, =fb_oy
        ldr     fb_bo_r, [x10]
        mov     x11, LOG_H
        madd    fb_be_r, x11, x9, fb_bo_r
        ldr     x10, =fb_ox
        ldr     x10, [x10]
        mov     x11, FB_PIXEL
        mul     fb_bl_r, x10, x11
        mov     x12, LOG_W
        madd    x10, x12, x9, x10
        mul     fb_br_r, x10, x11
        mov     fb_by_r, 0
fb_border_line:
        mul     x0, fb_by_r, fb_bp_r
        ldr     x1, =fb_line
        cmp     fb_by_r, fb_bo_r
        b.lt    fb_border_full
        cmp     fb_by_r, fb_be_r
        b.ge    fb_border_full
        mov     x2, fb_bl_r
        bl      fb_seek_write
        mul     x0, fb_by_r, fb_bp_r
        add     x0, x0, fb_br_r
        ldr     x1, =fb_line
        sub     x2, fb_bw_r, fb_br_r
        bl      fb_seek_write
        b       fb_border_next
fb_border_full:
        mov     x2, fb_bw_r
        bl      fb_seek_write
fb_border_next:
        add     fb_by_r, fb_by_r, 1
        cmp     fb_by_r, fb_bh_r
        b.lt    fb_border_line
        ldp     x19, x20, [sp, 16]
        ldp     x21, x22, [sp, 32]
        ldp     x23, x24, [sp, 48]
        ldp     x25, x26, [sp, 64]
        ldp     fp, lr, [sp], fb_border_dealloc
        ret

// present_frame(x0 = back, x1 = stride, x2 = palette, w3 = flags; bit 0 means the palette changed)
        .balign 4
        .global present_frame
present_frame:
        stp     fp, lr, [sp, present_frame_alloc]!
        mov     fp, sp
        stp     x19, x20, [sp, 16]
        stp     x21, x22, [sp, 32]
        stp     x23, x24, [sp, 48]
        stp     x25, x26, [sp, 64]
        mov     fb_back_r, x0
        mov     fb_stride_r, x1
        ldr     x9, =fb_last
        ldr     fb_front_r, [x9]
        // a new palette changes the colour of unchanged pixels too, so it repaints everything,
        // as the first frame and a resize do
        ldr     x9, =fb_full
        ldr     x10, [x9]
        and     w11, w3, 1
        orr     x10, x10, x11
        cbz     x10, present_frame_go
        str     xzr, [x9]
        mov     x0, x2
        bl      fb_pixels
        mov     fb_front_r, 0
        bl      fb_border
present_frame_go:
        ldr     x9, =fb_k
        ldr     fb_k_r, [x9]
        // one display row as framebuffer pixels: each pixel k wide
        mov     x9, FB_ROW1
        mul     fb_len_r, x9, fb_k_r
        mov     fb_y_r, 0
present_frame_row:
        mul     x9, fb_y_r, fb_stride_r
        add     x10, fb_back_r, x9
        cbz     fb_front_r, present_frame_send
        // eight pixels at a time: a row with no change is not written
        add     x11, fb_front_r, x9
        mov     x12, FB_ROW_WORDS
present_frame_cmp:
        ldr     x13, [x10], 8
        ldr     x14, [x11], 8
        cmp     x13, x14
        b.ne    present_frame_changed
        subs    x12, x12, 1
        b.ne    present_frame_cmp
        b       present_frame_next
present_frame_changed:
        add     x10, fb_back_r, x9
present_frame_send:
        ldr     x11, =fb_pix
        ldr     x12, =fb_row
        mov     x13, LOG_W
present_frame_px:
        ldrb    w14, [x10], 1
        ldr     w15, [x11, x14, lsl 2]
        mov     x1, fb_k_r
present_frame_rep:
        str     w15, [x12], FB_PIXEL
        subs    x1, x1, 1
        b.ne    present_frame_rep
        subs    x13, x13, 1
        b.ne    present_frame_px
        mov     fb_j_r, 0
present_frame_line:
        // screen row oy + y * k + j, from column ox
        madd    x9, fb_y_r, fb_k_r, fb_j_r
        ldr     x10, =fb_oy
        ldr     x10, [x10]
        add     x9, x9, x10
        ldr     x10, =fb_pitch
        ldr     x10, [x10]
        mul     x0, x9, x10
        ldr     x10, =fb_ox
        ldr     x10, [x10]
        mov     x11, FB_PIXEL
        madd    x0, x10, x11, x0
        ldr     x1, =fb_row
        mov     x2, fb_len_r
        bl      fb_seek_write
        add     fb_j_r, fb_j_r, 1
        cmp     fb_j_r, fb_k_r
        b.lt    present_frame_line
present_frame_next:
        add     fb_y_r, fb_y_r, 1
        cmp     fb_y_r, LOG_H
        b.lt    present_frame_row
        ldr     x9, =fb_last
        str     fb_back_r, [x9]
        ldp     x19, x20, [sp, 16]
        ldp     x21, x22, [sp, 32]
        ldp     x23, x24, [sp, 48]
        ldp     x25, x26, [sp, 64]
        ldp     fp, lr, [sp], present_frame_dealloc
        ret

// term_bench_take() -> x0 = bytes the bench frame produced, all counted as pixels
        .balign 4
        .global term_bench_take
term_bench_take:
        stp     fp, lr, [sp, -16]!
        mov     fp, sp
        ldr     x9, =fb_bframe
        ldr     x0, [x9]
        str     xzr, [x9]
        ldr     x9, =term_bsplit
        ldr     x10, [x9, TERM_SPLIT_OTHER]
        add     x10, x10, x0
        str     x10, [x9, TERM_SPLIT_OTHER]
        ldp     fp, lr, [sp], 16
        ret

// present_close(): the console back to text, and the framebuffer closed
        .balign 4
        .global present_close
present_close:
        stp     fp, lr, [sp, -16]!
        mov     fp, sp
        ldr     x9, =fb_opened
        ldr     x10, [x9]
        cbz     x10, present_close_done
        str     xzr, [x9]
        mov     x0, FB_KD_TEXT
        bl      fb_mode
        ldr     x9, =fb_fd
        ldr     x0, [x9]
        mov     x8, SYS_CLOSE
        svc     0
present_close_done:
        ldp     fp, lr, [sp], 16
        ret

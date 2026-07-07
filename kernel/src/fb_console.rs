// SPDX-License-Identifier: MPL-2.0

//! Minimal framebuffer console for the aarch64 virtio-gpu display.
//!
//! Renders kernel boot log text directly into the virtio-gpu framebuffer
//! using an embedded 8x8 bitmap font, then flushes to the device. This runs
//! without the heap and without the component system, so it works at the
//! raw boot stage where the virtio-gpu driver initializes.

#![allow(unsafe_code)]
#![allow(dead_code)]

use core::sync::atomic::{AtomicUsize, Ordering};

const CHAR_W: usize = 8;
const CHAR_H: usize = 8;
const COLS: usize = 80;
const ROWS: usize = 60; // 640/8=80 cols, 480/8=60 rows

static CURSOR_COL: AtomicUsize = AtomicUsize::new(0);
static CURSOR_ROW: AtomicUsize = AtomicUsize::new(0);

/// Background (dark blue) and foreground (light green) colors, XRGB8888.
const BG_COLOR: u32 = 0xFF000018;
const FG_COLOR: u32 = 0xFF33FF66;

/// Clear the framebuffer, reset the cursor, and draw a title banner.
pub fn init() {
    clear();
    draw_banner();
}

fn clear() {
    if let Some((fb, w, h, _stride)) = crate::fb_gpu::framebuffer_info() {
        unsafe {
            let p = fb as *mut u32;
            let n = (w as usize) * (h as usize);
            for i in 0..n {
                core::ptr::write_volatile(p.add(i), BG_COLOR);
            }
        }
        crate::fb_gpu::flush_framebuffer();
    }
    CURSOR_COL.store(0, Ordering::Relaxed);
    CURSOR_ROW.store(0, Ordering::Relaxed);
}

fn draw_banner() {
    // Print a header so the user can immediately see the console is live.
    print_str(" kei kernel (aarch64) \n");
    print_str(" virtio-gpu framebuffer console \n\n");
}

/// Public print: write a string, scroll if needed, and flush.
pub fn print_str(s: &str) {
    for &b in s.as_bytes() {
        write_byte(b);
    }
    crate::fb_gpu::flush_framebuffer();
}

pub fn println(s: &str) {
    print_str(s);
    print_str("\n");
}

fn write_byte(byte: u8) {
    match byte {
        b'\n' => {
            CURSOR_COL.store(0, Ordering::Relaxed);
            let r = CURSOR_ROW.fetch_add(1, Ordering::Relaxed) + 1;
            if r >= ROWS {
                scroll();
            }
        }
        b'\r' => {
            CURSOR_COL.store(0, Ordering::Relaxed);
        }
        0x20..=0x7e => {
            let col = CURSOR_COL.load(Ordering::Relaxed);
            let row = CURSOR_ROW.load(Ordering::Relaxed);
            if col < COLS && row < ROWS {
                draw_char(byte, col, row);
            }
            CURSOR_COL.store(col + 1, Ordering::Relaxed);
        }
        _ => {
            // Non-printable: draw a placeholder dot.
            write_byte(b'.');
        }
    }
}

fn scroll() {
    // Move every row up by one (row n+1 → row n), clear the last row.
    if let Some((fb, w, h, _stride)) = crate::fb_gpu::framebuffer_info() {
        let stride = w as usize;
        unsafe {
            let p = fb as *mut u32;
            for y in 0..(h as usize - CHAR_H) {
                for x in 0..stride {
                    let src = (y + CHAR_H) * stride + x;
                    let dst = y * stride + x;
                    core::ptr::write_volatile(p.add(dst), core::ptr::read_volatile(p.add(src)));
                }
            }
            // Clear the bottom CHAR_H rows.
            for y in (h as usize - CHAR_H)..(h as usize) {
                for x in 0..stride {
                    core::ptr::write_volatile(p.add(y * stride + x), BG_COLOR);
                }
            }
        }
    }
    CURSOR_ROW.store(ROWS - 1, Ordering::Relaxed);
}

fn draw_char(byte: u8, col: usize, row: usize) {
    let glyph = font8x8_glyph(byte);
    if let Some((fb, w, _h, _stride)) = crate::fb_gpu::framebuffer_info() {
        let stride = w as usize;
        let x0 = col * CHAR_W;
        let y0 = row * CHAR_H;
        unsafe {
            let p = fb as *mut u32;
            for gy in 0..CHAR_H {
                let bits = glyph[gy];
                for gx in 0..CHAR_W {
                    let on = (bits >> gx) & 1 == 1;
                    let color = if on { FG_COLOR } else { BG_COLOR };
                    let px = x0 + gx;
                    let py = y0 + gy;
                    if px < stride {
                        core::ptr::write_volatile(p.add(py * stride + px), color);
                    }
                }
            }
        }
    }
}

/// 8x8 bitmap font for printable ASCII (code points 0x20..=0x7e).
/// Each glyph is 8 bytes; bit `i` of byte `row` is column i (LSB = leftmost).
/// Derived from the public-domain font8x8 "legacy" BASIC subset.
fn font8x8_glyph(c: u8) -> [u8; 8] {
    // Only 0x20..=0x7e are meaningful; everything else is blank.
    const FONT: [[u8; 8]; 96] = include!("fb_console_font.rs");
    let idx = (c as usize).wrapping_sub(0x20);
    if idx < 96 {
        FONT[idx]
    } else {
        [0; 8]
    }
}

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
const COLS: usize = 160; // 1280/8=160 cols
const ROWS: usize = 100; // 800/8=100 rows

static CURSOR_COL: AtomicUsize = AtomicUsize::new(0);
static CURSOR_ROW: AtomicUsize = AtomicUsize::new(0);

/// The current foreground color for text rendered by `write_byte_color`.
/// Starts as the One Half Dark default foreground; updated by SGR sequences.
static CURRENT_FG: AtomicUsize = AtomicUsize::new(FG_COLOR as usize);

/// Modern dark theme colors (One Half Dark from the kou project), XRGB8888.
const BG_COLOR: u32 = 0xFF282C34; // One Half Dark background
const FG_COLOR: u32 = 0xFFDCDFE4; // One Half Dark foreground (soft white)
const ACCENT_COLOR: u32 = 0xFF61AFEF; // One Half Dark blue accent for banner

/// One Half Dark 16-color ANSI palette, ported from kou's render.rs.
/// Index 0–7 = standard colors, 8–15 = bright variants.
#[rustfmt::skip]
const ANSI_PALETTE: [u32; 16] = [
    0xFF282C34, // 0  Black
    0xFFE06C75, // 1  Red
    0xFF98C379, // 2  Green
    0xFFE5C07B, // 3  Yellow
    0xFF61AFEF, // 4  Blue
    0xFFC678DD, // 5  Magenta
    0xFF56B6C2, // 6  Cyan
    0xFFDCDFE4, // 7  White
    0xFF5A6374, // 8  Bright Black (dim gray)
    0xFFE06C75, // 9  Bright Red
    0xFF98C379, // 10 Bright Green
    0xFFE5C07B, // 11 Bright Yellow
    0xFF61AFEF, // 12 Bright Blue
    0xFFC678DD, // 13 Bright Magenta
    0xFF56B6C2, // 14 Bright Cyan
    0xFFDCDFE4, // 15 Bright White
];

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
    // Print a colorful header using ANSI SGR to demonstrate color support.
    // The SGR codes reference the One Half Dark palette (ported from kou).
    print_str("\x1b[34m kei kernel (aarch64) \x1b[0m\n"); // Blue title
    print_str("\x1b[36m virtio-gpu framebuffer console \x1b[0m\n\n"); // Cyan subtitle
}

/// Public print: write a string with ANSI SGR color support, scroll if needed.
///
/// Parses minimal SGR escape sequences (`\x1b[Nm` and `\x1b[N;Mm`) to set the
/// foreground color from the One Half Dark ANSI palette. This lets kernel boot
/// log messages (which often use ANSI colors via the `log` crate) display in
/// full color on the framebuffer console.
pub fn print_str(s: &str) {
    print_str_ansi(s);
    crate::fb_gpu::flush_framebuffer();
}

/// Internal: parse ANSI escape sequences and render text with the current color.
fn print_str_ansi(s: &str) {
    // Minimal SGR state machine: ESC [ params... m
    #[derive(PartialEq)]
    enum State {
        Normal,
        Escape,   // saw ESC (0x1b)
        Csi,      // saw ESC [
        CsiParam, // accumulating digits after ESC [
    }

    let bytes = s.as_bytes();
    let mut i = 0;
    let mut state = State::Normal;
    let mut param_buf: u32 = 0;
    let mut has_param = false;

    while i < bytes.len() {
        let b = bytes[i];
        match state {
            State::Normal => {
                if b == 0x1b {
                    state = State::Escape;
                } else {
                    write_byte_color(b, CURRENT_FG.load(Ordering::Relaxed) as u32);
                }
            }
            State::Escape => {
                if b == b'[' {
                    state = State::Csi;
                    param_buf = 0;
                    has_param = false;
                } else {
                    // Not a CSI — ignore the ESC and render the byte.
                    state = State::Normal;
                    if b == 0x1b {
                        state = State::Escape;
                    } else {
                        write_byte_color(b, CURRENT_FG.load(Ordering::Relaxed) as u32);
                    }
                }
            }
            State::Csi => {
                if b.is_ascii_digit() {
                    param_buf = param_buf.saturating_mul(10).saturating_add((b - b'0') as u32);
                    has_param = true;
                    state = State::CsiParam;
                } else if b == b'm' {
                    // SGR with no param = reset (SGR 0).
                    if !has_param {
                        CURRENT_FG.store(FG_COLOR as usize, Ordering::Relaxed);
                    }
                    state = State::Normal;
                } else if b == b';' {
                    // Separator — skip (we only handle single-param SGR for fg).
                    state = State::CsiParam;
                } else {
                    // Unknown CSI final byte — swallow the sequence.
                    state = State::Normal;
                }
            }
            State::CsiParam => {
                if b.is_ascii_digit() {
                    param_buf = param_buf.saturating_mul(10).saturating_add((b - b'0') as u32);
                    has_param = true;
                } else if b == b';' {
                    // Multi-param SGR — we only apply the first param for fg color.
                    // Fall through and keep parsing.
                } else if b == b'm' {
                    apply_sgr(param_buf);
                    param_buf = 0;
                    has_param = false;
                    state = State::Normal;
                } else {
                    // Unknown CSI final byte — swallow.
                    state = State::Normal;
                }
            }
        }
        i += 1;
    }
}

/// Apply a single SGR code to the current foreground color.
fn apply_sgr(code: u32) {
    let color = match code {
        0 => Some(FG_COLOR),        // Reset to default fg
        30 => Some(ANSI_PALETTE[0]), // Black
        31 => Some(ANSI_PALETTE[1]), // Red
        32 => Some(ANSI_PALETTE[2]), // Green
        33 => Some(ANSI_PALETTE[3]), // Yellow
        34 => Some(ANSI_PALETTE[4]), // Blue
        35 => Some(ANSI_PALETTE[5]), // Magenta
        36 => Some(ANSI_PALETTE[6]), // Cyan
        37 => Some(ANSI_PALETTE[7]), // White
        39 => Some(FG_COLOR),        // Default fg
        90 => Some(ANSI_PALETTE[8]),  // Bright Black
        91 => Some(ANSI_PALETTE[9]),  // Bright Red
        92 => Some(ANSI_PALETTE[10]), // Bright Green
        93 => Some(ANSI_PALETTE[11]), // Bright Yellow
        94 => Some(ANSI_PALETTE[12]), // Bright Blue
        95 => Some(ANSI_PALETTE[13]), // Bright Magenta
        96 => Some(ANSI_PALETTE[14]), // Bright Cyan
        97 => Some(ANSI_PALETTE[15]), // Bright White
        _ => None, // Unsupported SGR (bold, underline, etc.) — ignore
    };
    if let Some(c) = color {
        CURRENT_FG.store(c as usize, Ordering::Relaxed);
    }
}

/// Print a string with a specific foreground color (bypasses ANSI parsing).
pub fn print_str_color(s: &str, color: u32) {
    for &b in s.as_bytes() {
        write_byte_color(b, color);
    }
    crate::fb_gpu::flush_framebuffer();
}

pub fn println(s: &str) {
    print_str(s);
    print_str("\n");
}

fn write_byte(byte: u8) {
    write_byte_color(byte, CURRENT_FG.load(Ordering::Relaxed) as u32);
}

fn write_byte_color(byte: u8, color: u32) {
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
                draw_char_color(byte, col, row, color);
            }
            CURSOR_COL.store(col + 1, Ordering::Relaxed);
        }
        _ => {
            // Non-printable: draw a placeholder dot.
            write_byte_color(b'.', color);
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
    draw_char_color(byte, col, row, FG_COLOR);
}

fn draw_char_color(byte: u8, col: usize, row: usize, fg: u32) {
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
                    let color = if on { fg } else { BG_COLOR };
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

//! Color conversion — maps alacritty_terminal [`Color`] values to `[R, G, B]` triplets.
//!
//! Defines the standard 16 ANSI system colors as a shared array used by
//! both named-color and 256-color indexed lookups. Also handles the 6×6×6
//! RGB cube (indices 16–231) and the grayscale ramp (232–255).

use alacritty_terminal::vte::ansi::{Color, NamedColor};

use crate::term::CellInfo;

/// The 16 standard ANSI system colors, in indexed order (0–15).
const SYSTEM_COLORS: [[u8; 3]; 16] = [
    [0, 0, 0],       //  0 Black
    [205, 0, 0],     //  1 Red
    [0, 205, 0],     //  2 Green
    [205, 205, 0],   //  3 Yellow
    [0, 0, 238],     //  4 Blue
    [205, 0, 205],   //  5 Magenta
    [0, 205, 205],   //  6 Cyan
    [229, 229, 229], //  7 White
    [127, 127, 127], //  8 Bright Black
    [255, 0, 0],     //  9 Bright Red
    [0, 255, 0],     // 10 Bright Green
    [255, 255, 0],   // 11 Bright Yellow
    [92, 92, 255],   // 12 Bright Blue
    [255, 0, 255],   // 13 Bright Magenta
    [0, 255, 255],   // 14 Bright Cyan
    [255, 255, 255], // 15 Bright White
];

/// Convert an alacritty/vte `Color` to an `[R, G, B]` triplet.
///
/// Named colors use the standard xterm-256color palette. Indexed colors
/// (256-color mode) are approximated. True-color is passed through
/// directly.
pub fn color_to_rgb(color: &Color) -> [u8; 3] {
    match color {
        Color::Named(named) => named_to_rgb(named),
        Color::Spec(rgb) => [rgb.r, rgb.g, rgb.b],
        Color::Indexed(idx) => indexed_to_rgb(*idx),
    }
}

/// Map standard 16 ANSI named colors to approximate RGB values.
fn named_to_rgb(named: &NamedColor) -> [u8; 3] {
    match named {
        NamedColor::Background => CellInfo::DEFAULT_BG,
        NamedColor::Foreground => CellInfo::DEFAULT_FG,
        NamedColor::Black => SYSTEM_COLORS[0],
        NamedColor::Red => SYSTEM_COLORS[1],
        NamedColor::Green => SYSTEM_COLORS[2],
        NamedColor::Yellow => SYSTEM_COLORS[3],
        NamedColor::Blue => SYSTEM_COLORS[4],
        NamedColor::Magenta => SYSTEM_COLORS[5],
        NamedColor::Cyan => SYSTEM_COLORS[6],
        NamedColor::White => SYSTEM_COLORS[7],
        NamedColor::BrightBlack => SYSTEM_COLORS[8],
        NamedColor::BrightRed => SYSTEM_COLORS[9],
        NamedColor::BrightGreen => SYSTEM_COLORS[10],
        NamedColor::BrightYellow => SYSTEM_COLORS[11],
        NamedColor::BrightBlue => SYSTEM_COLORS[12],
        NamedColor::BrightMagenta => SYSTEM_COLORS[13],
        NamedColor::BrightCyan => SYSTEM_COLORS[14],
        NamedColor::BrightWhite => SYSTEM_COLORS[15],
        NamedColor::BrightForeground => SYSTEM_COLORS[15], // same as BrightWhite
        NamedColor::DimBlack => SYSTEM_COLORS[0],
        NamedColor::DimRed => SYSTEM_COLORS[1],
        NamedColor::DimGreen => SYSTEM_COLORS[2],
        NamedColor::DimYellow => SYSTEM_COLORS[3],
        NamedColor::DimBlue => SYSTEM_COLORS[4],
        NamedColor::DimMagenta => SYSTEM_COLORS[5],
        NamedColor::DimCyan => SYSTEM_COLORS[6],
        NamedColor::DimWhite => SYSTEM_COLORS[7],
        // Cursor, ViMode, search match — fall back to default foreground
        _ => CellInfo::DEFAULT_FG,
    }
}

/// Approximate a 256-color palette index to an RGB triplet.
///
/// Colors 0–15 are system colors, 16–231 form a 6×6×6 RGB cube, and
/// 232–255 form a grayscale ramp. This follows the standard xterm
/// 256-color palette.
fn indexed_to_rgb(idx: u8) -> [u8; 3] {
    match idx {
        0..=15 => SYSTEM_COLORS[idx as usize],
        // 16–231: 6×6×6 color cube
        n if n < 232 => {
            let n = n - 16;
            let r = (n / 36) * 51;
            let g = ((n / 6) % 6) * 51;
            let b = (n % 6) * 51;
            [r, g, b]
        }
        // 232–255: grayscale ramp (8 to 238 in steps of 10)
        n => {
            let gray = (n as u16 - 232) * 10 + 8;
            [gray as u8, gray as u8, gray as u8]
        }
    }
}

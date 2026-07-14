class_name Icons

# Single source of truth for all icon glyphs.
# Non-BMP codepoints use char() — GDScript source parser may not handle 4-byte UTF-8 literals.

const CLOSE    = "\u2715"            # U+2715  MULTIPLICATION X
static var DELETE   = char(0x1F5D1) # U+1F5D1 WASTEBASKET
const MINIMIZE = "\u25BC"            # U+25BC  BLACK DOWN-POINTING TRIANGLE
const RESTORE  = "\u25B2"            # U+25B2  BLACK UP-POINTING TRIANGLE
const COLLAPSE = "\u25C0"            # U+25C0  BLACK LEFT-POINTING TRIANGLE
const EXPAND   = "\u25B6"            # U+25B6  BLACK RIGHT-POINTING TRIANGLE
const ADD      = "+"                 # U+002B  PLUS SIGN
const SETTINGS = "\u2699"            # U+2699  GEAR
const RESET    = "\u21BA"            # U+21BA  ANTICLOCKWISE OPEN CIRCLE ARROW
const SWAP     = "\u21C4"            # U+21C4  RIGHTWARDS ARROW OVER LEFTWARDS ARROW

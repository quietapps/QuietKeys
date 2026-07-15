import CoreGraphics

/// Physical ANSI keyboard geometry keyed by macOS virtual key code.
/// `x` is the key-center position normalized 0…1 across the board — used for
/// spatial panning and the visualizer. `row` is 0 (esc row) … 5 (space row).
struct KeyInfo {
    let label: String
    let row: Int
    let x: CGFloat        // normalized 0…1 center
    let width: CGFloat    // in key units (1u, 1.5u, 2.25u …)
}

enum KeyLayout {
    /// Sound class routing: big keys get their own deeper samples.
    static func keyClass(for keyCode: Int64) -> SampleBank.KeyClass {
        switch keyCode {
        case 49: return .space
        case 36, 76: return .return          // return, keypad enter
        case 51, 117: return .delete         // backspace, forward delete
        default: return .default
        }
    }

    /// Stereo pan for a key, -1…+1. Unknown keys sit at center.
    static func pan(for keyCode: Int64) -> Float {
        guard let info = keys[Int(keyCode)] else { return 0 }
        return Float((info.x - 0.5) * 1.6)   // keep extremes off the hard edges
    }

    /// Rows of key codes in physical order, for rendering keyboards.
    /// -1 entries are non-key spacers (unused); widths in key units.
    static let ansiRows: [[(code: Int, label: String, width: CGFloat)]] = [
        [(53, "esc", 1), (122, "F1", 1), (120, "F2", 1), (99, "F3", 1), (118, "F4", 1),
         (96, "F5", 1), (97, "F6", 1), (98, "F7", 1), (100, "F8", 1),
         (101, "F9", 1), (109, "F10", 1), (103, "F11", 1), (111, "F12", 1)],
        [(50, "`", 1), (18, "1", 1), (19, "2", 1), (20, "3", 1), (21, "4", 1),
         (23, "5", 1), (22, "6", 1), (26, "7", 1), (28, "8", 1), (25, "9", 1),
         (29, "0", 1), (27, "-", 1), (24, "=", 1), (51, "⌫", 1.75)],
        [(48, "tab", 1.5), (12, "Q", 1), (13, "W", 1), (14, "E", 1), (15, "R", 1),
         (17, "T", 1), (16, "Y", 1), (32, "U", 1), (34, "I", 1), (31, "O", 1),
         (35, "P", 1), (33, "[", 1), (30, "]", 1), (42, "\\", 1.25)],
        [(57, "caps", 1.75), (0, "A", 1), (1, "S", 1), (2, "D", 1), (3, "F", 1),
         (5, "G", 1), (4, "H", 1), (38, "J", 1), (40, "K", 1), (37, "L", 1),
         (41, ";", 1), (39, "'", 1), (36, "↵", 2)],
        [(56, "shift", 2.25), (6, "Z", 1), (7, "X", 1), (8, "C", 1), (9, "V", 1),
         (11, "B", 1), (45, "N", 1), (46, "M", 1), (43, ",", 1), (47, ".", 1),
         (44, "/", 1), (60, "shift", 2.5)],
        [(59, "⌃", 1.25), (58, "⌥", 1.25), (55, "⌘", 1.5), (49, "␣", 6.25),
         (54, "⌘", 1.5), (61, "⌥", 1.25), (62, "⌃", 1.25)],
    ]

    /// keyCode → geometry, derived from `ansiRows`.
    static let keys: [Int: KeyInfo] = {
        var map: [Int: KeyInfo] = [:]
        for (rowIndex, row) in ansiRows.enumerated() {
            let totalUnits = row.reduce(CGFloat(0)) { $0 + $1.width }
            var cursor: CGFloat = 0
            for key in row {
                let center = (cursor + key.width / 2) / totalUnits
                if map[key.code] == nil {
                    map[key.code] = KeyInfo(label: key.label, row: rowIndex,
                                            x: center, width: key.width)
                }
                cursor += key.width
            }
        }
        // Arrow cluster + navigation: pan hard right.
        for (code, label) in [(123, "←"), (124, "→"), (125, "↓"), (126, "↑"),
                              (115, "home"), (119, "end"), (116, "pgup"),
                              (121, "pgdn"), (117, "⌦")] {
            map[code] = KeyInfo(label: label, row: 5, x: 0.97, width: 1)
        }
        // Keypad: also right side.
        for code in [65, 67, 69, 71, 75, 78, 81, 82, 83, 84, 85, 86, 87, 88, 89,
                     91, 92, 76] {
            if map[code] == nil {
                map[code] = KeyInfo(label: "num", row: 3, x: 0.97, width: 1)
            }
        }
        return map
    }()
}

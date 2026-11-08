import AppKit
import Carbon.HIToolbox

/// The current keyboard layout, read through Text Input Sources.
public enum KeyboardLayout {
    /// The key that types `character` in the current keyboard layout, so ⌘V is ⌘V on Dvorak
    /// and AZERTY too. Nil if the layout can't be read.
    public static func virtualKey(for character: Character) -> CGKeyCode? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let pointer = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(pointer).takeUnretainedValue() as Data
        return virtualKey(for: character, layoutData: data)
    }

    /// `virtualKey(for:)` against a given `uchr` layout (tests pass a fixed one).
    public static func virtualKey(for character: Character, layoutData data: Data) -> CGKeyCode? {
        let target = String(character)
        return data.withUnsafeBytes { raw -> CGKeyCode? in
            guard let layout = raw.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return nil }
            for code in 0..<128 {
                var deadKeys: UInt32 = 0
                var length = 0
                var chars = [UniChar](repeating: 0, count: 4)
                let status = UCKeyTranslate(layout, UInt16(code), UInt16(kUCKeyActionDisplay), 0,
                                            UInt32(LMGetKbdType()), OptionBits(kUCKeyTranslateNoDeadKeysBit),
                                            &deadKeys, chars.count, &length, &chars)
                if status == noErr, length > 0, String(utf16CodeUnits: chars, count: length) == target {
                    return CGKeyCode(code)
                }
            }
            return nil
        }
    }

    /// The physical key for a command shortcut (⌘V, ⌘C) in the current layout, falling back
    /// to the ANSI position when the layout can't be read.
    public static func commandKey(_ character: Character, fallback: Int) -> CGKeyCode {
        virtualKey(for: character) ?? CGKeyCode(fallback)
    }
}

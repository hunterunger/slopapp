import Foundation

/// Folds text for search: lowercase, compatibility-decomposed, combining marks removed.
/// "Zürich" → "zurich", "São Paulo" → "sao paulo", "ＴＯＫＹＯ" → "tokyo".
///
/// Must match `fold()` in Tools/build-cities.py, which pre-folds the bundled search keys.
public enum SearchFolding {
    public static func fold(_ text: String) -> String {
        let decomposed = text.lowercased().decomposedStringWithCompatibilityMapping
        var scalars = String.UnicodeScalarView()
        for scalar in decomposed.unicodeScalars where scalar.properties.generalCategory != .nonspacingMark {
            scalars.append(scalar)
        }
        return String(scalars).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

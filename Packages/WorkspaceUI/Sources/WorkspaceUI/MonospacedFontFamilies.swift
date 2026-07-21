import AppKit

/// Installed monospaced font families, for the Preferences font picker.
/// Constraining the picker (not just the persisted value) to monospaced
/// families keeps `settings.json`'s `fontFamily` meaningful for a
/// code/text editor even on a fresh install with no hand-editing.
enum MonospacedFontFamilies {
    static var installed: [String] {
        NSFontManager.shared.availableFontFamilies.filter { family in
            guard let members = NSFontManager.shared.availableMembers(ofFontFamily: family),
                  let firstMemberName = members.first?[0] as? String,
                  let sampleFont = NSFont(name: firstMemberName, size: 12)
            else { return false }
            return sampleFont.isFixedPitch
        }.sorted()
    }
}

import Foundation

extension String {
    /// Substring search that will not match in the middle of a word.
    ///
    /// Plain `contains` is wrong for identifying software, because a command line
    /// is mostly filesystem paths. `/bin/ng` appears inside `/bin/ngrok` and
    /// `/bin/nginx`, and `.bin/vite` appears inside `.bin/vitepress`. Both would
    /// otherwise produce a confident, completely wrong label.
    ///
    /// A match counts only when the characters immediately around it are not
    /// word characters. A needle that already ends in a separator, such as
    /// `/nuxt/bin/`, needs no trailing check.
    func containsToken(_ needle: String) -> Bool {
        guard !needle.isEmpty else { return false }

        let checkLeading = needle.first.map(Self.isWordCharacter) ?? false
        let checkTrailing = needle.last.map(Self.isWordCharacter) ?? false

        var searchStart = startIndex
        while let found = range(of: needle, range: searchStart..<endIndex) {
            let leadingIsBoundary = !checkLeading
                || found.lowerBound == startIndex
                || !Self.isWordCharacter(self[index(before: found.lowerBound)])
            let trailingIsBoundary = !checkTrailing
                || found.upperBound == endIndex
                || !Self.isWordCharacter(self[found.upperBound])

            if leadingIsBoundary && trailingIsBoundary { return true }
            guard found.lowerBound < endIndex else { return false }
            searchStart = index(after: found.lowerBound)
        }
        return false
    }

    /// Characters that continue a name. `.` and `/` are excluded so `vite` still
    /// matches `vite.mjs` and `/vite`, while `vitest` and `vite-node` do not.
    private static func isWordCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "-" || character == "_"
    }
}

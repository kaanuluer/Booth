import Foundation

enum MediaPath {
    static let allowedWriteExtensions: Set<String> = [
        "m4a", "aac", "wav", "aiff", "aif", "caf", "mp3", "jpg", "jpeg", "png"
    ]

    static func leafName(_ filename: String) -> String? {
        let name = (filename as NSString).lastPathComponent
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != ".", name != ".." else { return nil }
        if name.contains("/") || name.contains("\\") { return nil }
        if name.hasPrefix(".") { return nil }
        if name.unicodeScalars.contains(where: { $0.value < 32 || $0.value == 127 }) { return nil }
        return name
    }

    static func sanitizeForWrite(_ filename: String) -> String {
        let leaf = leafName(filename) ?? "audio.m4a"
        var ext = (leaf as NSString).pathExtension.lowercased()
        if !allowedWriteExtensions.contains(ext) {
            ext = "m4a"
        }
        let base = ((leaf as NSString).deletingPathExtension as NSString).lastPathComponent
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let filtered = String(base.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" })
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        let clipped = String(filtered.prefix(64))
        let safeBase = clipped.isEmpty ? "ses" : clipped
        return "\(safeBase).\(ext)"
    }

    static func resolve(root: URL, filename: String) -> URL? {
        guard let name = leafName(filename) else { return nil }
        let rootStd = root.standardizedFileURL
        let candidate = rootStd.appendingPathComponent(name, isDirectory: false).standardizedFileURL
        guard isInside(candidate, root: rootStd) else { return nil }
        return candidate
    }

    static func isInside(_ url: URL, root: URL) -> Bool {
        let filePath = url.resolvingSymlinksInPath().standardizedFileURL.path
        let rootPath = root.resolvingSymlinksInPath().standardizedFileURL.path
        guard filePath != rootPath else { return false }
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        return filePath.hasPrefix(prefix)
    }

    static func isRegularFile(_ url: URL) -> Bool {
        let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .isDirectoryKey])
        return values?.isRegularFile == true
            && values?.isSymbolicLink != true
            && values?.isDirectory != true
    }

    static func exportBasename(_ raw: String, fileExtension: String) -> String {
        let leaf = (raw as NSString).lastPathComponent
        let withoutExt = (leaf as NSString).deletingPathExtension
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_ ."))
        let filtered = String(withoutExt.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" })
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let clipped = String(filtered.prefix(80))
        let ext = allowedWriteExtensions.contains(fileExtension.lowercased()) ? fileExtension.lowercased() : "m4a"
        let safe = (clipped.isEmpty || clipped == "." || clipped == "..") ? "bolum" : clipped
        return safe + "." + ext
    }

    static func protect(_ url: URL) {
        try? (url as NSURL).setResourceValue(
            URLFileProtection.completeUntilFirstUserAuthentication,
            forKey: .fileProtectionKey
        )
    }
}

extension URL {
    func boothFile(_ filename: String) -> URL? {
        MediaPath.resolve(root: self, filename: filename)
    }
}

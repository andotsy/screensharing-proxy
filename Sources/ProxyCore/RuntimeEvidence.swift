import Foundation

enum RuntimeEvidence {
    static func family(_ path: String) -> String? {
        let name = URL(fileURLWithPath: path).lastPathComponent.lowercased()
        for family in ["python", "ruby"] {
            if name.range(of: "^" + family + #"(?:[0-9]+(?:\.[0-9]+){0,2})?(?:\.app)?$"#,
                          options: .regularExpression) != nil { return family }
        }
        return nil
    }

    static func bundleExecutable(_ data: Data) -> String? {
        guard data.count <= 262_144,
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let name = plist["CFBundleExecutable"] as? String,
              !name.isEmpty, name != ".", name != "..", name.utf8.count <= 255,
              !name.contains("/"), !name.utf8.contains(0) else { return nil }
        return name
    }
}

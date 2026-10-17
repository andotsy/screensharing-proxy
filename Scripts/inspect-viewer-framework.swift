// Read metadata from the system framework loaded from the dyld shared cache.
// No private methods are called and no Screen Sharing session is started.
import Darwin
import Foundation
import MachO

let path = "/System/Library/PrivateFrameworks/ScreenSharing.framework/Versions/A/ScreenSharing"
guard let handle = dlopen(path, RTLD_LAZY | RTLD_LOCAL) else {
    print("ScreenSharing framework unavailable")
    exit(0)
}
defer { dlclose(handle) }
let expression = try NSRegularExpression(pattern:
    "port.?base|udp|rtcp|loopback|localhost|sockname|peername|media.{0,20}(port|address)|(?:local|remote|peer).{0,20}(port|address)|bind.{0,15}(port|socket)",
    options: [.caseInsensitive])
for index in 0..<_dyld_image_count() {
    guard let name = _dyld_get_image_name(index), String(cString: name) == path,
          let header = _dyld_get_image_header(index) else { continue }
    let header64 = UnsafeRawPointer(header).assumingMemoryBound(to: mach_header_64.self)
    guard header64.pointee.magic == MH_MAGIC_64 else { continue }
    for section in ["__cstring", "__objc_methname", "__objc_classname"] {
        var size: UInt = 0
        guard let bytes = getsectiondata(header64, "__TEXT", section, &size), size <= 16 * 1024 * 1024 else { continue }
        let strings = Data(bytes: bytes, count: Int(size)).split(separator: 0)
        var count = 0
        print("SECTION \(section)")
        for bytes in strings {
            guard let text = String(data: Data(bytes), encoding: .utf8), text.utf8.count <= 2048,
                  expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil else { continue }
            print(text)
            count += 1
            if count >= 150 { break }
        }
    }
}

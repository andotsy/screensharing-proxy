// Read metadata from the system framework loaded from the dyld shared cache.
// No private methods are called and no Screen Sharing session is started.
import Darwin
import Foundation
import MachO
import ObjectiveC

func describeSymbol(_ address: UInt) -> String {
    guard let pointer = UnsafeRawPointer(bitPattern: address) else { return "unknown" }
    var info = Dl_info()
    guard dladdr(pointer, &info) != 0, let name = info.dli_sname else { return "unknown" }
    return String(cString: name)
}

let path = "/System/Library/PrivateFrameworks/ScreenSharing.framework/Versions/A/ScreenSharing"
guard let handle = dlopen(path, RTLD_LAZY | RTLD_LOCAL) else {
    print("ScreenSharing framework unavailable")
    exit(0)
}

// Inspect one socket-creation method without invoking it. Limit reads to the
// framework's executable section, and emit only this method's short code prefix.
if let cls = NSClassFromString("SSSession"),
   let method = class_getClassMethod(cls, NSSelectorFromString("udpSocketWithAVCMediaStreamConfig:port:")) {
    let bits = unsafeBitCast(method_getImplementation(method), to: UInt.self)
    let address = bits & 0x0000_ffff_ffff_ffff // Strip arm64e authentication bits for inspection.
    for index in 0..<_dyld_image_count() {
        guard let name = _dyld_get_image_name(index), String(cString: name) == path,
              let header = _dyld_get_image_header(index) else { continue }
        let header64 = UnsafeRawPointer(header).assumingMemoryBound(to: mach_header_64.self)
        var size: UInt = 0
        guard let text = getsectiondata(header64, "__TEXT", "__text", &size) else { continue }
        let start = UInt(bitPattern: text)
        guard address >= start, address < start + size,
              let code = UnsafeRawPointer(bitPattern: address) else { continue }
        let count = min(2048, Int(start + size - address))
        let record: [String: Any] = [
            "method": "SSSession.udpSocketWithAVCMediaStreamConfig:port:",
            "address": String(address, radix: 16),
            "encoding": method_getTypeEncoding(method).map { String(cString: $0) } ?? "unknown",
            "code": Data(bytes: code, count: count).base64EncodedString()
        ]
        print("METHOD " + String(data: try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]), encoding: .utf8)!)
        // Resolve the method's direct calls and show only bounded stub prefixes.
        // Addresses must lie inside a known executable section of this image.
        var executableRanges: [Range<UInt>] = []
        for section in ["__text", "__stubs", "__auth_stubs", "__objc_stubs"] {
            var length: UInt = 0
            if let bytes = getsectiondata(header64, "__TEXT", section, &length), length <= 32 * 1024 * 1024 {
                let begin = UInt(bitPattern: bytes)
                executableRanges.append(begin..<(begin + length))
            }
        }
        var targets = Set<UInt>()
        for offset in stride(from: 0, to: count - 3, by: 4) {
            let instruction = code.load(fromByteOffset: offset, as: UInt32.self)
            if instruction == 0xd65f0fff || instruction == 0xd65f03c0 { break } // retab / ret
            guard instruction & 0xfc00_0000 == 0x9400_0000 else { continue } // bl imm26
            let displacement = Int64(Int32(bitPattern: (instruction & 0x03ff_ffff) << 6) >> 4)
            let target = UInt(Int64(address) + Int64(offset) + displacement)
            guard targets.count < 48, targets.insert(target).inserted,
                  let range = executableRanges.first(where: { $0.contains(target) }),
                  let pointer = UnsafeRawPointer(bitPattern: target) else { continue }
            let prefix = min(32, Int(range.upperBound - target))
            let call: [String: Any] = [
                "address": String(target, radix: 16), "symbol": describeSymbol(target),
                "code": Data(bytes: pointer, count: prefix).base64EncodedString()
            ]
            print("CALLEE " + String(data: try JSONSerialization.data(withJSONObject: call, options: [.sortedKeys]), encoding: .utf8)!)
        }
        for symbol in ["socket", "bind", "connect", "setsockopt", "getsockname", "getpeername", "close"] {
            if let pointer = dlsym(handle, symbol) {
                print("SYMBOL \(symbol) \(String(UInt(bitPattern: pointer) & 0x0000_ffff_ffff_ffff, radix: 16))")
            }
        }
    }
}
defer { dlclose(handle) }
let expression = try NSRegularExpression(pattern:
    "port.?base|udp|rtcp|loopback|localhost|sockname|peername|media.{0,20}(port|address)|(?:local|remote|peer).{0,20}(port|address)|(?:bind|connect).{0,15}(port|socket)|address.{0,15}use",
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

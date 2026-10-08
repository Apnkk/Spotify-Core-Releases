import UIKit
import Orion

struct HookTargetNameHelper {
    static var lyricsScrollProvider: String {
        switch EeveeSpotify.hookTarget {
        case .lastAvailableiOS14, .v91:
            return "Lyrics_CoreImpl.ScrollProvider"
        default:
            return "Lyrics_NPVCommunicatorImpl.ScrollProvider"
        }
    }
}

// Swift classes register in the ObjC runtime lazily, so NSClassFromString at
// tweak-init time can miss classes that exist. Brute-force the registered class list
// as a fallback, cached after the first scan so every activation lookup shares one pass.
private var classListByNameCache: [String: AnyClass] = [:]
private var classListByNameCacheBuilt = false

func findTweakClass(_ name: String) -> AnyClass? {
    if let cls = NSClassFromString(name) { return cls }
    if classListByNameCacheBuilt { return classListByNameCache[name] }
    let total = objc_getClassList(nil, 0)
    guard total > 0 else { return nil }
    let buf = UnsafeMutablePointer<AnyClass>.allocate(capacity: Int(total))
    defer { buf.deallocate() }
    let n = objc_getClassList(AutoreleasingUnsafeMutablePointer<AnyClass>(buf), total)
    for i in 0..<Int(n) {
        let raw = UnsafeRawPointer(buf).load(fromByteOffset: i * MemoryLayout<UnsafeRawPointer>.size,
                                              as: UnsafeRawPointer.self)
        let cls = unsafeBitCast(raw, to: AnyClass.self)
        classListByNameCache[String(cString: class_getName(cls))] = cls
    }
    classListByNameCacheBuilt = true
    return classListByNameCache[name]
}


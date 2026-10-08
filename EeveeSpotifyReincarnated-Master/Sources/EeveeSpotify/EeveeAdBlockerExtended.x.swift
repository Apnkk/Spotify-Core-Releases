// TESTING: extended ad blocker for Swift Service-based ad surfaces
// (Evo home brand-ads, NPV under-player ad, in-stream audio, native ads).
// Hooks SPTService -load on each ad service and skips orig so the service
// stays inert. Per-surface bool flips below if one needs disabling.

import Orion
import Foundation
import UIKit

// Every service has its own group. Spotify rolls these modules out
// independently, so one missing/renamed class must not disable the rest of the
// blocker on sideloaded/rootless builds either.
struct AdsServiceImplGroup: HookGroup {}
struct InStreamAdsServiceGroup: HookGroup {}
struct EmbeddedNPVServiceGroup: HookGroup {}
struct LeavebehindAdsBaseServiceGroup: HookGroup {}
struct LeavebehindAdsBaseInternalServiceGroup: HookGroup {}
struct SponsoredContextServiceGroup: HookGroup {}
struct SponsoredContextNPBAttachmentServiceGroup: HookGroup {}
struct SponsoredPlaylistHeaderServiceGroup: HookGroup {}
struct SponsoredPlaylistHeaderViewGroup: HookGroup {}
struct NativeAdsLoggerServiceGroup: HookGroup {}
struct SponsoredCtxAttachmentGroup: HookGroup {}
struct RealTimeAdControllerServiceGroup: HookGroup {}
struct EmbeddedPlaylistServiceGroup: HookGroup {}
struct EmbeddedAdControllerServiceGroup: HookGroup {}
struct EmbeddedCTAElementsServiceGroup: HookGroup {}
struct AdsInstrumentationServiceGroup: HookGroup {}
struct AdsIdentityTrackingSessionServiceGroup: HookGroup {}

private let killAdsServiceImpl         = true
private let killInStreamAdsService     = true
private let killEmbeddedNPVService     = true
private let killNativeAdsLoggerService = true
private let killSponsoredCtxAttachment = true
private let logAdBlockerEvents         = true

@inline(__always)
private func adlog(_ what: String) {
    if logAdBlockerEvents { NSLog("[EeveeSpotify][AdBlock] suppressed %@", what) }
}

class AdsServiceImplKill: ClassHook<NSObject> {
    typealias Group = AdsServiceImplGroup
    static let targetName: String = "_TtC19AdsPlatform_AdsImpl14AdsServiceImpl"
    func load() {
        if killAdsServiceImpl { adlog("AdsServiceImpl.load"); return }
        orig.load()
    }
}

class InStreamAdsServiceKill: ClassHook<NSObject> {
    typealias Group = InStreamAdsServiceGroup
    static let targetName: String = "_TtC29AdsNowPlaying_InStreamAdsImpl18InStreamAdsService"
    func load() {
        if killInStreamAdsService { adlog("InStreamAdsService.load"); return }
        orig.load()
    }
}

class EmbeddedNPVServiceImplKill: ClassHook<NSObject> {
    typealias Group = EmbeddedNPVServiceGroup
    static let targetName: String = "_TtC29AdsNowPlaying_EmbeddedNPVImpl22EmbeddedNPVServiceImpl"
    func load() {
        if killEmbeddedNPVService { adlog("EmbeddedNPVServiceImpl.load"); return }
        orig.load()
    }
}

// Spotify 9.1.66+ can render the under-player card through a separate
// "unified leavebehind" pipeline. It does not depend on EmbeddedNPVServiceImpl.
class LeavebehindAdsBaseServiceKill: ClassHook<NSObject> {
    typealias Group = LeavebehindAdsBaseServiceGroup
    static let targetName: String =
        "_TtC36AdsStandalone_LeavebehindAdsBaseImpl25LeavebehindAdsBaseService"

    func load() {
        adlog("LeavebehindAdsBaseService.load")
        return
    }
}

class LeavebehindAdsBaseInternalServiceKill: ClassHook<NSObject> {
    typealias Group = LeavebehindAdsBaseInternalServiceGroup
    static let targetName: String =
        "_TtC36AdsStandalone_LeavebehindAdsBaseImpl33LeavebehindAdsBaseInternalService"

    func load() {
        adlog("LeavebehindAdsBaseInternalService.load")
        return
    }
}

// Native sponsored surfaces are separate from AdsServiceImpl in 9.1.x.
// Blocking their SPTService entry points keeps sponsored headers and the
// Now Playing Bar attachment from being constructed at all.
class SponsoredContextServiceKill: ClassHook<NSObject> {
    typealias Group = SponsoredContextServiceGroup
    static let targetName =
        "_TtC35AdsEmbedded_AdsSponsoredContextImpl30AdsSponsoredContextServiceImpl"

    func load() {
        adlog("AdsSponsoredContextServiceImpl.load")
        return
    }
}

class SponsoredContextNPBAttachmentServiceKill: ClassHook<NSObject> {
    typealias Group = SponsoredContextNPBAttachmentServiceGroup
    static let targetName =
        "_TtC48AdsEmbedded_AdsSponsoredContextNPBAttachmentImpl43AdsSponsoredContextNPBAttachmentServiceImpl"

    func load() {
        adlog("AdsSponsoredContextNPBAttachmentServiceImpl.load")
        return
    }
}

class SponsoredPlaylistHeaderServiceKill: ClassHook<NSObject> {
    typealias Group = SponsoredPlaylistHeaderServiceGroup
    static let targetName =
        "_TtC42AdsEmbedded_AdsSponsoredPlaylistHeaderImpl37AdsSponsoredPlaylistHeaderServiceImpl"

    func load() {
        adlog("AdsSponsoredPlaylistHeaderServiceImpl.load")
        return
    }
}

// Rendering fallback for a sponsored header that was already materialized
// before its service hook became active. Generic Spotify banners stay intact.
class SponsoredPlaylistHeaderViewKill: ClassHook<UIView> {
    typealias Group = SponsoredPlaylistHeaderViewGroup
    static let targetName =
        "_TtC18AdsPlatform_ECMKit37AdsSponsoredPlaylistHeaderCentralView"

    func didMoveToSuperview() {
        orig.didMoveToSuperview()
        target.isHidden = true
        target.isUserInteractionEnabled = false
        if target.superview != nil {
            adlog("AdsSponsoredPlaylistHeaderCentralView")
            target.removeFromSuperview()
        }
    }
}

class NativeAdsLoggerServiceImplKill: ClassHook<NSObject> {
    typealias Group = NativeAdsLoggerServiceGroup
    static let targetName: String = "_TtC20NativeAds_LoggerImpl26NativeAdsLoggerServiceImpl"
    func load() {
        if killNativeAdsLoggerService { adlog("NativeAdsLoggerServiceImpl.load"); return }
        orig.load()
    }
}

class RealTimeAdControllerServiceKill: ClassHook<NSObject> {
    typealias Group = RealTimeAdControllerServiceGroup
    static let targetName: String = "_TtC36AdsPlatform_RealTimeAdControllerImpl31RealTimeAdControllerServiceImpl"
    func load() {
        adlog("RealTimeAdControllerServiceImpl.load")
        return
    }
}

class EmbeddedPlaylistServiceKill: ClassHook<NSObject> {
    typealias Group = EmbeddedPlaylistServiceGroup
    static let targetName: String = "_TtC32AdsEmbedded_EmbeddedPlaylistImpl27EmbeddedPlaylistServiceImpl"
    func load() {
        adlog("EmbeddedPlaylistServiceImpl.load")
        return
    }
}

class EmbeddedAdControllerServiceKill: ClassHook<NSObject> {
    typealias Group = EmbeddedAdControllerServiceGroup
    static let targetName: String = "_TtC36AdsEmbedded_EmbeddedAdControllerImpl31EmbeddedAdControllerServiceImpl"
    func load() {
        adlog("EmbeddedAdControllerServiceImpl.load")
        return
    }
}

class EmbeddedCTAElementsServiceKill: ClassHook<NSObject> {
    typealias Group = EmbeddedCTAElementsServiceGroup
    static let targetName: String = "_TtC35AdsEmbedded_EmbeddedCTAElementsImpl30EmbeddedCTAElementsServiceImpl"
    func load() {
        adlog("EmbeddedCTAElementsServiceImpl.load")
        return
    }
}

class AdsInstrumentationServiceKill: ClassHook<NSObject> {
    typealias Group = AdsInstrumentationServiceGroup
    static let targetName: String = "_TtC34AdsPlatform_AdsInstrumentationImpl29AdsInstrumentationServiceImpl"
    func load() {
        adlog("AdsInstrumentationServiceImpl.load")
        return
    }
}

class AdsIdentityTrackingSessionServiceKill: ClassHook<NSObject> {
    typealias Group = AdsIdentityTrackingSessionServiceGroup
    static let targetName: String = "_TtC35AdsPlatform_AdsIdentityTrackingImpl33AdsIdentityTrackingSessionService"
    func load() {
        adlog("AdsIdentityTrackingSessionService.load")
        return
    }
}

// Passive log only — returning nil from init would crash the alloc chain.
// Upstream events are starved by killing AdsServiceImpl above.
class SponsoredCtxAttachmentProbe: ClassHook<NSObject> {
    typealias Group = SponsoredCtxAttachmentGroup
    static let targetName: String =
        "_TtC48AdsEmbedded_AdsSponsoredContextNPBAttachmentImpl25AdModelChangedEventSource"
    func `init`() -> Target {
        if killSponsoredCtxAttachment {
            adlog("SponsoredCtxAttachment.init (passive)")
        }
        return orig.`init`()
    }
}

func activateEeveeAdBlockerExtended() {
    let loadSelector = Selector(("load"))
    let initSelector = Selector(("init"))

    let loadTargets: [(String, String, () -> Void)] = [
        (AdsServiceImplKill.targetName, "AdsServiceImpl", { AdsServiceImplGroup().activate() }),
        (InStreamAdsServiceKill.targetName, "InStreamAdsService", { InStreamAdsServiceGroup().activate() }),
        (EmbeddedNPVServiceImplKill.targetName, "EmbeddedNPVServiceImpl", { EmbeddedNPVServiceGroup().activate() }),
        (LeavebehindAdsBaseServiceKill.targetName, "LeavebehindAdsBaseService", { LeavebehindAdsBaseServiceGroup().activate() }),
        (LeavebehindAdsBaseInternalServiceKill.targetName, "LeavebehindAdsBaseInternalService", { LeavebehindAdsBaseInternalServiceGroup().activate() }),
        (SponsoredContextServiceKill.targetName, "AdsSponsoredContextServiceImpl", { SponsoredContextServiceGroup().activate() }),
        (SponsoredContextNPBAttachmentServiceKill.targetName, "AdsSponsoredContextNPBAttachmentServiceImpl", { SponsoredContextNPBAttachmentServiceGroup().activate() }),
        (SponsoredPlaylistHeaderServiceKill.targetName, "AdsSponsoredPlaylistHeaderServiceImpl", { SponsoredPlaylistHeaderServiceGroup().activate() }),
        (NativeAdsLoggerServiceImplKill.targetName, "NativeAdsLoggerServiceImpl", { NativeAdsLoggerServiceGroup().activate() }),
        (RealTimeAdControllerServiceKill.targetName, "RealTimeAdControllerServiceImpl", { RealTimeAdControllerServiceGroup().activate() }),
        (EmbeddedPlaylistServiceKill.targetName, "EmbeddedPlaylistServiceImpl", { EmbeddedPlaylistServiceGroup().activate() }),
        (EmbeddedAdControllerServiceKill.targetName, "EmbeddedAdControllerServiceImpl", { EmbeddedAdControllerServiceGroup().activate() }),
        (EmbeddedCTAElementsServiceKill.targetName, "EmbeddedCTAElementsServiceImpl", { EmbeddedCTAElementsServiceGroup().activate() }),
        (AdsInstrumentationServiceKill.targetName, "AdsInstrumentationServiceImpl", { AdsInstrumentationServiceGroup().activate() }),
        (AdsIdentityTrackingSessionServiceKill.targetName, "AdsIdentityTrackingSessionService", { AdsIdentityTrackingSessionServiceGroup().activate() }),
    ]

    var activated = 0
    for (className, label, activate) in loadTargets {
        guard let cls = NSClassFromString(className),
              class_getInstanceMethod(cls, loadSelector) != nil else {
            NSLog("[EeveeSpotify][AdBlock] %@/load unavailable; skipping", label)
            continue
        }
        activate()
        activated += 1
        NSLog("[EeveeSpotify][AdBlock] %@ hook activated", label)
    }

    if let cls = NSClassFromString(SponsoredCtxAttachmentProbe.targetName),
       class_getInstanceMethod(cls, initSelector) != nil {
        SponsoredCtxAttachmentGroup().activate()
        activated += 1
        NSLog("[EeveeSpotify][AdBlock] SponsoredCtxAttachment hook activated")
    } else {
        NSLog("[EeveeSpotify][AdBlock] SponsoredCtxAttachment/init unavailable; skipping")
    }

    let viewSelector = Selector(("didMoveToSuperview"))
    if let cls = NSClassFromString(SponsoredPlaylistHeaderViewKill.targetName) as? UIView.Type,
       class_getInstanceMethod(cls, viewSelector) != nil {
        SponsoredPlaylistHeaderViewGroup().activate()
        activated += 1
        NSLog("[EeveeSpotify][AdBlock] SponsoredPlaylistHeader view fallback activated")
    } else {
        NSLog("[EeveeSpotify][AdBlock] SponsoredPlaylistHeader view unavailable; skipping")
    }

    NSLog("[EeveeSpotify][AdBlock] activated %d/%d compatible extended hooks",
          activated, loadTargets.count + 2)
}

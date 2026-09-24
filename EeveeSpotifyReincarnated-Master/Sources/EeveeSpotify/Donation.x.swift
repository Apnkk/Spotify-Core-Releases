import Foundation
import UIKit

/// Easter egg: on the 5th and 10th app launch, show a tappable toast
/// "Hysan's Elsa Recovery Fund: $0 raised. Be the first to contribute ☕"
/// Tapping the action button opens the donation page.
enum Donation {

    private static let launchCountKey = "hysanRecoveryFundLaunchCount"
    private static let hasShownKey = "hysanRecoveryFundShown"
    private static let donationURL = URL(string: "https://ko-fi.com/jaydenjcpy")!
    private static let showOnLaunches: Set<Int> = [5, 10]

    /// Disabled: completely silenced, no donation prompts or toasts
    static func activate() {
        return
    }

    private static func showToast() {
        SponsorBlockToast.shared.show(
            message: "☕ Hysan's Elsa Recovery Fund: $0 raised",
            actions: [
                SponsorBlockToastAction(
                    systemImage: "cup.and.saucer.fill",
                    style: .primary,
                    tintOverride: UIColor(red: 1.0, green: 0.6, blue: 0.8, alpha: 1.0),
                    handler: {
                        UIApplication.shared.open(donationURL, options: [:], completionHandler: nil)
                    }
                )
            ],
            duration: 8.0
        )
    }
}

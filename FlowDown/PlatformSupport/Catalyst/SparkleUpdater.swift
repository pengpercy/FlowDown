//
//  SparkleUpdater.swift
//  FlowDown
//

#if targetEnvironment(macCatalyst)

    import Foundation
    import ObjectiveC

    /// Drives Sparkle, which checks the fork's GitHub releases for a newer
    /// build, shows its notes, then downloads, installs and relaunches it.
    ///
    /// Sparkle is an AppKit framework, so a Catalyst target cannot link it.
    /// The release script copies `Sparkle.framework` into the app instead and
    /// this loads it at launch and talks to it through the Objective-C
    /// runtime. Builds without the framework (Xcode runs) return `nil` from
    /// `shared` and fall back to the release-page check in `UpdateManager`.
    final class SparkleUpdater: NSObject {
        static let shared = SparkleUpdater(hostBundle: .main)

        /// Each architecture has its own feed, since a release ships one DMG
        /// per CPU and Sparkle installs the single archive an item names.
        static var feedURL: String {
            #if DEBUG
                // Lets a local build try an update against a feed on this Mac.
                if let override = ProcessInfo.processInfo.environment["FLOWDOWN_FEED_URL"] {
                    return override
                }
            #endif
            #if arch(arm64)
                let arch = "arm64"
            #else
                let arch = "x86_64"
            #endif
            return "https://github.com/pengpercy/FlowDown/releases/latest/download/appcast-\(arch).xml"
        }

        private var controller: NSObject?

        private init?(hostBundle: Bundle) {
            guard let frameworks = hostBundle.privateFrameworksURL,
                  let sparkle = Bundle(url: frameworks.appendingPathComponent("Sparkle.framework")),
                  sparkle.load(),
                  NSClassFromString("SPUStandardUpdaterController") != nil
            else {
                Logger.app.infoFile("Sparkle is not embedded; using the release page check")
                return nil
            }
            super.init()
        }

        /// Creates and starts the updater. Sparkle schedules its own
        /// background checks from here, honoring `SUEnableAutomaticChecks`.
        func start() {
            guard controller == nil,
                  let controllerClass = NSClassFromString("SPUStandardUpdaterController") as? NSObject.Type
            else { return }

            typealias Initializer = @convention(c) (
                AnyObject, Selector, Bool, AnyObject?, AnyObject?,
            ) -> NSObject?
            let selector = NSSelectorFromString("initWithStartingUpdater:updaterDelegate:userDriverDelegate:")
            guard let allocated = controllerClass.perform(NSSelectorFromString("alloc"))?.takeUnretainedValue(),
                  let method = class_getInstanceMethod(controllerClass, selector)
            else { return }
            let initialize = unsafeBitCast(method_getImplementation(method), to: Initializer.self)
            controller = initialize(allocated, selector, true, self, nil)
            Logger.app.infoFile("Sparkle started with feed \(Self.feedURL)")
        }

        /// Shows Sparkle's window for a check the user asked for.
        func checkForUpdates() {
            controller?.perform(NSSelectorFromString("checkForUpdates:"), with: nil)
        }

        // MARK: - SPUUpdaterDelegate

        @objc(feedURLStringForUpdater:)
        func feedURLString(for _: AnyObject) -> String? {
            Self.feedURL
        }
    }

#endif

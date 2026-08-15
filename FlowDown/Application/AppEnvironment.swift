//
//  AppEnvironment.swift
//  FlowDown
//
//  Created by OpenAI Code Assistant on 2/17/25.
//

import Foundation
import Security
import Storage

/// Centralizes core services so they can be swapped (for previews/tests) without touching global singletons.
nonisolated enum AppEnvironment {
    nonisolated struct Container {
        nonisolated let storage: Storage
        nonisolated let syncEngine: SyncEngine
    }

    private static var containerStack: [Container] = []

    nonisolated static var isBootstrapped: Bool {
        !containerStack.isEmpty
    }

    nonisolated static var current: Container {
        guard let container = containerStack.last else {
            fatalError("Call AppEnvironment.bootstrap(_) before accessing dependencies.")
        }
        return container
    }

    @discardableResult
    nonisolated static func bootstrap(_ container: Container) -> Container {
        containerStack = [container]
        apply(container)
        return container
    }

    nonisolated static func push(_ container: Container) {
        containerStack.append(container)
        apply(container)
    }

    nonisolated static func pop() {
        guard containerStack.count > 1 else {
            assertionFailure("Attempted to pop the root AppEnvironment container.")
            return
        }
        _ = containerStack.popLast()
        if let container = containerStack.last {
            apply(container)
        }
    }

    private nonisolated static func apply(_ container: Container) {
        Storage.setSyncEngine(container.syncEngine)
    }
}

nonisolated extension AppEnvironment.Container {
    nonisolated static func live() throws -> AppEnvironment.Container {
        let storage = try Storage.db()
        let isRunningTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil

        // Sideloaded / ad-hoc builds have no iCloud entitlement. Creating a
        // live CKContainer then traps in CloudKit. Fall back to mock sync.
        let shouldEnableCloudSync = processHasICloudServicesEntitlement()
            && SyncEngine.isCloudSyncSupported(containerIdentifier: CloudKitConfig.containerIdentifier)
        let shouldUseMockSync = isRunningTests || !shouldEnableCloudSync
        if !shouldEnableCloudSync || shouldUseMockSync {
            SyncEngine.setSyncEnabled(false)
        }

        let mode: SyncEngine.Mode = shouldUseMockSync ? .mock : .live
        let automaticallySync = shouldUseMockSync ? false : shouldEnableCloudSync

        #if DEBUG
            let infoDic = Bundle.main.infoDictionary
            let value = infoDic?["UIApplicationSupportsMultipleScenes"] as? Bool
            assert(value == false)
        #endif

        let syncEngine = SyncEngine(
            storage: storage,
            containerIdentifier: CloudKitConfig.containerIdentifier,
            mode: mode,
            automaticallySync: automaticallySync,
        )
        return .init(storage: storage, syncEngine: syncEngine)
    }
}

/// True when this process was signed with CloudKit. Ad-hoc verification
/// builds omit that restricted entitlement, so live sync must not start.
private nonisolated func processHasICloudServicesEntitlement() -> Bool {
    #if targetEnvironment(macCatalyst)
        guard let task = SecTaskCreateFromSelf(nil) else { return false }
        var error: Unmanaged<CFError>?
        let value = SecTaskCopyValueForEntitlement(
            task,
            "com.apple.developer.icloud-services" as CFString,
            &error,
        )
        error?.release()
        return value != nil
    #elseif targetEnvironment(simulator)
        // SecTask entitlement APIs are unavailable to iOS Simulator. Tests use
        // mock sync, so treating the simulator as unsigned is both correct and
        // prevents a CloudKit container from being created during test setup.
        return false
    #else
        // Keep the existing iOS-device behavior. The SecTask entitlement APIs
        // are macOS/Catalyst-only, while App Store-signed iOS builds continue
        // to use their configured CloudKit container.
        return true
    #endif
}

/// Convenience accessors to keep existing call sites small.
nonisolated var sdb: Storage {
    AppEnvironment.current.storage
}

nonisolated var syncEngine: SyncEngine {
    AppEnvironment.current.syncEngine
}

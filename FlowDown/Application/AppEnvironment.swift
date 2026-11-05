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

    private static var container: Container?

    nonisolated static var isBootstrapped: Bool {
        container != nil
    }

    nonisolated static var current: Container {
        guard let container else {
            fatalError("Call AppEnvironment.bootstrap(_) before accessing dependencies.")
        }
        return container
    }

    nonisolated static func bootstrap(_ newValue: Container) {
        container = newValue
        Storage.setSyncEngine(newValue.syncEngine)
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
        if shouldUseMockSync {
            SyncEngine.setSyncEnabled(false)
        }

        let mode: SyncEngine.Mode = shouldUseMockSync ? .mock : .live

        #if DEBUG
            let infoDic = Bundle.main.infoDictionary
            let value = infoDic?["UIApplicationSupportsMultipleScenes"] as? Bool
            assert(value == false)
        #endif

        let syncEngine = SyncEngine(
            storage: storage,
            containerIdentifier: CloudKitConfig.containerIdentifier,
            mode: mode,
            automaticallySync: !shouldUseMockSync,
        )
        return .init(storage: storage, syncEngine: syncEngine)
    }
}

/// True when this process was signed with CloudKit. Ad-hoc verification
/// builds omit that restricted entitlement, so live sync must not start.
private nonisolated func processHasICloudServicesEntitlement() -> Bool {
    guard let task = SecTaskCreateFromSelf(nil) else { return false }
    var error: Unmanaged<CFError>?
    let value = SecTaskCopyValueForEntitlement(
        task,
        "com.apple.developer.icloud-services" as CFString,
        &error,
    )
    error?.release()
    return value != nil
}

/// Convenience accessors to keep existing call sites small.
nonisolated var sdb: Storage {
    AppEnvironment.current.storage
}

nonisolated var syncEngine: SyncEngine {
    AppEnvironment.current.syncEngine
}

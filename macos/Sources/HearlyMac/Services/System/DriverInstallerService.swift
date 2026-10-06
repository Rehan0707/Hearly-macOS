import AppKit
import Foundation

enum DriverInstallerError: LocalizedError {
    case notBundled
    case couldNotOpen

    var errorDescription: String? {
        switch self {
        case .notBundled:
            return "This app build does not include the Hearly driver installer. Build the full Hearly Xcode scheme to package it."
        case .couldNotOpen:
            return "macOS could not open the Hearly driver installer."
        }
    }
}

struct DriverInstallerService {
    private var installerURL: URL? {
        Bundle.main.url(forResource: "HearlyDriverInstaller", withExtension: "pkg")
    }

    var isAvailable: Bool { installerURL != nil }

    func open() throws {
        guard let installerURL else { throw DriverInstallerError.notBundled }
        guard NSWorkspace.shared.open(installerURL) else { throw DriverInstallerError.couldNotOpen }
    }
}

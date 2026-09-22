//
//  Logging.swift
//  Shared
//

import OSLog

extension Logger {
    private static let subsystem = Bundle.main.bundleIdentifier ?? ""
    private static let diagnosticsEnabled = ProcessInfo.processInfo.environment["ICE_DIAGNOSTICS"] == "1"

    /// Creates a logger using the specified category.
    init(category: String) {
        self.init(subsystem: Self.subsystem, category: category)
    }

    /// Logs diagnostic information when explicitly enabled.
    func diagnostic(_ message: @autoclosure () -> String) {
        guard Self.diagnosticsEnabled else {
            return
        }
        let diagnosticMessage = message()
        debug("[diag] \(diagnosticMessage, privacy: .public)")
    }
}

// MARK: - Shared Loggers

extension Logger {
    /// The default logger.
    static let `default` = Logger(.default)

    /// The logger for hotkey operations.
    static let hotkeys = Logger(category: "Hotkeys")

    /// The logger for menu bar appearance overlay panels.
    static let overlayPanel = Logger(category: "OverlayPanel")

    /// The logger for serialization operations.
    static let serialization = Logger(category: "Serialization")
}

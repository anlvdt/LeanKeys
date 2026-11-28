import Foundation

/// Permission and layout checks shared by `typist --check` and the run itself.
public enum Preflight {
    public static let accessibilityPath = "System Settings > Privacy & Security > Accessibility"
    public static let inputMonitoringPath = "System Settings > Privacy & Security > Input Monitoring"

    /// nil when typist can type and see real input; otherwise one message for the user.
    /// Permission messages always name both Accessibility and Input Monitoring.
    public static func problem(accessibilityTrusted: Bool, tapCreated: Bool, layoutID: String) -> String? {
        if !accessibilityTrusted || !tapCreated {
            return "typist: give this terminal Accessibility and Input Monitoring in "
                + "\(accessibilityPath) and \(inputMonitoringPath), then retry."
        }
        if !Guard.layoutAccepted(layoutID) {
            return "typist: the keyboard layout is \(layoutID), not U.S. or ABC. Switch the input source to U.S. or ABC first."
        }
        return nil
    }
}

/// What the window title says about the bench page.
public enum PageState: Equatable {
    case ready
    case error
    case other

    public static func of(title: String?, token: String) -> PageState {
        guard let title, !token.isEmpty else { return .other }
        if title.contains("webbench-\(token)-ready") { return .ready }
        if title.contains("webbench-\(token)-error") { return .error }
        return .other
    }
}

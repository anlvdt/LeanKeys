import Foundation

/// The update row of the status popover (spec §16.2): what it shows and what a click on it does.
/// Pure, so the app's `UpdateManager` state is mirrored into `Source` and decided here.
public enum PopoverUpdateRow {
    /// A mirror of the app's `UpdateState` (which lives in the app target, out of reach of the tests).
    public enum Source: Equatable {
        case idle
        case checking
        case available
        /// `progress` as reported; it is negative or above 1 when the server sends no size.
        case downloading(progress: Double)
        case readyToInstall
        case upToDate
        /// The message `UpdateManager` stored. Only `Failure.from(message:)` reads it; it is never shown.
        case error(String)
    }

    public enum Failure: Equatable {
        case network, download, install

        /// What `UpdateManager` stores for a failed install started from the popover.
        public static let installMessage = "Không cài được bản mới"

        /// Gõ Nhanh's download errors ("Tải về thất bại", "Không thể lưu bản cập nhật") and the popover install
        /// message are recognised; anything else came from `UpdateChecker`, i.e. the check itself failed.
        public static func from(message: String) -> Failure {
            switch message {
            case installMessage: return .install
            case "Tải về thất bại", "Không thể lưu bản cập nhật": return .download
            default: return .network
            }
        }
    }

    public enum Phase: Equatable {
        case idle
        case checking
        /// nil when the size is unknown (an indeterminate bar).
        case downloading(progress: Double?)
        case installing
        case ready
        case upToDate
        case failed(Failure)
    }

    public enum TapAction: Equatable {
        case check, install
    }

    /// `installRequested` is set while a check, download or install the user started from the popover is running.
    public static func phase(source: Source, installRequested: Bool) -> Phase {
        switch source {
        case .idle: return .idle
        case .checking: return .checking
        // A click on "Kiểm tra cập nhật" starts the download at once; `.available` only lasts until then.
        // Without that click it is the legacy window's offer, with nothing downloaded yet: the row offers the check.
        case .available: return installRequested ? .downloading(progress: nil) : .idle
        case let .downloading(progress): return .downloading(progress: clamp(progress))
        case .readyToInstall: return installRequested ? .installing : .ready
        case .upToDate: return .upToDate
        case let .error(message): return .failed(Failure.from(message: message))
        }
    }

    /// A fraction in 0...1, or nil when it is not one (unknown size, NaN).
    public static func clamp(_ progress: Double) -> Double? {
        guard progress.isFinite, progress >= 0, progress <= 1 else { return nil }
        return progress
    }

    /// The one status line, or nil when the row is just a button.
    public static func line(_ phase: Phase) -> String? {
        switch phase {
        case .idle, .ready: return nil
        case .checking: return "Đang kiểm tra cập nhật…"
        case let .downloading(progress):
            guard let progress else { return "Đang tải bản mới…" }
            return "Đang tải bản mới… \(Int((progress * 100).rounded(.down)))%"
        case .installing: return "Đang cài, LeanKeys sẽ tự mở lại"
        case .upToDate: return "Bạn đang dùng bản mới nhất"
        case .failed(.network): return "Không kết nối được, thử lại sau"
        case .failed(.download): return "Tải bản mới thất bại"
        case .failed(.install): return Failure.installMessage
        }
    }

    public static func buttonTitle(_ phase: Phase) -> String? {
        switch phase {
        case .idle: return "Kiểm tra cập nhật"
        case .ready: return "Cài bản mới"
        case .failed: return "Thử lại"
        case .checking, .downloading, .installing, .upToDate: return nil
        }
    }

    public static func tapAction(_ phase: Phase) -> TapAction? {
        switch phase {
        case .idle, .failed: return .check
        case .ready: return .install
        case .checking, .downloading, .installing, .upToDate: return nil
        }
    }

    public static func isBusy(_ phase: Phase) -> Bool {
        switch phase {
        case .checking, .downloading, .installing: return true
        case .idle, .ready, .upToDate, .failed: return false
        }
    }
}

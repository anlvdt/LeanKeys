import AppKit
import SwiftUI

/// LeanKeys' one-screen welcome (spec §13.3): a single button to grant Accessibility, nothing else to choose.
/// Polls `isTrusted` every second; once it turns true, shows the done line and calls `onDone` once, about a second
/// later. No 4B toggle yet (ruling R22). A returning user (`wasTrusted`) whose grant was lost to an update gets the
/// re-grant steps instead of the welcome (ruling R24).
public struct LeanOnboardingView: View {
    enum Strings {
        static let title = "Chào mừng đến với LeanKeys"
        static let message = "Chỉ cần cấp quyền Trợ năng một lần, sau đó cứ thế gõ — LeanKeys tự chuyển Việt/Anh cho bạn."
        static let returningTitle = "LeanKeys vừa được cập nhật"
        static let returningMessage = "macOS cần bạn cấp lại quyền Trợ năng: mở Cài đặt Trợ năng, chọn LeanKeys, bấm nút \u{2212} để xoá, rồi bấm + và thêm lại LeanKeys."
        static let openSettings = "Cấp quyền Trợ năng"
        static let done = "Xong! Bạn có thể bắt đầu gõ."

        /// Title and body: the re-grant steps once Accessibility had been granted before, else the welcome.
        static func copy(wasTrusted: Bool) -> (title: String, message: String) {
            wasTrusted ? (returningTitle, returningMessage) : (title, message)
        }
    }

    private let isTrusted: () -> Bool
    private let openSettings: () -> Void
    private let onDone: () -> Void
    private let wasTrusted: Bool

    @State private var trusted = false
    @State private var finished = false

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    /// `wasTrusted`: `ReturningUser.wasTrusted()`, read once when the window opens.
    public init(isTrusted: @escaping () -> Bool, openSettings: @escaping () -> Void, onDone: @escaping () -> Void,
                wasTrusted: Bool = false)
    {
        self.isTrusted = isTrusted
        self.openSettings = openSettings
        self.onDone = onDone
        self.wasTrusted = wasTrusted
    }

    public var body: some View {
        VStack(spacing: 16) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 72, height: 72)
            Text(Strings.copy(wasTrusted: wasTrusted).title)
                .font(.system(size: 18, weight: .semibold))
            Text(Strings.copy(wasTrusted: wasTrusted).message)
                .font(.system(size: 13))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            if trusted {
                Label(Strings.done, systemImage: "checkmark.circle.fill")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.green)
            } else {
                Button(Strings.openSettings, action: openSettings)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
        }
        .padding(28)
        .frame(width: 420)
        .onAppear(perform: poll)
        .onReceive(timer) { _ in poll() }
    }

    private func poll() {
        guard !trusted else { return }
        trusted = isTrusted()
        guard trusted, !finished else { return }
        finished = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { onDone() }
    }
}

/// Remembers that this Mac had granted LeanKeys Accessibility once, so a later onboarding (the grant lost to an
/// ad-hoc signed update) explains the re-grant instead of welcoming a new user.
public enum ReturningUser {
    public static let wasTrustedKey = "LeanKeys.wasTrusted"

    /// Sets "LeanKeys.wasTrusted" when `isTrusted`; never clears it.
    public static func record(isTrusted: Bool, defaults: UserDefaults = .standard) {
        if isTrusted { defaults.set(true, forKey: wasTrustedKey) }
    }

    public static func wasTrusted(defaults: UserDefaults = .standard) -> Bool {
        defaults.bool(forKey: wasTrustedKey)
    }
}

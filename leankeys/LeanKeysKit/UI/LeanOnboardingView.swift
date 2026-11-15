import AppKit
import SwiftUI

/// LeanKeys' one-screen welcome (spec §13.3): a single button to grant Accessibility, nothing else to choose.
/// Polls `isTrusted` every second; once it turns true, shows the done line and calls `onDone` once, about a second
/// later. No 4B toggle yet (ruling R22).
public struct LeanOnboardingView: View {
    enum Strings {
        static let title = "Chào mừng đến với LeanKeys"
        static let message = "Chỉ cần cấp quyền Trợ năng một lần, sau đó cứ thế gõ — LeanKeys tự chuyển Việt/Anh cho bạn."
        static let openSettings = "Mở cài đặt Trợ năng"
        static let done = "Xong! Bạn có thể bắt đầu gõ."
    }

    private let isTrusted: () -> Bool
    private let openSettings: () -> Void
    private let onDone: () -> Void

    @State private var trusted = false
    @State private var finished = false

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    public init(isTrusted: @escaping () -> Bool, openSettings: @escaping () -> Void, onDone: @escaping () -> Void) {
        self.isTrusted = isTrusted
        self.openSettings = openSettings
        self.onDone = onDone
    }

    public var body: some View {
        VStack(spacing: 16) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 72, height: 72)
            Text(Strings.title)
                .font(.system(size: 18, weight: .semibold))
            Text(Strings.message)
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

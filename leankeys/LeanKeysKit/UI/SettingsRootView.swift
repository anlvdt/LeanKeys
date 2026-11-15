import AppKit
import Combine
import SwiftUI

/// The four pages of the LeanKeys settings window (spec §14.3).
public enum SettingsPage: CaseIterable {
    case general, shortcuts, advanced, about

    public var title: String {
        switch self {
        case .general: return "Chung"
        case .shortcuts: return "Phím tắt"
        case .advanced: return "Nâng cao"
        case .about: return "Giới thiệu"
        }
    }

    public var symbol: String {
        switch self {
        case .general: return "gearshape"
        case .shortcuts: return "keyboard"
        case .advanced: return "wrench.and.screwdriver"
        case .about: return "info.circle"
        }
    }

    /// Maps the page names Gõ Nhanh's `NavigationPage` stored, so a legacy request opens the matching page.
    public init?(legacyRawValue: String) {
        switch legacyRawValue {
        case "Cài đặt": self = .general
        case "Nâng cao": self = .advanced
        case "Giới thiệu": self = .about
        default: return nil
        }
    }
}

/// Settings window root: a 200 pt sidebar (logo, name, version, badge, page list) beside the selected page.
public struct SettingsRootView: View {
    private let logo: NSImage
    private let name: String
    private let version: String
    private let badge: AnyView
    private let pageViews: [SettingsPage: AnyView]
    private let pageRequests: AnyPublisher<SettingsPage, Never>

    @State private var selected: SettingsPage = .general
    @Environment(\.colorScheme) private var colorScheme

    public init(
        logo: NSImage,
        name: String,
        version: String,
        badge: AnyView,
        general: AnyView,
        shortcuts: AnyView,
        advanced: AnyView,
        about: AnyView,
        pageRequests: AnyPublisher<SettingsPage, Never>
    ) {
        self.logo = logo
        self.name = name
        self.version = version
        self.badge = badge
        self.pageViews = [.general: general, .shortcuts: shortcuts, .advanced: advanced, .about: about]
        self.pageRequests = pageRequests
    }

    public var body: some View {
        HStack(spacing: 0) {
            sidebar
                .frame(width: 200)
                .frame(maxHeight: .infinity)
                .background(SettingsVisualEffect(material: .sidebar))

            ScrollView {
                pageViews[selected, default: AnyView(EmptyView())]
                    .padding(28)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(contentBackground)
        }
        .frame(width: 700, height: 480)
        .ignoresSafeArea()
        .onReceive(pageRequests) { selected = $0 }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Image(nsImage: logo)
                    .resizable()
                    .frame(width: 48, height: 48)
                Text(name)
                    .font(.system(size: 15, weight: .bold))
                Text("v\(version)")
                    .font(.system(size: 11))
                    .foregroundColor(Color(NSColor.secondaryLabelColor))
                badge
            }
            .padding(.horizontal, 16)
            .padding(.top, 28)

            List(SettingsPage.allCases, id: \.self, selection: Binding(
                get: { selected },
                set: { if let page = $0 { selected = page } }
            )) { page in
                Label(page.title, systemImage: page.symbol)
            }
            .listStyle(.sidebar)
        }
    }

    @ViewBuilder
    private var contentBackground: some View {
        if colorScheme == .dark {
            SettingsVisualEffect(material: .headerView)
        } else {
            Color(NSColor.windowBackgroundColor)
        }
    }
}

/// Wraps `NSVisualEffectView` so SwiftUI can draw the sidebar and dark content materials.
private struct SettingsVisualEffect: NSViewRepresentable {
    let material: NSVisualEffectView.Material

    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = material
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ view: NSVisualEffectView, context: Context) {
        view.material = material
    }
}

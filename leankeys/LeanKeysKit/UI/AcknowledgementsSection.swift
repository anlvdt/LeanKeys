import AppKit
import SwiftUI

/// LeanKeys' block on Gõ Nhanh's About page: the engine versions and a credit line per source project.
public struct AcknowledgementsSection: View {
    static let licenseLine = "\(LeanBranding.name) phát hành theo giấy phép \(LeanAcknowledgements.leanKeysLicense) · "
    static let creditsLink = "Xem ghi công"

    public init() {}

    public var body: some View {
        VStack(spacing: 6) {
            Text(LeanVersions.engineLine)
                .font(.system(size: 11))
                .foregroundColor(Color(NSColor.secondaryLabelColor))
            ForEach(LeanAcknowledgements.credits) { credit in
                HStack(spacing: 4) {
                    if let url = URL(string: credit.repository) {
                        Link(credit.name, destination: url)
                    } else {
                        Text(credit.name)
                    }
                    Text("· \(credit.authors) · \(credit.license)")
                        .foregroundColor(Color(NSColor.secondaryLabelColor))
                }
                .font(.system(size: 11))
            }
            if let url = URL(string: LeanBranding.repository + "/blob/main/ACKNOWLEDGEMENTS.md") {
                // Only "Xem ghi công" is the link; the licence sentence is plain text.
                HStack(spacing: 0) {
                    Text(Self.licenseLine)
                    Link(Self.creditsLink, destination: url)
                }
                .font(.system(size: 11))
            }
        }
        .multilineTextAlignment(.center)
    }
}

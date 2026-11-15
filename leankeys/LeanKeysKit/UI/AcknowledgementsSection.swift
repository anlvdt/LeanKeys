import AppKit
import SwiftUI

/// LeanKeys' block on Gõ Nhanh's About page: the engine versions and a credit line per source project.
public struct AcknowledgementsSection: View {
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
                        .foregroundColor(Color(NSColor.tertiaryLabelColor))
                }
                .font(.system(size: 11))
            }
            if let url = URL(string: LeanBranding.repository + "/blob/main/ACKNOWLEDGEMENTS.md") {
                Link("\(LeanBranding.name) phát hành theo \(LeanAcknowledgements.leanKeysLicense) · Xem ghi công", destination: url)
                    .font(.system(size: 11))
            }
        }
        .multilineTextAlignment(.center)
    }
}

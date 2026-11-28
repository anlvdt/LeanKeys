import AppKit
import SwiftUI

public enum PredictionSettingsPart {
    /// Toggle row on Cài đặt › Chung.
    case general
    /// Detailed card on Cài đặt › Nâng cao.
    case advanced
}

/// Settings UI for 4A+ Laban Key-style word/phrase/sentence suggestions (spec 2026-11-28-prediction-4a).
public struct PredictionSettingsSection: View {
    public static let title = "Gợi ý từ & câu tiếp theo"
    public static let subtitle = "Hiện chữ gợi ý mờ ngay dưới con trỏ khi tạm dừng gõ (Tab, ⌥1–⌥3)"
    public static let learnTitle = "Học thói quen viết để gợi ý cụm từ & câu"
    public static let learnSubtitle = "Cá nhân hoá gợi ý theo cách bạn hay nhắn tin và viết bài"
    public static let consentTitle = "Cho LeanKeys học thói quen gợi ý câu?"
    public static let consentText = "LeanKeys sẽ học các cặp từ, cụm từ và câu bạn hay gõ để gợi ý từ, cụm từ và câu tiếp theo sát hơn. Dữ liệu chỉ nằm trên máy này, được mã hoá, không bao giờ gửi đi đâu. Không học trong ô mật khẩu, terminal, trình soạn code và các app bạn loại trừ. Bạn xem và xoá được bất cứ lúc nào."
    public static let consentConfirm = "Cho phép"
    public static let consentCancel = "Không"
    public static let eraseLabel = "Xoá dữ liệu gợi ý"
    public static let eraseConfirmTitle = "Xoá dữ liệu gợi ý đã học?"
    public static let eraseConfirmMessage = "Mọi cặp từ và cụm câu cá nhân đã học sẽ bị xoá. Kho từ tiếng Việt có sẵn vẫn giữ nguyên."
    public static let eraseConfirm = "Xoá"

    @ObservedObject private var model: PredictionController
    private let part: PredictionSettingsPart
    @State private var confirmErase = false

    public init(model: PredictionController, part: PredictionSettingsPart) {
        self.model = model
        self.part = part
    }

    public var body: some View {
        switch part {
        case .general: generalRow
        case .advanced: advancedCard
        }
    }

    private var generalRow: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(Self.title).font(.system(size: 13))
                Text(Self.subtitle)
                    .font(.system(size: 11))
                    .foregroundColor(Color(NSColor.secondaryLabelColor))
                    .lineLimit(1)
                    .help(Self.subtitle)
            }
            Spacer()
            Toggle("", isOn: Binding(get: { model.enabled }, set: { model.setEnabled($0) }))
                .toggleStyle(.switch)
                .controlSize(.mini)
                .labelsHidden()
                .accessibilityLabel(Text(Self.title))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var advancedCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(Self.title)
                .font(.system(size: 13, weight: .medium))
                .padding(.horizontal, 12)
                .padding(.top, 10)
                .padding(.bottom, 4)

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Hiện thanh gợi ý khi gõ").font(.system(size: 13))
                    Text("Bấm Tab chọn gợi ý đầu, ⌥1–⌥3 chọn nhanh, Esc để ẩn")
                        .font(.system(size: 11))
                        .foregroundColor(Color(NSColor.secondaryLabelColor))
                        .lineLimit(1)
                }
                Spacer()
                Toggle("", isOn: Binding(get: { model.enabled }, set: { model.setEnabled($0) }))
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .labelsHidden()
                    .accessibilityLabel(Text("Hiện thanh gợi ý khi gõ"))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider().padding(.leading, 12)

            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(Self.learnTitle).font(.system(size: 13))
                    Text(Self.learnSubtitle)
                        .font(.system(size: 11))
                        .foregroundColor(Color(NSColor.secondaryLabelColor))
                        .lineLimit(1)
                        .help(Self.learnSubtitle)
                }
                Spacer()
                Toggle("", isOn: Binding(get: { model.learnEnabled }, set: { model.setLearnEnabled($0) }))
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .labelsHidden()
                    .accessibilityLabel(Text(Self.learnTitle))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)

            Divider().padding(.leading, 12)

            HStack(spacing: 8) {
                Button(Self.eraseLabel) { confirmErase = true }
                    .controlSize(.small)
                    .disabled(model.learnedBigramCount == 0 && model.learnedPhraseCount == 0)
                Spacer()
                if model.learnedBigramCount > 0 || model.learnedPhraseCount > 0 {
                    Text("Đã học \(model.learnedBigramCount) cặp từ · \(model.learnedPhraseCount) cụm/câu")
                        .font(.system(size: 11))
                        .foregroundColor(Color(NSColor.secondaryLabelColor))
                        .monospacedDigit()
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(NSColor.controlBackgroundColor).opacity(0.5)))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(NSColor.separatorColor).opacity(0.5), lineWidth: 0.5))
        .alert(Self.consentTitle, isPresented: Binding(get: { model.learnConsentPending },
                                                       set: { if !$0 { model.cancelLearnConsent() } })) {
            Button(Self.consentConfirm) { model.confirmLearnConsent() }
            Button(Self.consentCancel, role: .cancel) { model.cancelLearnConsent() }
        } message: {
            Text(Self.consentText)
        }
        .alert(Self.eraseConfirmTitle, isPresented: $confirmErase) {
            Button(Self.eraseConfirm, role: .destructive) { model.eraseLearnedData() }
            Button(Self.consentCancel, role: .cancel) {}
        } message: {
            Text(Self.eraseConfirmMessage)
        }
    }
}

import Foundation
import XCTest
@testable import LeanKeysKit

/// The suggestion bench (design 2026-11-24): a made-up month of office and chat typing, run through the learner,
/// the ranking and the trigger names, with the engine. Made-up text only, never the user's data.
///
/// Before the redesign, by this test's own measures, this month gave 18 suggestions: 6 of the `shortChat` replies,
/// 4 variants of one thank-you line, 9 of 16 phrase triggers over five letters, numbered or blocked (dektlrbas,
/// decoacdqta, eco2, cl…), and both sentences below taken for addresses. After: 9, 0, 2, 0 of 6, 0.
final class SuggestionBenchTests: XCTestCase {
    private final class MemStore: LearnStore, LearnKeyProvider {
        var data: Data?
        func load() throws -> Data? { data }
        func save(_ d: Data) throws { data = d }
        func erase() throws { data = nil }
        func hmacKey() throws -> Data { Data(repeating: 7, count: 32) }
    }

    static let chat = ["ok anh", "dạ vâng ạ", "ok em nhé", "em cảm ơn", "đúng rồi anh", "để em check lại",
                       "để em kiểm tra lại rồi báo anh sau", "anh xem giúp em với", "haha đúng rồi"]
    static let shortChat: Set<String> = ["ok anh", "dạ vâng ạ", "ok em nhé", "em cảm ơn", "đúng rồi anh",
                                         "haha đúng rồi", "để em check lại"]

    private func month() -> [Candidate] {
        let learner = PhraseLearner(store: MemStore())
        learner.enabled = true
        let start = Date(timeIntervalSince1970: 20_000 * 86_400 + 3_600)
        let thanks = ["Dạ em cảm ơn anh chị đã quan tâm ạ", "Em cảm ơn anh chị đã quan tâm",
                      "Cảm ơn anh chị đã quan tâm nhé", "dạ em cảm ơn anh chị đã quan tâm"]
        let signature = ["Trân trọng, Nguyễn Văn An", "Trân trọng cảm ơn", "Mọi thắc mắc xin liên hệ phòng kế toán",
                         "Mọi thắc mắc xin liên hệ phòng kế toán qua số 0912 345 678"]
        let work = ["Em gửi anh báo cáo tuần này ạ", "Em gửi anh báo cáo tuần này", "em gửi chị file báo cáo tháng",
                    "Báo cáo bảo hiểm xã hội số tiền phải nộp tháng này", "Số lượng đơn hàng ở quận 1 tăng mạnh",
                    "Giao giúp em tới số 12 đường Lê Lợi phường Bến Nghé quận 1 nhé",
                    "Địa chỉ: số 12 đường Lê Lợi, phường Bến Nghé, quận 1, TP Hồ Chí Minh"]
        for d in 0..<30 {
            let ctx = LearnContext(bundleID: "com.tinyspeck.slackmacgap", secureInput: false, secureField: false,
                                   now: start.addingTimeInterval(Double(d) * 86_400))
            var lines = [thanks[d % thanks.count]]
            if d % 3 == 0 { lines.append(signature[d % signature.count]) }
            for (i, line) in Self.chat.enumerated() where (d + i) % 2 == 0 { lines.append(line) }
            if d % 2 == 0 { lines.append(work[d % work.count]) }
            if d % 7 == 0 { lines.append("Giao giúp em tới số 12 đường Lê Lợi phường Bến Nghé quận 1 nhé") }
            if d % 5 == 0 { lines += ["Email của em là an.nguyen@congty.vn", "an.nguyen@congty.vn"] }
            for line in lines { learner.observe(CommittedPhrase(text: line), context: ctx) }
        }
        return SuggestionRanking.rank(learner.ready)
    }

    func testMonth() {
        let shown = month()
        var taken: Set<String> = []
        var triggers: [String] = []
        for c in shown {
            let t = Abbreviation.suggest(for: c, existing: taken)
            taken.insert(t)
            triggers.append(t)
            print("BENCH \(c.count)x/\(c.days)d [\(c.kind)] \(t) ← \(c.text)")
        }
        let filler = shown.filter { Self.shortChat.contains($0.text.lowercased()) }
        let thankYous = shown.filter { $0.text.lowercased().contains("quan tâm") }
        let hard = zip(shown, triggers).filter { c, t in
            c.kind == .phrase && (t.count > 5 || t.contains(where: \.isNumber) || Abbreviation.isBlocked(t))
        }
        let falseAddresses = ["Báo cáo bảo hiểm xã hội số tiền phải nộp tháng này", "Số lượng đơn hàng ở quận 1 tăng mạnh"]
            .filter { text in PhraseDetector.pieces(in: text).contains { $0.1.kind == .address } }
        print("BENCH shown=\(shown.count) filler=\(filler.count) thankYous=\(thankYous.count) hard=\(hard.count) " +
              "falseAddresses=\(falseAddresses.count)")

        XCTAssertEqual(filler.map(\.text), [], "short chat replies are not worth a gõ tắt")
        // Of the 4 variants, the one held by another is hidden. Two remain that hold no other: only counting
        // sub-phrases (tier 5, not done) would find their shared core "cảm ơn anh chị đã quan tâm".
        XCTAssertEqual(thankYous.count, 2, "thank-you variants")
        XCTAssertEqual(hard.map(\.1), [], "phrase triggers: at most five letters, no number, nothing blocked")
        XCTAssertEqual(falseAddresses, [])
        XCTAssertTrue(shown.contains { $0.kind == .email }, "the email is still suggested")
        XCTAssertTrue(shown.contains { $0.kind == .address && $0.text.hasSuffix("quận 1") },
                      "the delivery address, without its trailing \"nhé\"")
    }
}

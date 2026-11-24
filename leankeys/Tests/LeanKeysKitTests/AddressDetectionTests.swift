import XCTest
@testable import LeanKeysKit

final class AddressDetectionTests: XCTestCase {
    private func address(_ text: String) -> String? {
        PhraseDetector.pieces(in: PhraseDetector.normalizedDisplay(text)).first { $0.1.kind == .address }?.1.display
    }

    /// N5: "số" and "xã" are everyday words. "số" counts before a number ("số 12", "số nhà 5"), "xã hội" never.
    func testEverydayWordsAreNoAddress() {
        XCTAssertNil(address("Báo cáo bảo hiểm xã hội số tiền phải nộp tháng này"))
        XCTAssertNil(address("Số lượng đơn hàng ở quận 1 tăng mạnh"))
        XCTAssertNil(address("Con số này ở phường mình cao lắm"))
    }

    /// The address ends with the name after its last address word, not at the end of the phrase.
    func testAddressEndsAfterLastName() {
        XCTAssertEqual(address("Giao giúp em tới số 12 đường Lê Lợi phường Bến Nghé quận 1 nhé"),
                       "số 12 đường Lê Lợi phường Bến Nghé quận 1")
        XCTAssertEqual(address("Em ở số nhà 5, quận Ba Đình"), "số nhà 5, quận Ba Đình")
        XCTAssertEqual(address("Địa chỉ: số 12 đường Lê Lợi, phường Bến Nghé, quận 1, TP Hồ Chí Minh"),
                       "số 12 đường Lê Lợi, phường Bến Nghé, quận 1, TP Hồ Chí Minh")
        // Lowercase names too: people often type "quận đống đa".
        XCTAssertEqual(address("gửi về 5 đường láng, quận đống đa giúp em với"), "đường láng, quận đống đa")
        XCTAssertEqual(address("Số 1234 đường Lê Lợi, quận 1"), "Số 1234 đường Lê Lợi, quận 1")
    }
}

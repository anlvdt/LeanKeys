import XCTest
@testable import LeanKeysKit

final class VietnameseTextToolkitTests: XCTestCase {
    func testStripDiacriticsAndCaseTransforms() {
        XCTAssertEqual(VietnameseTextToolkit.stripDiacritics("Đắk Lắk - Tiếng Việt 2026"), "Dak Lak - Tieng Viet 2026")
        XCTAssertEqual(VietnameseTextToolkit.transform("tiếng Việt", action: .uppercase), "TIẾNG VIỆT")
        XCTAssertEqual(VietnameseTextToolkit.transform("TIẾNG VIỆT", action: .lowercase), "tiếng việt")
        XCTAssertEqual(VietnameseTextToolkit.sentenceCase("chào bạn. hôm nay thế nào?"), "Chào bạn. Hôm nay thế nào?")
        XCTAssertEqual(VietnameseTextToolkit.titleCase("nguyễn văn an"), "Nguyễn Văn An")
    }

    func testTCVN3AndVNIWindowsRoundTrip() {
        let sample = "Cộng hòa xã hội chủ nghĩa Việt Nam - Đắk Lắk"
        let tcvn3 = VietnameseTextToolkit.unicodeToTCVN3(sample)
        XCTAssertNotEqual(tcvn3, sample)
        XCTAssertEqual(VietnameseTextToolkit.tcvn3ToUnicode(tcvn3), sample)

        XCTAssertEqual(VietnameseTextToolkit.vniWindowsToUnicode("Coäng hoøa xaõ hoäi chuû nghóa Vieät Nam"),
                       "Cộng hòa xã hội chủ nghĩa Việt Nam")
    }
}

import XCTest
@testable import LeanKeysKit

final class PopoverUpdateRowTests: XCTestCase {
    private func phase(_ source: PopoverUpdateRow.Source, requested: Bool = false) -> PopoverUpdateRow.Phase {
        PopoverUpdateRow.phase(source: source, installRequested: requested)
    }

    // The three states the task names: checking, up to date, newer version → download and install.
    func testCheckingShowsSpinnerLineAndNoButton() {
        let p = phase(.checking, requested: true)
        XCTAssertEqual(p, .checking)
        XCTAssertEqual(PopoverUpdateRow.line(p), "Đang kiểm tra cập nhật…")
        XCTAssertNil(PopoverUpdateRow.buttonTitle(p))
        XCTAssertNil(PopoverUpdateRow.tapAction(p))
        XCTAssertTrue(PopoverUpdateRow.isBusy(p))
    }

    func testUpToDateLine() {
        let p = phase(.upToDate)
        XCTAssertEqual(PopoverUpdateRow.line(p), "Bạn đang dùng bản mới nhất")
        XCTAssertNil(PopoverUpdateRow.tapAction(p))
        XCTAssertFalse(PopoverUpdateRow.isBusy(p))
    }

    func testNewerVersionGoesStraightToDownloadThenInstall() {
        XCTAssertEqual(phase(.available, requested: true), .downloading(progress: nil))
        XCTAssertEqual(phase(.downloading(progress: 0.425), requested: true), .downloading(progress: 0.425))
        XCTAssertEqual(PopoverUpdateRow.line(.downloading(progress: 0.425)), "Đang tải bản mới… 42%")
        let installing = phase(.readyToInstall, requested: true)
        XCTAssertEqual(installing, .installing)
        XCTAssertEqual(PopoverUpdateRow.line(installing), "Đang cài — LeanKeys sẽ tự mở lại")
        XCTAssertNil(PopoverUpdateRow.tapAction(installing), "no second click during the install")
    }

    func testIdleOffersTheCheck() {
        let p = phase(.idle)
        XCTAssertNil(PopoverUpdateRow.line(p))
        XCTAssertEqual(PopoverUpdateRow.buttonTitle(p), "Kiểm tra cập nhật")
        XCTAssertEqual(PopoverUpdateRow.tapAction(p), .check)
    }

    func testLegacyWindowOfferIsNotAnInstallButton() {
        XCTAssertEqual(phase(.available, requested: false), .idle, "nothing is downloaded yet")
    }

    func testBackgroundDownloadOffersOneClickInstall() {
        let p = phase(.readyToInstall, requested: false)
        XCTAssertEqual(p, .ready)
        XCTAssertEqual(PopoverUpdateRow.buttonTitle(p), "Cài")
        XCTAssertEqual(PopoverUpdateRow.tapAction(p), .install)
    }

    /// The ready row says which version it installs when the updater knows it.
    func testReadyLineNamesTheNewVersion() {
        XCTAssertEqual(PopoverUpdateRow.line(.ready, newVersion: "1.9"), "Có bản mới 1.9")
        XCTAssertEqual(PopoverUpdateRow.line(.ready), "Có bản mới")
        XCTAssertNil(PopoverUpdateRow.line(.idle, newVersion: "1.9"), "idle stays a plain button")
    }

    func testUnknownSizeIsIndeterminate() {
        XCTAssertNil(PopoverUpdateRow.clamp(-0.5), "totalBytesExpectedToWrite is -1 without Content-Length")
        XCTAssertNil(PopoverUpdateRow.clamp(.nan))
        XCTAssertNil(PopoverUpdateRow.clamp(.infinity))
        XCTAssertNil(PopoverUpdateRow.clamp(1.5))
        XCTAssertEqual(PopoverUpdateRow.clamp(1), 1)
        XCTAssertEqual(phase(.downloading(progress: -2), requested: true), .downloading(progress: nil))
        XCTAssertEqual(PopoverUpdateRow.line(.downloading(progress: nil)), "Đang tải bản mới…")
        XCTAssertEqual(PopoverUpdateRow.line(.downloading(progress: 0.999)), "Đang tải bản mới… 99%")
    }

    func testErrorsAreOneShortVietnameseLineWithRetry() {
        // UpdateChecker's English text is never shown.
        let network = phase(.error("Network error: The Internet connection appears to be offline."))
        XCTAssertEqual(network, .failed(.network))
        XCTAssertEqual(PopoverUpdateRow.line(network), "Không kiểm tra được, thử lại sau")
        XCTAssertEqual(phase(.error("Server error: 403")), .failed(.network))
        XCTAssertEqual(phase(.error("Tải về thất bại")), .failed(.download))
        XCTAssertEqual(phase(.error("Không thể lưu bản cập nhật")), .failed(.download))
        XCTAssertEqual(PopoverUpdateRow.line(.failed(.download)), "Không tải được bản mới")
        XCTAssertEqual(phase(.error(PopoverUpdateRow.Failure.installMessage)), .failed(.install))
        XCTAssertEqual(PopoverUpdateRow.line(.failed(.install)), "Không cài được bản mới")
        for failure in [PopoverUpdateRow.Failure.network, .download, .install] {
            XCTAssertEqual(PopoverUpdateRow.buttonTitle(.failed(failure)), "Thử lại")
            XCTAssertEqual(PopoverUpdateRow.tapAction(.failed(failure)), .check)
        }
    }

    func testEveryLineFitsOnOneShortLine() {
        let phases: [PopoverUpdateRow.Phase] = [.checking, .downloading(progress: 1), .downloading(progress: nil), .installing,
                                                .upToDate, .failed(.network), .failed(.download), .failed(.install)]
        for p in phases {
            let line = try? XCTUnwrap(PopoverUpdateRow.line(p))
            XCTAssertLessThanOrEqual(line?.count ?? 99, 34, "\(p)")
            XCTAssertFalse(line?.contains("\n") ?? true)
        }
    }

    func testErrorWindowTitleSaysWhatFailed() {
        XCTAssertEqual(PopoverUpdateRow.Failure.from(message: "Tải về thất bại").title, "Không tải được bản mới")
        XCTAssertEqual(PopoverUpdateRow.Failure.from(message: "Không thể lưu bản cập nhật").title, "Không tải được bản mới")
        XCTAssertEqual(PopoverUpdateRow.Failure.from(message: "Máy chủ cập nhật đang bận (mã 503). Thử lại sau ít phút.").title,
                       "Không kiểm tra được cập nhật")
        XCTAssertEqual(PopoverUpdateRow.Failure.from(message: PopoverUpdateRow.Failure.installMessage).title, "Không cài được bản mới")
    }
}

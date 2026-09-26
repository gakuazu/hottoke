import XCTest
import Photos
@testable import HottokeApp

/// 「写真リンク」の表示状態の判定（`DiaryPhotoService.presentation(for:hasPhotosThisDay:)`）のテスト。
/// オーナー実機フィードバック「写真ビューアがどこにあるか分からない」の原因（許可待ち・拒否・
/// その日の写真が0枚のいずれも「エリアを完全に隠す」扱いだったこと）への対応を検証する。
final class DiaryPhotoServiceTests: XCTestCase {

    func testAuthorizedWithPhotosShowsThumbnails() {
        XCTAssertEqual(DiaryPhotoService.presentation(for: .authorized, hasPhotosThisDay: true), .thumbnails)
        XCTAssertEqual(DiaryPhotoService.presentation(for: .limited, hasPhotosThisDay: true), .thumbnails, "一部の写真のみ許可でも表示する")
    }

    func testAuthorizedWithoutPhotosShowsAQuietMessageInsteadOfHiding() {
        XCTAssertEqual(DiaryPhotoService.presentation(for: .authorized, hasPhotosThisDay: false), .noPhotosThisDay)
        XCTAssertEqual(DiaryPhotoService.presentation(for: .limited, hasPhotosThisDay: false), .noPhotosThisDay)
    }

    func testNotDeterminedAsksForPermission() {
        XCTAssertEqual(DiaryPhotoService.presentation(for: .notDetermined, hasPhotosThisDay: false), .needsPermission)
        // 権限が無い間は、その日に写真があるかどうかに関わらず許可を促す表示になる。
        XCTAssertEqual(DiaryPhotoService.presentation(for: .notDetermined, hasPhotosThisDay: true), .needsPermission)
    }

    func testDeniedAndRestrictedAreDistinguished() {
        XCTAssertEqual(DiaryPhotoService.presentation(for: .denied, hasPhotosThisDay: false), .denied)
        XCTAssertEqual(DiaryPhotoService.presentation(for: .restricted, hasPhotosThisDay: false), .restricted)
        XCTAssertNotEqual(
            DiaryPhotoService.presentation(for: .denied, hasPhotosThisDay: false),
            DiaryPhotoService.presentation(for: .restricted, hasPhotosThisDay: false),
            "拒否と制限は別の案内にする（制限は設定アプリでは変えられないことが多いため）"
        )
    }
}

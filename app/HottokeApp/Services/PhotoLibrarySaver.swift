import Photos
import Foundation

/// docs/02-spec.md 2章・6章: 保存機能はカメラロールへの「追加のみ」権限で完結させる
/// （読み取り権限は要求しない設計）。
enum PhotoLibrarySaver {

    struct SaveError: Error, LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    static func saveVideo(at url: URL) async throws {
        try await requestAuthorizationIfNeeded()
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges({
                PHAssetChangeRequest.creationRequestForAssetFromVideo(atFileURL: url)
            }) { success, error in
                if success {
                    continuation.resume(returning: ())
                } else {
                    continuation.resume(throwing: error ?? SaveError(message: "動画の保存に失敗しました。"))
                }
            }
        }
    }

    private static func requestAuthorizationIfNeeded() async throws {
        let status = PHPhotoLibrary.authorizationStatus(for: .addOnly)
        if status == .authorized || status == .limited { return }
        let newStatus = await PHPhotoLibrary.requestAuthorization(for: .addOnly)
        guard newStatus == .authorized || newStatus == .limited else {
            throw SaveError(message: "写真ライブラリへのアクセスが許可されていません。設定アプリから許可してください。")
        }
    }
}

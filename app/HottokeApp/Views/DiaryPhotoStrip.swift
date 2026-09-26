import SwiftUI
import Photos

/// 「写真リンク」: その日撮った写真のサムネイルを、ひとこと日記カードのそばに小さく並べる。
/// タップすると、アプリ内で拡大表示する（Apple公式では特定の日だけを開くPhotosアプリへの
/// 深いリンクの手段が用意されていないため、アプリ内ビューアで代替している）。
/// 写真ファイルはアプリ内にコピー・保存せず、表示のたびにPhotosフレームワークから読み込むだけ。
struct DiaryPhotoStrip: View {
    let date: Date
    @AppStorage(DiaryPhotoLinkSettings.storageKey) private var enabled = DiaryPhotoLinkSettings.defaultEnabled

    @State private var items: [DiaryPhotoService.Item] = []
    @State private var thumbnails: [String: UIImage] = [:]
    /// タップした写真。`showViewer`と分けて持つ（`.sheet(item:)`は環境によって開かないことがあるため、
    /// `.fullScreenCover(isPresented:)`＋別途保持したこの値、という組み合わせのほうが確実に動く）。
    @State private var selectedItem: DiaryPhotoService.Item?
    @State private var showViewer = false

    var body: some View {
        Group {
            if enabled && !items.isEmpty {
                HStack(spacing: 8) {
                    ForEach(items) { item in
                        Button {
                            selectedItem = item
                            showViewer = true
                        } label: {
                            thumbnailView(for: item)
                        }
                        .buttonStyle(.plain)
                        // ラベルの見た目に関わらず、枠全体を確実にタップできるようにする。
                        .contentShape(Rectangle())
                        .accessibilityLabel("この日撮った写真")
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .task(id: "\(enabled)-\(date)") { await load() }
        .fullScreenCover(isPresented: $showViewer) {
            DiaryPhotoViewerSheet(items: items, initialID: selectedItem?.id ?? items.first?.id ?? "")
        }
    }

    @ViewBuilder
    private func thumbnailView(for item: DiaryPhotoService.Item) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 10).fill(Color.secondary.opacity(0.15))
            if let image = thumbnails[item.id] {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 56, height: 56)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
        }
        .frame(width: 56, height: 56)
    }

    private func load() async {
        guard enabled else {
            items = []
            return
        }
        let authorized = await DiaryPhotoService.requestAuthorizationIfNeeded()
        guard authorized else {
            items = []
            return
        }
        let found = DiaryPhotoService.photos(on: date)
        items = found
        thumbnails = [:]
        for item in found {
            DiaryPhotoService.requestThumbnail(for: item.asset, size: CGSize(width: 112, height: 112)) { image in
                guard let image else { return }
                Task { @MainActor in
                    thumbnails[item.id] = image
                }
            }
        }
    }
}

/// 写真をアプリ内で拡大表示する簡易ビューア（左右スワイプでその日の他の写真も見られる）。
struct DiaryPhotoViewerSheet: View {
    let items: [DiaryPhotoService.Item]
    let initialID: String
    @Environment(\.dismiss) private var dismiss
    @State private var selection: String
    @State private var images: [String: UIImage] = [:]

    init(items: [DiaryPhotoService.Item], initialID: String) {
        self.items = items
        self.initialID = initialID
        _selection = State(initialValue: initialID)
    }

    var body: some View {
        NavigationStack {
            TabView(selection: $selection) {
                ForEach(items) { item in
                    Group {
                        if let image = images[item.id] {
                            Image(uiImage: image)
                                .resizable()
                                .scaledToFit()
                        } else {
                            ProgressView()
                                .tint(.white)
                        }
                    }
                    .tag(item.id)
                    .task(id: item.id) { await loadDisplayImage(item) }
                }
            }
            .tabViewStyle(.page(indexDisplayMode: items.count > 1 ? .automatic : .never))
            .background(Color.black)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("閉じる") { dismiss() }
                }
            }
            .toolbarBackground(.visible, for: .navigationBar)
        }
    }

    private func loadDisplayImage(_ item: DiaryPhotoService.Item) async {
        guard images[item.id] == nil else { return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            DiaryPhotoService.requestDisplayImage(for: item.asset) { image in
                Task { @MainActor in
                    if let image { images[item.id] = image }
                    continuation.resume()
                }
            }
        }
    }
}

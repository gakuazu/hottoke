import SwiftUI

/// 「ひとこと日記」の絵文字を選ぶ、下からせり上がるシート（docs/29-app1-diary-note-design.md 4章）。
/// 標準絵文字16種を4×4のグリッドで表示し、タップすると即座に選ばれて閉じる。
/// 「なし（つけない）」で選択を解除できる。
struct EmojiPickerSheet: View {
    let selected: String?
    let onPick: (String?) -> Void
    @Environment(\.dismiss) private var dismiss

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 12), count: 4)

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(DiaryEmoji.allCases) { emoji in
                        Button {
                            onPick(emoji.symbol)
                            dismiss()
                        } label: {
                            VStack(spacing: 6) {
                                Text(emoji.symbol)
                                    .font(.system(size: 32))
                                    .frame(width: 56, height: 56)
                                    .background(
                                        Circle().fill(Color.secondary.opacity(0.12))
                                    )
                                    .overlay(
                                        Circle().strokeBorder(
                                            selected == emoji.symbol ? Color.accentColor : Color.clear,
                                            lineWidth: 2
                                        )
                                    )
                                Text(emoji.label)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                                    .minimumScaleFactor(0.8)
                            }
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(20)

                Button(role: .destructive) {
                    onPick(nil)
                    dismiss()
                } label: {
                    Label("なし（つけない）", systemImage: "xmark.circle")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .padding(.horizontal, 20)
                .padding(.bottom, 20)
            }
            .navigationTitle("絵文字を選ぶ")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

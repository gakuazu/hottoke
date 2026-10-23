import SwiftUI
import PhotosUI

struct ContentView: View {
    @ObservedObject var engine: FogEngine
    @State private var pickerItem: PhotosPickerItem?
    @State private var hintVisible = true

    var body: some View {
        ZStack {
            FogViewRepresentable(engine: engine)
                .ignoresSafeArea()

            if hintVisible {
                VStack(spacing: 8) {
                    Text("ふーっと息を吹く")
                    Text("指でなぞって拭く")
                    Text("2本指で長押しでも曇る")
                    Text("3本指タップで設定")
                }
                .font(.footnote)
                .foregroundStyle(.white.opacity(0.9))
                .shadow(radius: 3)
                .padding(.horizontal, 20).padding(.vertical, 14)
                .background(.black.opacity(0.25), in: RoundedRectangle(cornerRadius: 14))
                .allowsHitTesting(false)
                .transition(.opacity)
            }

            VStack {
                Spacer()
                HStack {
                    PhotosPicker(selection: $pickerItem, matching: .images) {
                        Image(systemName: "photo")
                            .font(.title3)
                            .foregroundStyle(.white.opacity(0.85))
                            .frame(width: 44, height: 44)
                            .background(.black.opacity(0.25), in: Circle())
                    }
                    Spacer()
                }
                .padding(.horizontal, 20).padding(.bottom, 12)
            }
        }
        .background(Color.black)
        .sheet(isPresented: $engine.showSettings) {
            SettingsView(engine: engine)
                .presentationDetents([.medium, .large])
        }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task {
                if let data = try? await item.loadTransferable(type: Data.self),
                   let img = UIImage(data: data) {
                    await MainActor.run { engine.setBackground(img) }
                }
            }
        }
        .task {
            try? await Task.sleep(nanoseconds: 7_000_000_000)
            withAnimation(.easeOut(duration: 1.0)) { hintVisible = false }
        }
    }
}

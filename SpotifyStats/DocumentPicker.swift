import SwiftUI
import UniformTypeIdentifiers

/// LiveContainer内でも確実に動くよう、SwiftUIのfileImporterではなくUIKitのピッカーを使う（asCopy=true）
struct DocumentPicker: UIViewControllerRepresentable {
    var types: [UTType]
    var allowsMultiple: Bool = true
    var onPick: ([URL]) -> Void

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let vc = UIDocumentPickerViewController(forOpeningContentTypes: types, asCopy: true)
        vc.allowsMultipleSelection = allowsMultiple
        vc.delegate = context.coordinator
        return vc
    }

    func updateUIViewController(_ uiViewController: UIDocumentPickerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        var parent: DocumentPicker

        init(parent: DocumentPicker) {
            self.parent = parent
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            parent.onPick(urls)
        }
    }
}

/// ファイル読み込みボタンの共通部品（自分のシートでピッカーを出す）
struct ImportButton: View {
    @EnvironmentObject private var store: StatsStore
    @State private var showPicker = false
    var title: String = "ZIP / JSONを選ぶ"

    var body: some View {
        Button {
            showPicker = true
        } label: {
            Label(title, systemImage: "square.and.arrow.down")
        }
        .disabled(store.isBusy)
        .sheet(isPresented: $showPicker) {
            DocumentPicker(types: [.zip, .json], allowsMultiple: true) { urls in
                store.importFiles(urls)
            }
        }
    }
}

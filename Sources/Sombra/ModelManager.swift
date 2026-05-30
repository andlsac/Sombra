import Foundation

/// Gerencia os modelos: lista instalados, importa um .gguf e baixa do catálogo.
/// Os modelos ficam em ~/Library/Application Support/Sombra/models.
@MainActor
final class ModelManager: NSObject, ObservableObject {
    static let shared = ModelManager()

    @Published var installed: [URL] = []
    @Published var downloadingFile: String? = nil   // filename em download
    @Published var progress: Double = 0             // 0...1
    @Published var lastError: String? = nil

    private var task: URLSessionDownloadTask?

    nonisolated static var modelsDir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Sombra/models", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    override init() {
        super.init()
        refreshInstalled()
    }

    func refreshInstalled() {
        let fm = FileManager.default
        let urls = (try? fm.contentsOfDirectory(at: Self.modelsDir,
                                                includingPropertiesForKeys: nil)) ?? []
        installed = urls.filter { $0.pathExtension.lowercased() == "gguf" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    /// Modelo base embutido no app (somente leitura, não pode ser apagado).
    nonisolated static var bundledBase: URL? {
        Bundle.main.resourceURL?
            .appendingPathComponent("models", isDirectory: true)
            .appendingPathComponent(ModelLocator.fileName)
    }

    /// Apaga um modelo baixado/importado (nunca o base embutido).
    func remove(_ url: URL) {
        guard url.path.hasPrefix(Self.modelsDir.path) else { return } // segurança
        try? FileManager.default.removeItem(at: url)
        refreshInstalled()
    }

    /// Copia um .gguf escolhido pelo usuário para a pasta de modelos.
    func importFile(_ src: URL) {
        let dest = Self.modelsDir.appendingPathComponent(src.lastPathComponent)
        do {
            if FileManager.default.fileExists(atPath: dest.path) {
                try FileManager.default.removeItem(at: dest)
            }
            try FileManager.default.copyItem(at: src, to: dest)
            refreshInstalled()
        } catch {
            lastError = "Falha ao importar: \(error.localizedDescription)"
        }
    }

    /// Baixa um modelo do catálogo com progresso.
    func download(_ model: CatalogModel) {
        guard downloadingFile == nil, let url = URL(string: model.url) else { return }
        lastError = nil
        progress = 0
        downloadingFile = model.filename
        let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
        let t = session.downloadTask(with: url)
        t.taskDescription = model.filename // destino, lido no delegate (nonisolated)
        task = t
        t.resume()
    }

    func cancelDownload() {
        task?.cancel()
        task = nil
        downloadingFile = nil
        progress = 0
    }
}

extension ModelManager: URLSessionDownloadDelegate {
    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                                didWriteData bytesWritten: Int64,
                                totalBytesWritten: Int64,
                                totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        let p = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
        Task { @MainActor in self.progress = p }
    }

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                                didFinishDownloadingTo location: URL) {
        // Move o arquivo temporário (síncrono, ainda válido aqui).
        let name = downloadTask.taskDescription ?? location.lastPathComponent
        let dest = Self.modelsDir.appendingPathComponent(name)
        let fm = FileManager.default
        try? fm.removeItem(at: dest)
        let ok = (try? fm.moveItem(at: location, to: dest)) != nil
        Task { @MainActor in
            if ok { self.refreshInstalled() }
            else { self.lastError = "Falha ao salvar o modelo." }
            self.downloadingFile = nil
            self.progress = 0
            self.task = nil
        }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask,
                                didCompleteWithError error: Error?) {
        if let error = error {
            Task { @MainActor in
                self.lastError = "Download falhou: \(error.localizedDescription)"
                self.downloadingFile = nil
                self.progress = 0
                self.task = nil
            }
        }
    }
}

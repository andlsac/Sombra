import AppKit

/// Informações de um release do GitHub relevantes para a atualização.
struct ReleaseInfo: Equatable {
    let version: String   // "0.3.0" (sem o "v")
    let tag: String       // "v0.3.0"
    let name: String      // "Sombra v0.3.0"
    let notes: String     // corpo do release (markdown)
    let dmgURL: URL       // download do .dmg
    let pageURL: URL      // página do release no GitHub
}

enum UpdateError: LocalizedError {
    case network, noRelease, noAsset, parse, notWritable, install(String)
    var errorDescription: String? {
        switch self {
        case .network:     return L.t("Could not reach GitHub.", "Não foi possível acessar o GitHub.")
        case .noRelease:   return L.t("No release found.", "Nenhum release encontrado.")
        case .noAsset:     return L.t("This release has no .dmg to install.", "Este release não tem .dmg para instalar.")
        case .parse:       return L.t("Unexpected response from GitHub.", "Resposta inesperada do GitHub.")
        case .notWritable: return L.t("Sombra isn't installed in a writable location. Reinstall from the .dmg manually.",
                                      "A Sombra não está num local com permissão de escrita. Reinstale pelo .dmg manualmente.")
        case .install(let m): return m
        }
    }
}

/// Verifica e aplica atualizações a partir dos Releases do GitHub.
/// Toda a rede é sob demanda: só roda quando o usuário pede (botão) ou, se ele
/// tiver optado, uma vez por abertura. Sem rede em qualquer outra situação.
@MainActor
final class Updater: ObservableObject {
    static let shared = Updater()
    private let repo = "andlsac/Sombra"

    @Published var checking = false
    @Published var downloading = false
    @Published var progress: Double = 0          // 0...1 durante o download
    @Published private(set) var available: ReleaseInfo?  // != nil se há versão nova
    @Published var lastError: String?
    @Published var lastCheck: Date?
    /// true após uma verificação que NÃO encontrou versão nova (feedback de UI).
    @Published var upToDate = false

    private var downloader: FileDownloader?

    /// Versão atual do app (CFBundleShortVersionString).
    var currentVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    // MARK: - Verificação

    /// Consulta o último release. Se for mais novo, popula `available`.
    /// `userInitiated` controla apenas o feedback de "já está atualizado".
    func checkForUpdates(userInitiated: Bool) async {
        guard !checking, !downloading else { return }
        checking = true
        lastError = nil
        upToDate = false
        defer { checking = false; lastCheck = Date() }

        do {
            let release = try await fetchLatest()
            if Self.isNewer(release.version, than: currentVersion) {
                available = release
            } else {
                available = nil
                upToDate = true
            }
        } catch {
            lastError = (error as? UpdateError)?.errorDescription ?? error.localizedDescription
        }
    }

    private func fetchLatest() async throws -> ReleaseInfo {
        guard let url = URL(string: "https://api.github.com/repos/\(repo)/releases/latest") else {
            throw UpdateError.network
        }
        var req = URLRequest(url: url)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("Sombra-Updater", forHTTPHeaderField: "User-Agent")
        req.timeoutInterval = 20

        let (data, resp): (Data, URLResponse)
        do { (data, resp) = try await URLSession.shared.data(for: req) }
        catch { throw UpdateError.network }
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            throw UpdateError.noRelease
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = json["tag_name"] as? String else { throw UpdateError.parse }

        let name = (json["name"] as? String) ?? tag
        let notes = (json["body"] as? String) ?? ""
        let pageURL = URL(string: (json["html_url"] as? String) ?? "https://github.com/\(repo)/releases")!
        let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag

        // Procura um asset .dmg.
        let assets = (json["assets"] as? [[String: Any]]) ?? []
        guard let dmg = assets.first(where: {
            (($0["name"] as? String)?.lowercased().hasSuffix(".dmg")) == true
        }), let dmgStr = dmg["browser_download_url"] as? String,
            let dmgURL = URL(string: dmgStr) else {
            throw UpdateError.noAsset
        }
        return ReleaseInfo(version: version, tag: tag, name: name,
                           notes: notes, dmgURL: dmgURL, pageURL: pageURL)
    }

    // MARK: - Download + instalação

    /// Baixa o .dmg do release, troca o app instalado e reabre.
    func downloadAndInstall(_ release: ReleaseInfo) async {
        guard !downloading else { return }
        // O app precisa estar num local gravável (ex.: /Applications copiado pelo
        // usuário). Senão, orientamos a reinstalar manualmente.
        let dest = Bundle.main.bundlePath
        let parent = (dest as NSString).deletingLastPathComponent
        guard FileManager.default.isWritableFile(atPath: parent) else {
            lastError = UpdateError.notWritable.errorDescription
            return
        }

        downloading = true
        progress = 0
        lastError = nil
        defer { downloading = false }

        do {
            let dl = FileDownloader { [weak self] p in
                Task { @MainActor in self?.progress = p }
            }
            downloader = dl
            let dmg = try await dl.download(release.dmgURL)
            try Self.installAndRelaunch(dmgPath: dmg.path, destAppPath: dest)
            // installAndRelaunch agenda o helper e encerra o app.
            NSApp.terminate(nil)
        } catch {
            lastError = (error as? UpdateError)?.errorDescription ?? error.localizedDescription
        }
    }

    /// Monta o .dmg, localiza o Sombra.app dentro dele e dispara um script que
    /// (1) espera este processo sair, (2) troca o bundle e (3) reabre o app.
    private static func installAndRelaunch(dmgPath: String, destAppPath: String) throws {
        let mount = NSTemporaryDirectory() + "SombraUpdate-\(UUID().uuidString)"
        try run("/usr/bin/hdiutil", ["attach", "-nobrowse", "-readonly",
                                     "-mountpoint", mount, dmgPath])

        // Encontra o .app montado.
        let contents = (try? FileManager.default.contentsOfDirectory(atPath: mount)) ?? []
        guard let appName = contents.first(where: { $0.hasSuffix(".app") }) else {
            _ = try? run("/usr/bin/hdiutil", ["detach", mount])
            throw UpdateError.install(L.t("App not found in the downloaded image.",
                                          "App não encontrado na imagem baixada."))
        }
        let src = mount + "/" + appName
        let pid = ProcessInfo.processInfo.processIdentifier

        let script = """
        #!/bin/bash
        PID="$1"; SRC="$2"; DEST="$3"; MNT="$4"
        # Espera o app atual encerrar.
        while kill -0 "$PID" 2>/dev/null; do sleep 0.3; done
        # Copia o novo app ao lado e troca de forma atômica.
        /usr/bin/ditto "$SRC" "${DEST}.new" || exit 1
        /usr/bin/hdiutil detach "$MNT" >/dev/null 2>&1
        /bin/rm -rf "$DEST"
        /bin/mv "${DEST}.new" "$DEST"
        /usr/bin/xattr -dr com.apple.quarantine "$DEST" 2>/dev/null
        sleep 0.4
        /usr/bin/open "$DEST"
        """
        let scriptPath = NSTemporaryDirectory() + "sombra-update-\(UUID().uuidString).sh"
        try script.write(toFile: scriptPath, atomically: true, encoding: .utf8)

        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/bash")
        task.arguments = [scriptPath, "\(pid)", src, destAppPath, mount]
        try task.run() // segue rodando após este app encerrar (reparentado ao launchd)
    }

    @discardableResult
    private static func run(_ launchPath: String, _ args: [String]) throws -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: launchPath)
        p.arguments = args
        try p.run()
        p.waitUntilExit()
        if p.terminationStatus != 0 {
            throw UpdateError.install(L.t("Failed to mount the update image.",
                                          "Falha ao montar a imagem da atualização."))
        }
        return p.terminationStatus
    }

    // MARK: - Comparação de versões (semver simples)

    static func isNewer(_ remote: String, than local: String) -> Bool {
        let r = parse(remote), l = parse(local)
        for i in 0..<max(r.count, l.count) {
            let rv = i < r.count ? r[i] : 0
            let lv = i < l.count ? l[i] : 0
            if rv != lv { return rv > lv }
        }
        return false
    }

    private static func parse(_ v: String) -> [Int] {
        v.split(separator: ".").map { Int($0.filter(\.isNumber)) ?? 0 }
    }
}

/// Baixa um arquivo para um temporário, reportando progresso (0...1).
private final class FileDownloader: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let onProgress: (Double) -> Void
    private var cont: CheckedContinuation<URL, Error>?

    init(onProgress: @escaping (Double) -> Void) { self.onProgress = onProgress }

    func download(_ url: URL) async throws -> URL {
        try await withCheckedThrowingContinuation { c in
            self.cont = c
            let session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)
            var req = URLRequest(url: url)
            req.setValue("Sombra-Updater", forHTTPHeaderField: "User-Agent")
            session.downloadTask(with: req).resume()
        }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                    totalBytesExpectedToWrite: Int64) {
        guard totalBytesExpectedToWrite > 0 else { return }
        onProgress(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                    didFinishDownloadingTo location: URL) {
        // `location` é apagado ao retornar — move já para um temporário estável.
        let dest = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("SombraUpdate-\(UUID().uuidString).dmg")
        do {
            try? FileManager.default.removeItem(at: dest)
            try FileManager.default.moveItem(at: location, to: dest)
            cont?.resume(returning: dest)
        } catch {
            cont?.resume(throwing: error)
        }
        cont = nil
        session.finishTasksAndInvalidate()
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        if let error { cont?.resume(throwing: error); cont = nil }
    }
}

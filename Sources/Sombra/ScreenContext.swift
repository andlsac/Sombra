import AppKit

/// Contexto da tela para enriquecer as sugestões: classifica onde você está
/// digitando (email, navegador + site, notas, código, chat…) a partir do
/// `bundleId` + título da janela — instantâneo, via Acessibilidade — e, quando
/// o recurso está ligado, acrescenta um trecho enxuto do texto visível (OCR).
///
/// O OCR é recapturado só quando o contexto MUDA (troca de app/janela/página),
/// em segundo plano, e fica cacheado — assim a digitação nunca espera por ele.
/// O texto final é curto de propósito (contexto longo dilui e não ajuda).
@MainActor
final class ScreenContext {
    static let shared = ScreenContext()
    private let ocr = ScreenOCR()

    private var lastAppId: String?
    private var lastTitle: String?
    private var label: String = ""

    /// Atualiza a partir do foco atual. Em mudança de app/janela, recomputa o
    /// rótulo e dispara recaptura do OCR.
    func update(bundleId: String?, windowTitle: String?) {
        guard SombraSettings.shared.useScreenContext else { return }
        if bundleId != lastAppId || windowTitle != lastTitle {
            lastAppId = bundleId
            lastTitle = windowTitle
            let appName = NSWorkspace.shared.frontmostApplication?.localizedName
            label = Self.categoryLabel(bundleId: bundleId, title: windowTitle, appName: appName)
            ocr.refresh(force: true)
        } else {
            ocr.refresh(force: false)
        }
    }

    /// Trecho de contexto para o prompt (rótulo + texto visível enxuto). Vazio
    /// se o recurso estiver desligado.
    var prompt: String {
        guard SombraSettings.shared.useScreenContext else { return "" }
        var parts: [String] = []
        if !label.isEmpty { parts.append(label) }
        let vis = ocr.latest.trimmingCharacters(in: .whitespacesAndNewlines)
        if !vis.isEmpty {
            let snippet = vis.split(whereSeparator: { $0 == " " || $0 == "\n" })
                .prefix(45).joined(separator: " ")
            parts.append(L.t("On screen: ", "Na tela: ") + snippet)
        }
        return parts.joined(separator: " ")
    }

    /// Solicita a permissão de gravação de tela (chamado ao LIGAR o recurso).
    static func requestScreenPermission() {
        _ = Permissions.ensureScreenRecording()
    }

    // MARK: - Classificação do contexto (rótulo curto)

    private static func categoryLabel(bundleId: String?, title: String?, appName: String?) -> String {
        let b = (bundleId ?? "").lowercased()
        let t = (title ?? "").lowercased()
        func tt(_ en: String, _ pt: String) -> String { L.t(en, pt) }

        if b.contains("mail") || b.contains("spark") || b.contains("airmail") {
            return tt("Writing an email.", "Escrevendo um email.")
        }
        if b.contains("notes") || b.contains("bear") || b.contains("obsidian") || b.contains("notion") {
            return tt("Writing a note.", "Escrevendo uma nota.")
        }
        if b.contains("slack") || b.contains("discord") || b.contains("whatsapp")
            || b.contains("messages") || b.contains("telegram") || b.contains("messenger") {
            return tt("Writing a chat message.", "Escrevendo uma mensagem.")
        }
        if b.contains("code") || b.contains("xcode") || b.contains("terminal")
            || b.contains("iterm") || b.contains("sublime") || b.contains("jetbrains") {
            return tt("Writing code.", "Escrevendo código.")
        }

        let browsers = ["safari", "chrome", "brave", "arc", "firefox", "edge", "vivaldi", "opera", "chromium"]
        if browsers.contains(where: { b.contains($0) }) {
            let sites: [(String, String, String)] = [
                ("reddit", "Commenting on Reddit.", "Comentando no Reddit."),
                ("github", "Writing on GitHub.", "Escrevendo no GitHub."),
                ("youtube", "Commenting on YouTube.", "Comentando no YouTube."),
                ("stack overflow", "Answering on Stack Overflow.", "Respondendo no Stack Overflow."),
                ("gmail", "Writing an email.", "Escrevendo um email."),
                ("twitter", "Writing a post.", "Escrevendo um post."),
                (" x", "Writing a post.", "Escrevendo um post."),
                ("linkedin", "Writing on LinkedIn.", "Escrevendo no LinkedIn."),
                ("whatsapp", "Writing a chat message.", "Escrevendo uma mensagem."),
            ]
            for (kw, en, pt) in sites where t.contains(kw) { return tt(en, pt) }
            return tt("Writing in the browser.", "Escrevendo no navegador.")
        }

        if let n = appName, !n.isEmpty {
            return L.t("Writing in \(n).", "Escrevendo no \(n).")
        }
        return ""
    }
}

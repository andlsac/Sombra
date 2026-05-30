import AppKit
import ScreenCaptureKit
import Vision

/// Captura a tela e extrai texto via Vision para dar contexto ao preditor.
/// É caro: roda no máximo a cada `minInterval` e cacheia o resultado.
final class ScreenOCR {
    private var cached: String = ""
    private var lastRun: Date = .distantPast
    private let minInterval: TimeInterval = 4.0
    private var running = false

    /// Texto da tela mais recente (pode estar levemente defasado — tudo bem).
    var latest: String { cached }

    /// Dispara uma atualização do OCR se já passou tempo suficiente.
    func refreshIfNeeded() {
        guard !running, Date().timeIntervalSince(lastRun) > minInterval else { return }
        guard Permissions.ensureScreenRecording() else { return }
        running = true
        lastRun = Date()

        Task.detached(priority: .utility) { [weak self] in
            let text = await self?.captureAndRecognize() ?? ""
            await MainActor.run { [weak self] in
                if !text.isEmpty { self?.cached = text }
                self?.running = false
            }
        }
    }

    private func captureAndRecognize() async -> String {
        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                false, onScreenWindowsOnly: true
            )
            guard let display = content.displays.first else { return "" }

            let filter = SCContentFilter(display: display, excludingWindows: [])
            let config = SCStreamConfiguration()
            config.width = display.width
            config.height = display.height
            config.showsCursor = false

            let image = try await SCScreenshotManager.captureImage(
                contentFilter: filter, configuration: config
            )
            return recognizeText(in: image)
        } catch {
            NSLog("[Sombra] OCR falhou: \(error.localizedDescription)")
            return ""
        }
    }

    private func recognizeText(in image: CGImage) -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .fast        // velocidade > precisão p/ contexto
        request.usesLanguageCorrection = false
        request.recognitionLanguages = ["pt-BR", "en-US"]

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform([request])
        } catch {
            return ""
        }
        let lines = (request.results ?? []).compactMap {
            $0.topCandidates(1).first?.string
        }
        // Limita o tamanho para não estourar o contexto do modelo.
        return lines.joined(separator: "\n").prefixWords(120)
    }
}

private extension String {
    func prefixWords(_ n: Int) -> String {
        let parts = split(separator: " ")
        guard parts.count > n else { return self }
        return parts.prefix(n).joined(separator: " ")
    }
}

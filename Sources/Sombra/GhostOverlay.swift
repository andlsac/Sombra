import AppKit

/// Bubble flutuante que mostra a previsão perto do cursor (ou abaixo do campo,
/// quando o app não informa a posição do cursor de forma confiável).
/// Não recebe foco nem cliques.
final class GhostOverlay {
    private let panel: NSPanel
    private let bubble: NSView
    private let label: NSTextField

    private let hInset: CGFloat = 9
    private let vInset: CGFloat = 5

    init() {
        label = NSTextField(labelWithString: "")
        label.font = NSFont.systemFont(ofSize: 14)
        label.backgroundColor = .clear
        label.isBezeled = false
        label.isEditable = false
        label.drawsBackground = false
        label.lineBreakMode = .byTruncatingTail

        bubble = NSView()
        bubble.wantsLayer = true
        bubble.layer?.cornerRadius = 8
        bubble.layer?.borderWidth = 0.5
        bubble.addSubview(label)

        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 10, height: 24),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.contentView = bubble
    }

    /// Mostra `suffix`, ancorado no cursor (`caretRect`) ou, se inválido,
    /// abaixo do campo focado (`elementRect`). Retângulos em coords de tela
    /// (origem no canto superior esquerdo do display principal).
    func show(suffix: String, caretRect: CGRect?, elementRect: CGRect?,
              isCorrection: Bool = false, atEnd: Bool = true,
              correction: (wrong: String, right: String)? = nil) {
        guard !suffix.isEmpty else { hide(); return }

        bubble.layer?.backgroundColor = NSColor.textBackgroundColor.withAlphaComponent(0.96).cgColor
        bubble.layer?.borderColor = NSColor.separatorColor.cgColor
        panel.hasShadow = true

        if let c = correction {
            // Correção: a palavra errada RISCADA em vermelho + a correção em verde
            // escuro (ex.: "~~teh~~  the").
            label.attributedStringValue = Self.correctionText(wrong: c.wrong, right: c.right,
                                                              font: label.font ?? NSFont.systemFont(ofSize: 14))
        } else {
            // Autocomplete na cor configurável.
            label.textColor = SombraSettings.shared.nsGhostColor
            label.stringValue = suffix
        }
        label.sizeToFit()
        var size = label.frame.size
        size.width = min(size.width, 520) // não estoura a tela
        let bubbleSize = NSSize(width: size.width + hInset * 2, height: size.height + vInset * 2)

        // No fim da linha → à frente do cursor; editando no meio → acima (visível,
        // sem cobrir o texto que vem depois).
        guard let origin = placeCocoa(caretRect: caretRect, elementRect: elementRect,
                                      bubbleSize: bubbleSize, gap: 6,
                                      above: !atEnd) else { hide(); return }

        label.frame = NSRect(x: hInset, y: vInset, width: size.width, height: size.height)
        panel.setContentSize(bubbleSize)
        bubble.frame = NSRect(origin: .zero, size: bubbleSize)
        panel.setFrameOrigin(origin)
        panel.orderFrontRegardless()
    }

    func hide() {
        label.stringValue = ""
        panel.orderOut(nil)
    }

    /// Texto da correção: palavra errada riscada (vermelho) + correção (verde escuro).
    private static func correctionText(wrong: String, right: String, font: NSFont) -> NSAttributedString {
        let red = NSColor.systemRed
        let darkGreen = NSColor(srgbRed: 0.10, green: 0.50, blue: 0.20, alpha: 1)
        let s = NSMutableAttributedString()
        s.append(NSAttributedString(string: wrong, attributes: [
            .font: font, .foregroundColor: red,
            .strikethroughStyle: NSUnderlineStyle.single.rawValue,
            .strikethroughColor: red,
        ]))
        s.append(NSAttributedString(string: "  ", attributes: [.font: font]))
        s.append(NSAttributedString(string: right, attributes: [
            .font: font, .foregroundColor: darkGreen,
        ]))
        return s
    }

    // MARK: - Posicionamento

    /// Posição (origem Cocoa, bottom-left): à frente do cursor quando há posição
    /// confiável; senão, junto ao campo focado (apps tipo Electron/navegador que
    /// não expõem a posição do cursor — melhor mostrar perto do campo que sumir).
    /// `above`: posicionar ACIMA do cursor (em vez de à frente) — usado quando
    /// editando no meio do texto ou em apps não-nativos, pra ficar sempre visível
    /// (mesmo cobrindo a linha de cima) sem cobrir o que vem depois do cursor.
    private func placeCocoa(caretRect: CGRect?, elementRect: CGRect?,
                            bubbleSize: NSSize, gap: CGFloat, above: Bool) -> NSPoint? {
        var leftCG: CGFloat
        var topCG: CGFloat
        if let c = caretRect, isValidCaret(c) {
            if above {
                // Logo ACIMA da linha do cursor (um pouco acima).
                leftCG = c.minX
                topCG = c.minY - bubbleSize.height - 3
            } else {
                // À frente do cursor, centralizado na linha (fim de linha).
                leftCG = c.maxX + gap
                topCG = c.midY - bubbleSize.height / 2
            }
        } else if let e = elementRect, !e.isEmpty {
            // Apps Electron/Chromium (cursor impreciso): posição escolhida pelo usuário.
            switch SombraSettings.shared.electronGhostPosition {
            case 1: // abaixo do campo
                leftCG = e.minX + 8; topCG = e.maxY + 3
            case 2: // canto superior direito do campo/janela
                leftCG = e.maxX - bubbleSize.width - 6; topCG = e.minY + 4
            case 3: // ocultar a sombra nesses apps
                return nil
            default: // 0 = acima do campo (padrão)
                leftCG = e.minX + 8; topCG = e.minY - bubbleSize.height - 3
            }
        } else {
            return nil
        }

        let primaryH = NSScreen.screens.first(where: { $0.frame.origin == .zero })?.frame.height
            ?? NSScreen.main?.frame.height ?? topCG
        var x = leftCG
        var y = primaryH - topCG - bubbleSize.height

        let probe = NSPoint(x: leftCG, y: primaryH - topCG)
        let screen = NSScreen.screens.first(where: { $0.frame.contains(probe) }) ?? NSScreen.main
        if let vis = screen?.visibleFrame {
            x = min(max(x, vis.minX), vis.maxX - bubbleSize.width)
            y = min(max(y, vis.minY), vis.maxY - bubbleSize.height)
        }
        return NSPoint(x: x, y: y)
    }

    /// Heurística: descarta retângulos zerados/absurdos que alguns apps retornam.
    private func isValidCaret(_ r: CGRect) -> Bool {
        if r.origin == .zero && r.size == .zero { return false }
        if r.height <= 3 || r.height > 200 { return false }
        if abs(r.origin.x) > 20000 || abs(r.origin.y) > 20000 { return false }
        return true
    }
}

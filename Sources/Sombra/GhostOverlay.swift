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
    func show(suffix: String, caretRect: CGRect?, elementRect: CGRect?, isCorrection: Bool = false) {
        guard !suffix.isEmpty else { hide(); return }

        // Correção ortográfica em laranja; autocomplete na cor configurável.
        label.textColor = isCorrection ? NSColor.systemOrange : SombraSettings.shared.nsGhostColor
        bubble.layer?.backgroundColor = NSColor.textBackgroundColor.withAlphaComponent(0.96).cgColor
        bubble.layer?.borderColor = NSColor.separatorColor.cgColor

        label.stringValue = suffix
        label.sizeToFit()
        var size = label.frame.size
        size.width = min(size.width, 520) // não estoura a tela
        let bubbleSize = NSSize(width: size.width + hInset * 2, height: size.height + vInset * 2)

        guard let origin = placeCocoa(caretRect: caretRect, elementRect: elementRect,
                                      bubbleSize: bubbleSize) else { hide(); return }

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

    // MARK: - Posicionamento

    /// Posição (origem Cocoa, bottom-left) do bubble:
    ///  - cursor válido → À DIREITA do cursor, com folga, centralizado na linha;
    ///  - senão → abaixo da 1ª linha do campo focado.
    /// Sempre preso dentro da tela visível.
    private func placeCocoa(caretRect: CGRect?, elementRect: CGRect?,
                            bubbleSize: NSSize) -> NSPoint? {
        let gap: CGFloat = 10
        // topCG = borda superior desejada do bubble (coords CG, top-left).
        var leftCG: CGFloat
        var topCG: CGFloat

        if let c = caretRect, isValidCaret(c) {
            leftCG = c.maxX + gap                       // à frente do cursor
            topCG = c.midY - bubbleSize.height / 2       // centralizado na linha
        } else if let e = elementRect, !e.isEmpty {
            leftCG = e.minX + 6
            topCG = min(e.maxY + 2, e.minY + 26)         // abaixo da 1ª linha
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

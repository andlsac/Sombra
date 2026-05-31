import AppKit

/// Iconezinho de presença da Sombra, fixo no canto superior direito da janela
/// em foco. Indica que a Sombra está ativa e observando o campo — mesmo antes
/// de qualquer sugestão aparecer. Não recebe foco nem cliques.
final class IndicatorOverlay {
    private let panel: NSPanel
    private let imageView: NSImageView
    private let iconSize: CGFloat = 20     // tamanho de exibição (um pouco maior que a barra de menu)
    private let inset: CGFloat = 8         // folga a partir do canto da janela
    private var visible = false

    init() {
        imageView = NSImageView()
        imageView.imageScaling = .scaleProportionallyUpOrDown
        imageView.image = Self.loadIcon()

        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: iconSize, height: iconSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.alphaValue = 1.0
        imageView.frame = NSRect(x: 0, y: 0, width: iconSize, height: iconSize)
        panel.contentView = imageView
    }

    /// Ícone dedicado `indicator.png` (quando existir no bundle), senão o ícone
    /// do app como placeholder.
    private static func loadIcon() -> NSImage {
        if let url = Bundle.main.url(forResource: "indicator", withExtension: "png"),
           let img = NSImage(contentsOf: url) {
            return img
        }
        return NSApp.applicationIconImage ?? NSImage()
    }

    /// Posiciona no canto superior direito de `windowRect` (coords de tela,
    /// origem no canto superior esquerdo do display principal). Preso à tela.
    func show(windowRect: CGRect) {
        guard !windowRect.isEmpty, windowRect.width > 1, windowRect.height > 1 else { hide(); return }

        let rightCG = windowRect.maxX - inset - iconSize
        let topCG = windowRect.minY + inset

        let primaryH = NSScreen.screens.first(where: { $0.frame.origin == .zero })?.frame.height
            ?? NSScreen.main?.frame.height ?? 0
        var x = rightCG
        var y = primaryH - topCG - iconSize

        let probe = NSPoint(x: windowRect.midX, y: primaryH - windowRect.midY)
        let screen = NSScreen.screens.first(where: { $0.frame.contains(probe) }) ?? NSScreen.main
        if let vis = screen?.visibleFrame {
            x = min(max(x, vis.minX), vis.maxX - iconSize)
            y = min(max(y, vis.minY), vis.maxY - iconSize)
        }

        panel.setFrameOrigin(NSPoint(x: x, y: y))
        if !visible { panel.orderFrontRegardless(); visible = true }
    }

    func hide() {
        if visible { panel.orderOut(nil); visible = false }
    }
}

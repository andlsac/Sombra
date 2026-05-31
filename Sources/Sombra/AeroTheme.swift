import SwiftUI
import AppKit

/// Tema visual "Frutiger Aero / iMac translúcido": vidro (vibrancy) + gradiente
/// vivo, botões glossy estilo Aqua e toggles brilhantes. Cores candy variadas.
enum Candy {
    static let bondi      = Color(red: 0.00, green: 0.66, blue: 0.80)
    static let blueberry  = Color(red: 0.20, green: 0.52, blue: 0.96)
    static let grape      = Color(red: 0.56, green: 0.36, blue: 0.82)
    static let lime       = Color(red: 0.42, green: 0.78, blue: 0.25)
    static let tangerine  = Color(red: 1.00, green: 0.56, blue: 0.10)
    static let strawberry = Color(red: 0.96, green: 0.30, blue: 0.46)
}

/// NSVisualEffectView atrás do conteúdo (deixa o desktop aparecer = "liquid glass").
struct VisualEffectBackground: NSViewRepresentable {
    var material: NSVisualEffectView.Material = .underWindowBackground
    var blending: NSVisualEffectView.BlendingMode = .behindWindow
    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = NSVisualEffectView()
        v.material = material; v.blendingMode = blending; v.state = .active
        return v
    }
    func updateNSView(_ v: NSVisualEffectView, context: Context) {
        v.material = material; v.blendingMode = blending
    }
}

/// Fundo das janelas: vibrancy do sistema + gradiente vivo translúcido + brilho.
struct AeroBackground: View {
    var tint: Color = Candy.bondi
    var body: some View {
        ZStack {
            VisualEffectBackground()
            LinearGradient(colors: [tint.opacity(0.34), Candy.grape.opacity(0.26), Candy.blueberry.opacity(0.30)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            LinearGradient(colors: [.white.opacity(0.30), .clear],
                           startPoint: .top, endPoint: .center)
        }
        .ignoresSafeArea()
    }
}

// MARK: - Botão glossy (Aqua)

struct GlossyButtonStyle: ButtonStyle {
    var tint: Color = Candy.blueberry
    func makeBody(configuration: Configuration) -> some View {
        GlossyButtonBody(configuration: configuration, tint: tint)
    }
}

private struct GlossyButtonBody: View {
    let configuration: ButtonStyle.Configuration
    let tint: Color
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let p = configuration.isPressed
        let border = scheme == .dark ? 0.28 : 0.55
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.white)
            .padding(.vertical, 7).padding(.horizontal, 16)
            .background(
                ZStack {
                    Capsule().fill(.ultraThinMaterial)
                    Capsule().fill(LinearGradient(colors: [tint.opacity(0.50), tint.opacity(0.78)],
                                                  startPoint: .top, endPoint: .bottom))
                    Capsule().fill(LinearGradient(colors: [.white.opacity(0.60), .white.opacity(0.0)],
                                                  startPoint: .top, endPoint: .center))
                        .padding(1.5).mask(Capsule())
                    Capsule().strokeBorder(.white.opacity(border), lineWidth: 1)
                }
            )
            .shadow(color: tint.opacity(0.32), radius: 4, y: 2)
            .brightness(p ? -0.06 : 0)
            .scaleEffect(p ? 0.97 : 1)
            .animation(.easeOut(duration: 0.12), value: p)
    }
}

// MARK: - Toggle glossy (com símbolos estilo iOS: | ligado, ○ desligado)

struct GlossyToggleStyle: ToggleStyle {
    var onColor: Color = Candy.lime
    func makeBody(configuration: Configuration) -> some View {
        GlossyToggleBody(configuration: configuration, onColor: onColor)
    }
}

private struct GlossyToggleBody: View {
    let configuration: ToggleStyle.Configuration
    let onColor: Color
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let on = configuration.isOn
        let border = scheme == .dark ? 0.22 : 0.55
        HStack {
            configuration.label
            Spacer()
            ZStack(alignment: on ? .trailing : .leading) {
                Capsule().fill(Color.gray.opacity(scheme == .dark ? 0.30 : 0.40))
                Capsule().fill(LinearGradient(colors: [onColor.opacity(0.85), onColor],
                                              startPoint: .top, endPoint: .bottom))
                    .opacity(on ? 1 : 0)
                // Símbolos iOS: barra "|" (ligado, à esquerda) e círculo "○" (desligado, à direita).
                HStack(spacing: 0) {
                    RoundedRectangle(cornerRadius: 1).fill(.white)
                        .frame(width: 2.5, height: 11).opacity(on ? 0.95 : 0)
                    Spacer()
                    Circle().stroke(.white, lineWidth: 2)
                        .frame(width: 11, height: 11).opacity(on ? 0 : 0.8)
                }
                .padding(.horizontal, 8)
                Capsule().fill(LinearGradient(colors: [.white.opacity(0.45), .clear],
                                              startPoint: .top, endPoint: .center))
                    .padding(1.5).allowsHitTesting(false)
                Capsule().strokeBorder(.white.opacity(border), lineWidth: 1)
                Circle()
                    .fill(LinearGradient(colors: [.white, Color(white: 0.86)],
                                         startPoint: .top, endPoint: .bottom))
                    .overlay(Circle().strokeBorder(.black.opacity(0.06), lineWidth: 0.5))
                    .padding(2)
                    .shadow(color: .black.opacity(0.25), radius: 1.5, y: 1)
                    .frame(width: 26, height: 26)
            }
            .frame(width: 48, height: 28)
            .contentShape(Capsule())
            .onTapGesture { withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) { configuration.isOn.toggle() } }
        }
    }
}

// MARK: - Card de vidro

struct GlassCard: ViewModifier {
    var tint: Color = Candy.bondi
    var cornerRadius: CGFloat = 16
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        let border = scheme == .dark ? 0.16 : 0.40
        let sheen = scheme == .dark ? 0.16 : 0.35
        content
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(LinearGradient(colors: [tint.opacity(0.18), .clear],
                                             startPoint: .top, endPoint: .bottom)))
                    .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .fill(LinearGradient(colors: [.white.opacity(sheen), .clear],
                                             startPoint: .top, endPoint: .center)))
                    .overlay(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .strokeBorder(.white.opacity(border), lineWidth: 1))
            )
            .shadow(color: .black.opacity(0.15), radius: 8, y: 3)
    }
}

extension View {
    func glassCard(tint: Color = Candy.bondi, cornerRadius: CGFloat = 16) -> some View {
        modifier(GlassCard(tint: tint, cornerRadius: cornerRadius))
    }
}

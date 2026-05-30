import Foundation

/// Localização mínima EN/PT que segue o idioma do sistema.
/// Uso: `L.t("English text", "Texto em português")`.
enum L {
    /// true se o idioma preferido do sistema for português.
    static let isPT: Bool = {
        (Locale.preferredLanguages.first?.lowercased().hasPrefix("pt")) ?? false
    }()

    static func t(_ en: String, _ pt: String) -> String { isPT ? pt : en }
}

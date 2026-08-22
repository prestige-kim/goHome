import SwiftUI

enum TransitPalette {
    static let backdrop = Color(red: 0.87, green: 0.92, blue: 0.96)
    static let canvas = Color(red: 0.92, green: 0.95, blue: 0.97)
    static let steel = Color(red: 0.85, green: 0.90, blue: 0.94)
    static let cardBlue = Color(red: 0.86, green: 0.92, blue: 0.98)
    static let cardMint = Color(red: 0.87, green: 0.96, blue: 0.91)
    static let cardSand = Color(red: 0.97, green: 0.91, blue: 0.78)
    static let cardLilac = Color(red: 0.92, green: 0.89, blue: 0.98)
    static let cardPeach = Color(red: 0.98, green: 0.89, blue: 0.84)
    static let ivory = Color(red: 0.98, green: 0.97, blue: 0.94)
    static let ink = Color(red: 0.06, green: 0.13, blue: 0.22)
    static let slate = Color(red: 0.32, green: 0.40, blue: 0.48)
    static let cobalt = Color(red: 0.18, green: 0.44, blue: 0.86)
    static let transitGreen = Color(red: 0.15, green: 0.65, blue: 0.35)
    static let liveTeal = Color(red: 0.08, green: 0.61, blue: 0.55)
    static let warning = Color(red: 0.85, green: 0.48, blue: 0.07)
    static let favorite = Color(red: 0.91, green: 0.20, blue: 0.34)
}

enum TransitCardTone {
    case blue
    case mint
    case sand
    case lilac
    case peach
    case neutral

    var color: Color {
        switch self {
        case .blue: TransitPalette.cardBlue
        case .mint: TransitPalette.cardMint
        case .sand: TransitPalette.cardSand
        case .lilac: TransitPalette.cardLilac
        case .peach: TransitPalette.cardPeach
        case .neutral: TransitPalette.ivory
        }
    }
}

enum SubwayLineStyle {
    static func color(for lineName: String) -> Color {
        switch lineName {
        case "1호선": TransitPalette.cobalt
        case "2호선": TransitPalette.transitGreen
        case "3호선": Color(red: 0.93, green: 0.42, blue: 0.09)
        case "4호선": Color(red: 0.00, green: 0.58, blue: 0.76)
        case "5호선": Color(red: 0.54, green: 0.30, blue: 0.70)
        case "6호선": Color(red: 0.61, green: 0.39, blue: 0.20)
        case "7호선": Color(red: 0.40, green: 0.49, blue: 0.13)
        case "8호선": Color(red: 0.82, green: 0.17, blue: 0.42)
        case "9호선": Color(red: 0.66, green: 0.54, blue: 0.17)
        case "수인분당선": Color(red: 0.88, green: 0.66, blue: 0.08)
        case "신분당선": Color(red: 0.73, green: 0.13, blue: 0.16)
        case "경의중앙선": Color(red: 0.10, green: 0.62, blue: 0.48)
        case "경춘선": Color(red: 0.08, green: 0.62, blue: 0.40)
        case "공항철도": Color(red: 0.00, green: 0.43, blue: 0.66)
        case "우이신설선": Color(red: 0.62, green: 0.69, blue: 0.10)
        case "서해선": Color(red: 0.37, green: 0.64, blue: 0.18)
        case "경강선": Color(red: 0.00, green: 0.45, blue: 0.65)
        case "GTX-A": Color(red: 0.43, green: 0.24, blue: 0.62)
        default: TransitPalette.cobalt
        }
    }

    static func shortName(for lineName: String) -> String {
        lineName.replacingOccurrences(of: "호선", with: "")
    }
}

private struct TransitPageBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .foregroundStyle(TransitPalette.ink)
            .background {
                LinearGradient(
                    colors: [TransitPalette.canvas, TransitPalette.backdrop.opacity(0.72)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
            }
    }
}

private struct TransitCardSurface: ViewModifier {
    let tone: TransitCardTone
    let accent: Color?

    func body(content: Content) -> some View {
        content
            .background(tone.color, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(alignment: .leading) {
                if let accent {
                    Capsule()
                        .fill(accent)
                        .frame(width: 4)
                        .padding(.vertical, 15)
                        .padding(.leading, 1)
                }
            }
            .overlay {
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .stroke(TransitPalette.ink.opacity(0.07), lineWidth: 1)
            }
            .shadow(color: TransitPalette.ink.opacity(0.07), radius: 14, y: 7)
    }
}

extension View {
    func transitPageBackground() -> some View {
        modifier(TransitPageBackground())
    }

    func transitCard(
        tone: TransitCardTone = .neutral,
        accent: Color? = nil
    ) -> some View {
        modifier(TransitCardSurface(tone: tone, accent: accent))
    }
}

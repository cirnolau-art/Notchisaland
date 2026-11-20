import SwiftUI

struct LyricAppearancePreview: View {
    var appearance: LyricsAppearance
    var rightBackground: Bool

    var body: some View {
        GeometryReader { geometry in
            let centerWidth: CGFloat = 90
            let wings = min(appearance.width, max(0, (geometry.size.width - centerWidth) / 2))
            let color = Color(nsColor: appearance.color)
            HStack(spacing: 0) {
                LinearGradient(colors: [.clear, .black.opacity(appearance.opacity)], startPoint: .leading, endPoint: .trailing)
                    .frame(width: wings)
                    .overlay {
                        Text("把星光放在手心")
                            .font(Font(NSFont.systemFont(ofSize: appearance.size, weight: appearance.weight.fontWeight)))
                            .lineLimit(1)
                            .foregroundStyle(color)
                            .shadow(color: color.opacity(appearance.glow), radius: 2 + 6 * appearance.glow)
                            .padding(.horizontal, 8)
                    }
                Color.black.frame(width: centerWidth)
                LinearGradient(colors: [.black.opacity(appearance.opacity), .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: wings)
                    .opacity(rightBackground ? 1 : 0)
            }
            .frame(height: 30)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .background(Color(nsColor: NSColor(srgbRed: 0.18, green: 0.24, blue: 0.27, alpha: 1)), in: RoundedRectangle(cornerRadius: 8))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

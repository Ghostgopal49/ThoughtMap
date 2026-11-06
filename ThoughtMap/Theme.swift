import SwiftUI

enum Palette {
    static let count = 8

    static let colors: [Color] = [
        Color(red: 0.96, green: 0.52, blue: 0.26), // orange
        Color(red: 0.36, green: 0.55, blue: 0.96), // blue
        Color(red: 0.22, green: 0.70, blue: 0.55), // green
        Color(red: 0.86, green: 0.36, blue: 0.56), // pink
        Color(red: 0.58, green: 0.42, blue: 0.90), // violet
        Color(red: 0.90, green: 0.70, blue: 0.20), // gold
        Color(red: 0.20, green: 0.66, blue: 0.80), // teal
        Color(red: 0.80, green: 0.40, blue: 0.32)  // brick
    ]

    static func color(_ index: Int) -> Color {
        guard index >= 0 else { return Color.gray }
        return colors[index % colors.count]
    }
}

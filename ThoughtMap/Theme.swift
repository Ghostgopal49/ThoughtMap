import SwiftUI

enum Palette {
    static let count = 12

    static let colors: [Color] = [
        Color(red: 0.96, green: 0.52, blue: 0.26), // 0 orange
        Color(red: 0.36, green: 0.55, blue: 0.96), // 1 blue
        Color(red: 0.22, green: 0.72, blue: 0.45), // 2 green
        Color(red: 0.90, green: 0.38, blue: 0.62), // 3 pink
        Color(red: 0.60, green: 0.42, blue: 0.92), // 4 violet
        Color(red: 0.93, green: 0.74, blue: 0.20), // 5 gold
        Color(red: 0.20, green: 0.70, blue: 0.82), // 6 teal
        Color(red: 0.62, green: 0.44, blue: 0.32), // 7 brown
        Color(red: 0.92, green: 0.30, blue: 0.30), // 8 red
        Color(red: 0.36, green: 0.40, blue: 0.86), // 9 indigo
        Color(red: 0.40, green: 0.82, blue: 0.70), // 10 mint
        Color(red: 0.62, green: 0.66, blue: 0.72)  // 11 slate
    ]

    static let names = ["Orange", "Blue", "Green", "Pink", "Violet", "Gold",
                        "Teal", "Brown", "Red", "Indigo", "Mint", "Slate"]

    static func color(_ index: Int) -> Color {
        guard index >= 0 else { return Color.gray }
        return colors[index % colors.count]
    }
}

/// Picks a colour and icon that suit an area's purpose, e.g. Money → green + banknote.
enum AreaStyle {
    struct Style {
        let colorIndex: Int
        let symbol: String
    }

    private static let rules: [(keywords: [String], style: Style)] = [
        (["money", "finance", "invest", "saving", "budget", "income", "wealth"], Style(colorIndex: 2, symbol: "banknote")),
        (["cook", "food", "recipe", "kitchen", "meal", "baking"], Style(colorIndex: 0, symbol: "fork.knife")),
        (["learn", "study", "course", "school", "education", "language", "book", "read"], Style(colorIndex: 1, symbol: "book")),
        (["app", "tech", "code", "coding", "software", "computer", "programming"], Style(colorIndex: 4, symbol: "laptopcomputer")),
        (["work", "career", "job", "office", "business"], Style(colorIndex: 9, symbol: "briefcase")),
        (["health", "fitness", "gym", "run", "sport", "exercise", "body", "sleep"], Style(colorIndex: 8, symbol: "heart")),
        (["creative", "art", "music", "write", "writing", "design", "photo", "craft"], Style(colorIndex: 3, symbol: "paintpalette")),
        (["relationship", "family", "friend", "people", "social", "love"], Style(colorIndex: 3, symbol: "person.2")),
        (["home", "house", "garden", "chores", "diy"], Style(colorIndex: 7, symbol: "house")),
        (["travel", "trip", "holiday", "vacation", "places"], Style(colorIndex: 6, symbol: "airplane")),
        (["mind", "mental", "wellbeing", "meditation", "spiritual"], Style(colorIndex: 10, symbol: "leaf")),
        (["personal", "self", "life"], Style(colorIndex: 5, symbol: "person")),
        (["project", "idea"], Style(colorIndex: 5, symbol: "lightbulb"))
    ]

    static func guess(for name: String) -> Style? {
        let lower = name.lowercased()
        for rule in rules where rule.keywords.contains(where: { lower.contains($0) }) {
            return rule.style
        }
        return nil
    }

    /// Icons the person can choose from for an area.
    static let symbols = [
        "sparkles", "lightbulb", "banknote", "fork.knife", "book", "laptopcomputer",
        "briefcase", "heart", "paintpalette", "person.2", "house", "airplane",
        "leaf", "person", "music.note", "camera", "gamecontroller", "graduationcap",
        "hammer", "cart", "car", "pawprint", "globe", "star"
    ]
}

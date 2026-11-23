import Foundation

enum StudioLabels {
    static func title(_ key: String) -> String {
        switch key {
        case "minimal": return "Мінімалізм"
        case "cinema": return "Кінематографічний"
        case "vivid": return "Яскравий"
        case "peach": return "Персиковий"
        case "mint": return "Мʼятний"
        case "violet": return "Фіолетовий"
        case "blue": return "Синій"
        case "rose": return "Рожевий"
        case "following": return "Після підписки"
        case "everyone": return "Усі"
        case "nobody": return "Ніхто"
        case "fit": return "Повне зображення"
        case "square": return "Квадрат"
        case "portrait": return "Портрет"
        case "date": return "За датою"
        case "author": return "За автором"
        case "media": return "За типом медіа"
        default: return key
        }
    }
    static func key(_ title: String, among keys: [String]) -> String { keys.first { self.title($0) == title } ?? keys[0] }
}

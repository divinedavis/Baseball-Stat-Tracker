import Foundation

struct Player: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var number: Int
    var position: String

    init(id: UUID = UUID(), name: String, number: Int, position: String) {
        self.id = id
        self.name = name
        self.number = number
        self.position = position
    }
}

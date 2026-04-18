import Foundation

struct Player: Identifiable, Codable, Hashable {
    let id: UUID
    var name: String
    var number: Int
    var position: String
    var age: Int?
    var team: String?

    init(
        id: UUID = UUID(),
        name: String,
        number: Int,
        position: String,
        age: Int? = nil,
        team: String? = nil
    ) {
        self.id = id
        self.name = name
        self.number = number
        self.position = position
        self.age = age
        self.team = team
    }
}

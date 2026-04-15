import Foundation

struct Contact: Codable, Equatable {
    let id: UUID
    let firstName: String
    let phoneNumber: String  // E.164 format, e.g. "+601127388501"

    private enum CodingKeys: String, CodingKey {
        case id, firstName, phoneNumber
    }

    init(id: UUID = UUID(), firstName: String, phoneNumber: String) {
        self.id = id
        self.firstName = firstName
        self.phoneNumber = phoneNumber
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        firstName = try container.decode(String.self, forKey: .firstName)
        phoneNumber = try container.decode(String.self, forKey: .phoneNumber)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(firstName, forKey: .firstName)
        try container.encode(phoneNumber, forKey: .phoneNumber)
    }
}

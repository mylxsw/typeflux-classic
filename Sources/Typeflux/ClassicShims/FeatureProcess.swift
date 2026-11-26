import Foundation

enum FeatureProcess {
    enum Role { case host, settings }

    struct Command {
        let destination: Role
        let action: String
    }

    static var enabled: Bool { false }
    static var role: Role { .host }
    static func owns(_: Role) -> Bool { true }
    static func send(_: Command) {}
}

enum FeatureAuth {
    static func refresh(action _: String = "refresh") async -> Bool { false }
}

enum FeatureRPC {
    enum Failure: Error { case unavailable }
}

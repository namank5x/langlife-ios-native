import Foundation

enum SpeakSceneSeed {
    static let defaults: [SpeakScene] = [
        SpeakScene(
            id: UUID(uuidString: "11111111-1111-1111-1111-111111111111")!,
            title: "Bubble Tea Order",
            description: "",
            tags: [],
            level: .beginner,
            createdAt: nil
        ),
        SpeakScene(
            id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
            title: "Night Market Snacks",
            description: "",
            tags: [],
            level: .beginner,
            createdAt: nil
        ),
        SpeakScene(
            id: UUID(uuidString: "33333333-3333-3333-3333-333333333333")!,
            title: "MRT EasyCard Top-Up",
            description: "",
            tags: [],
            level: .beginner,
            createdAt: nil
        ),
        SpeakScene(
            id: UUID(uuidString: "44444444-4444-4444-4444-444444444444")!,
            title: "Convenience Store Checkout",
            description: "",
            tags: [],
            level: .beginner,
            createdAt: nil
        ),
        SpeakScene(
            id: UUID(uuidString: "55555555-5555-5555-5555-555555555555")!,
            title: "Restaurant Waiting List",
            description: "",
            tags: [],
            level: .beginner,
            createdAt: nil
        ),
        SpeakScene(
            id: UUID(uuidString: "66666666-6666-6666-6666-666666666666")!,
            title: "Directions to MRT",
            description: "",
            tags: [],
            level: .beginner,
            createdAt: nil
        )
    ]
}

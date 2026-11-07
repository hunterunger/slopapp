import Foundation

/// The measurements of a closed session, kept so "Restore Last Session" can bring them back.
/// Boards are matched to displays by a stable display id and pixel size: a board saved on a
/// display that's gone or changed resolution isn't restored (its pixels would be wrong).
public struct SavedSession: Codable, Equatable, Sendable {
    public struct Display: Codable, Equatable, Sendable {
        public var key: String
        public var width: Int
        public var height: Int
        public var board: Board

        public init(key: String, width: Int, height: Int, board: Board) {
            self.key = key
            self.width = width
            self.height = height
            self.board = board
        }
    }

    public var displays: [Display]

    public init(displays: [Display]) {
        self.displays = displays.filter { !$0.board.isEmpty }
    }

    public var isEmpty: Bool { displays.isEmpty }

    /// The saved board for a display, if it was saved at the same size.
    public func board(for key: String, width: Int, height: Int) -> Board? {
        displays.first { $0.key == key && $0.width == width && $0.height == height }?.board
    }

    public func encoded() -> Data? {
        try? JSONEncoder().encode(self)
    }

    public static func decode(_ data: Data?) -> SavedSession? {
        guard let data, let session = try? JSONDecoder().decode(SavedSession.self, from: data), !session.isEmpty else { return nil }
        return session
    }
}

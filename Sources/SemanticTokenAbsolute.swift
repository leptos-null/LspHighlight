import Foundation

public struct SemanticTokenAbsolute {
    /// zero-based
    public let line: Int
    /// zero-based
    public let startChar: Int
    public let length: Int
    public let type: SemanticTokenTypes
    public let modifiers: Set<SemanticTokenModifiers>
    
    public init(line: Int, startChar: Int, length: Int, type: SemanticTokenTypes, modifiers: Set<SemanticTokenModifiers>) {
        self.line = line
        self.startChar = startChar
        self.length = length
        self.type = type
        self.modifiers = modifiers
    }
}

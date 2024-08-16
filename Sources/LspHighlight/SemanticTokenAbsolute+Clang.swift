#if canImport(ClangWrapper)

import Foundation
import ClangWrapper

extension SemanticTokenAbsolute {
    /// - Parameters:
    ///   - line: The line to index into
    ///   - startIndexUTF8: The utf8 one-based index for the first character in the range (inclusive), or `nil` to start at the beginning of the line
    ///   - endIndexUTF8: The utf8 one-based index for the last character in the range (non-inclusive), or `nil` to end at the end of the line
    ///   - outputEncoding: The key path to the string view with which the result should be with respect to
    private static func translateClangRange<StringView: BidirectionalCollection>(line: String.SubSequence, startIndexUTF8: UInt32?, endIndexUTF8: UInt32?, outputEncoding: KeyPath<String.SubSequence, StringView> = \.self) -> (startChar: Int, length: Int)? where StringView.Index == String.SubSequence.Index {
        let inputLineView = line.utf8
        let outputLineView = line[keyPath: outputEncoding]
        
        let startIndex: StringView.Index
        if let startIndexUTF8 {
            guard let resolved = inputLineView.index(inputLineView.startIndex, offsetBy: Int(startIndexUTF8) - 1, limitedBy: inputLineView.endIndex) else {
                assertionFailure("Bounding error: \(startIndexUTF8 - 1) out of bounds (\(inputLineView.count))")
                return nil
            }
            startIndex = resolved
        } else {
            startIndex = inputLineView.startIndex
        }
        
        let endIndex: StringView.Index
        if let endIndexUTF8 {
            guard let resolved = inputLineView.index(inputLineView.startIndex, offsetBy: Int(endIndexUTF8) - 1, limitedBy: inputLineView.endIndex) else {
                assertionFailure("Bounding error: \(endIndexUTF8 - 1) out of bounds (\(inputLineView.count))")
                return nil
            }
            endIndex = resolved
        } else {
            endIndex = inputLineView.endIndex
        }
        
        return (
            outputLineView.distance(from: outputLineView.startIndex, to: startIndex),
            outputLineView.distance(from: startIndex, to: endIndex)
        )
    }
    
    static func translate<StringView: BidirectionalCollection>(_ tokens: [CWToken], for lines: [String.SubSequence], outputEncoding: KeyPath<String.SubSequence, StringView> = \.self) -> [Self] where StringView.Index == String.SubSequence.Index {
        tokens.flatMap { token -> [SemanticTokenAbsolute] in
            guard let type = SemanticTokenTypes(token.type) else { return [] }
            return (token.startLocation.line...token.endLocation.line).compactMap { oneBasedLineIndex in
                let lineIndex = Int(oneBasedLineIndex) - 1
                let translatedRange = Self.translateClangRange(
                    line: lines[lineIndex],
                    startIndexUTF8: (oneBasedLineIndex == token.startLocation.line) ? token.startLocation.column : nil,
                    endIndexUTF8: (oneBasedLineIndex == token.endLocation.line) ? token.endLocation.column : nil,
                    outputEncoding: outputEncoding
                )
                
                guard let translatedRange else { return nil }
                return SemanticTokenAbsolute(
                    line: lineIndex,
                    startChar: translatedRange.startChar, length: translatedRange.length,
                    type: type, modifiers: []
                )
            }
        }
    }
}

extension SemanticTokenTypes {
    init?(_ type: CWTokenType) {
        switch type {
        case .unknown: return nil
        case .comment: self = .comment
        case .keyword: self = .keyword
        case .operator: self = .operator
        case .literalString: self = .string
        case .literalCharacter: self = .number
        case .literalNumeric: self = .number
        case .preprocessingDirective: self = .macro
        case .inclusionDirective: self = .macro
        case .macroDefinition: self = .macro
        @unknown default:
            return nil
        }
    }
}

#endif /* canImport(ClangWrapper) */

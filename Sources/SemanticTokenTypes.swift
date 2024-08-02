import Foundation

public struct SemanticTokenTypes: RawRepresentable, Hashable {
    public let rawValue: String
    
    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

extension SemanticTokenTypes: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        self.init(rawValue: value)
    }
}

// https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#semanticTokenTypes
public extension SemanticTokenTypes {
    static let namespace: Self = "namespace"
    static let type: Self = "type"
    static let `class`: Self = "class"
    static let `enum`: Self = "enum"
    static let interface: Self = "interface"
    static let `struct`: Self = "struct"
    static let typeParameter: Self = "typeParameter"
    static let parameter: Self = "parameter"
    static let variable: Self = "variable"
    static let property: Self = "property"
    static let enumMember: Self = "enumMember"
    static let event: Self = "event"
    static let function: Self = "function"
    static let method: Self = "method"
    static let macro: Self = "macro"
    static let keyword: Self = "keyword"
    static let modifier: Self = "modifier"
    static let comment: Self = "comment"
    static let string: Self = "string"
    static let number: Self = "number"
    static let regexp: Self = "regexp"
    static let `operator`: Self = "operator"
}

// LSP 3.17.0 extension
public extension SemanticTokenTypes {
    static let decorator: Self = "decorator"
}

// clangd 12 extensions
// https://clangd.llvm.org/features#kinds
public extension SemanticTokenTypes {
    static let unknown: Self = "unknown"
    static let concept: Self = "concept"
}

// SourceKit extensions
public extension SemanticTokenTypes {
    static let identifier: Self = "identifier"
}

public extension SemanticTokenTypes {
    static let sourceKitCases: [Self] = [
        .namespace,
        .type,
        .class, // actor - this is for compatibility
        .class,
        .enum,
        .interface,
        .struct,
        .typeParameter,
        .parameter,
        .variable,
        .property,
        .enumMember,
        .event,
        .function,
        .method,
        .macro,
        .keyword,
        .modifier,
        .comment,
        .string,
        .number,
        .regexp,
        .operator,
        .decorator,
        .identifier,
    ]
}

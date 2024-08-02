import Foundation

public struct SemanticTokenModifiers: RawRepresentable, Hashable {
    public let rawValue: String
    
    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}

extension SemanticTokenModifiers: ExpressibleByStringLiteral {
    public init(stringLiteral value: String) {
        self.init(rawValue: value)
    }
}

// https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#semanticTokenModifiers
public extension SemanticTokenModifiers {
    static let declaration: Self = "declaration"
    static let definition: Self = "definition"
    static let readonly: Self = "readonly"
    static let `static`: Self = "static"
    static let deprecated: Self = "deprecated"
    static let abstract: Self = "abstract"
    static let async: Self = "async"
    static let modification: Self = "modification"
    static let documentation: Self = "documentation"
    static let defaultLibrary: Self = "defaultLibrary"
}

// clangd extensions
// https://clangd.llvm.org/features#modifiers
public extension SemanticTokenModifiers {
    static let deduced: Self = "deduced"
    static let virtual: Self = "virtual"
    static let dependentName: Self = "dependentName"
    static let usedAsMutableReference: Self = "usedAsMutableReference"
    static let usedAsMutablePointer: Self = "usedAsMutablePointer"
    static let constructorOrDestructor: Self = "constructorOrDestructor"
    static let userDefined: Self = "userDefined"
    static let functionScope: Self = "functionScope"
    static let classScope: Self = "classScope"
    static let fileScope: Self = "fileScope"
    static let globalScope: Self = "globalScope"
}

public extension SemanticTokenModifiers {
    static let sourceKitCases: [Self] = [
        .declaration,
        .definition,
        .readonly,
        .static,
        .deprecated,
        .abstract,
        .async,
        .modification,
        .documentation,
        .defaultLibrary,
    ]
}

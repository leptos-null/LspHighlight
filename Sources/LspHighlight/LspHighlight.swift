import Foundation
import ArgumentParser
import LanguageServerProtocol
import LanguageServerProtocolJSONRPC
import OSLog

// we just send a couple of requests right now - we don't need to support these messages right now
final class LspHandler: MessageHandler {
    private static let logger = Logger(subsystem: "null.leptos.LspHighlight", category: "LspHandler")
    
    func handle<Notification>(_ params: Notification, from clientID: ObjectIdentifier) where Notification: NotificationType {
        Self.logger.info("Got \(String(describing: params))")
    }
    
    func handle<Request>(_ params: Request, id: RequestID, from clientID: ObjectIdentifier, reply: @escaping (LSPResult<Request.Response>) -> Void) where Request: RequestType {
        Self.logger.info("Got \(String(describing: params))")
    }
}

@main
struct LspHighlight: ParsableCommand {
    private static var knownLanguageIds: [String] {
        Language.allKnownCases.map(\.rawValue)
    }
    
    @Option(
        name: [.customShort("S", allowingJoined: true), .customLong("lsp-server")],
        help: ArgumentHelp("Path to the LSP server", valueName: "path"),
        completion: .file()
    )
    var lspServerPath: String
    
    @Option(
        name: .customLong("Xlsp", withSingleDash: true),
        parsing: .unconditionalSingleValue,
        help: ArgumentHelp("Pass flag to the LSP server", valueName: "flag")
    )
    var lspServerFlags: [String] = []
    
    @Option(
        help: ArgumentHelp(
            "The LSP language identifier for the given source code file",
            discussion: "By default, the program attempts to select the language based on the file name"
        ),
        completion: .list(Self.knownLanguageIds)
    )
    var language: Language.LanguageId? = nil
    
    @Argument(
        help: ArgumentHelp("Path to the source code file"),
        completion: .file()
    )
    var filePath: String
    
    // based on
    // https://github.com/swiftlang/sourcekit-lsp/blob/swift-5.10.1-RELEASE/Sources/SKCore/BuildServerBuildSystem.swift#L318
    private static func makeJSONRPCBuildServer(client: MessageHandler, serverPath: URL, serverFlags: [String]) throws -> JSONRPCConnection {
        let clientToServer = Pipe()
        let serverToClient = Pipe()
        
        let connection = JSONRPCConnection(
            protocol: .lspProtocol,
            inFD: serverToClient.fileHandleForReading,
            outFD: clientToServer.fileHandleForWriting
        )
        
        connection.start(receiveHandler: client) {
            withExtendedLifetime((clientToServer, serverToClient)) {}
        }
        let process = Process()
        process.executableURL = serverPath
        process.arguments = serverFlags
        process.standardOutput = serverToClient
        process.standardInput = clientToServer
        process.terminationHandler = { process in
            print("build server exited: \(process.terminationReason) \(process.terminationStatus)")
            connection.close()
        }
        try process.run()
        return connection
    }
    
    mutating func run() throws {
        let lspServer = URL(fileURLWithPath: lspServerPath)
        let sourceFile = URL(fileURLWithPath: filePath)
        
        let sourceLanguage: Language
        if let language {
            sourceLanguage = Language(rawValue: language)
        } else if let language = Language(url: sourceFile) {
            sourceLanguage = language
        } else {
            throw ValidationError(
                "Unable to automatically determine language for \(sourceFile.lastPathComponent), explicitly set with '--language'"
            )
        }
        
        let handler = LspHandler()
        let connection = try Self.makeJSONRPCBuildServer(
            client: handler,
            serverPath: lspServer,
            serverFlags: lspServerFlags
        )
        
        let clientCapabilities = ClientCapabilities(
            textDocument: .init(
                semanticTokens: .init(
                    requests: .init(range: .bool(false), full: .bool(true)),
                    tokenTypes: SemanticTokenTypes.allKnownCases.map(\.rawValue),
                    tokenModifiers: SemanticTokenModifiers.allKnownCases.map(\.rawValue),
                    formats: [.relative]
                )
            )
        )
        
        let initRequest = InitializeRequest(
            rootURI: nil, // deprecated
            capabilities: clientCapabilities,
            workspaceFolders: nil
        )
        
        let initResponse = try connection.sendSync(initRequest)
        
        // sourcekit-lsp returns `nil` here, however it does provide tokens.
        // additionally, sourcekit-lsp will automatically call out to clangd
        // when needed, as well
        let semanticTokensProvider = initResponse.capabilities.semanticTokensProvider
        let tokenLegend = semanticTokensProvider?.legend ?? SemanticTokensLegend(
            tokenTypes: SemanticTokenTypes.sourceKitCases.map(\.rawValue),
            tokenModifiers: SemanticTokenModifiers.sourceKitCases.map(\.rawValue)
        )
        
        let sourceFileURI = DocumentURI(string: sourceFile.absoluteString)
        let sourceText = try String(contentsOf: sourceFile)
        
        let didOpenNotif = DidOpenTextDocumentNotification(
            textDocument: TextDocumentItem(
                uri: sourceFileURI, language: sourceLanguage,
                version: 0, text: sourceText
            )
        )
        connection.send(didOpenNotif)
        
        let semanticTokensRequest = DocumentSemanticTokensRequest(textDocument: TextDocumentIdentifier(sourceFileURI))
        let semanticTokensResponse = try connection.sendSync(semanticTokensRequest)
        
        guard let semanticTokensResponse else {
            Self.exit(withError: CleanExit.message("No semantic tokens response"))
        }
        let tokens = SemanticTokenAbsolute.decode(lspEncoded: semanticTokensResponse.data, tokenLegend: tokenLegend)
        Self.process(tokens: tokens, for: sourceText)
    }
    
    private static func process(tokens: [SemanticTokenAbsolute], for text: String) {
        let stapledTokens = StapledToken.staple(semanticTokens: tokens, to: text)
        
        let html: String = stapledTokens.reduce(into: "") { partialResult, token in
            // thanks to https://www.w3.org/International/questions/qa-escapes#use
            let cleanHtml = token.text.replacingCharacters([
                "<": "&lt;",
                ">": "&gt;",
                "&": "&amp;",
                "\"": "&quot;",
                "'": "&apos;",
            ])
            if let semanticToken = token.semanticToken {
                let classList = [ "lsp-type-\(semanticToken.type.rawValue)" ] + semanticToken.modifiers.map { "lsp-modifier-\($0.rawValue)" }
                partialResult.append("<span class=\"\(classList.joined(separator: " "))\">")
                partialResult.append(contentsOf: cleanHtml)
                partialResult.append("</span>")
            } else {
                partialResult.append(contentsOf: cleanHtml)
            }
        }
        
        print(html)
    }
}

extension StringProtocol {
    func replacingCharacters(_ map: [Character: String]) -> String {
        reduce(into: "") { partialResult, character in
            if let replacement = map[character] {
                partialResult.append(replacement)
            } else {
                partialResult.append(character)
            }
        }
    }
}

struct StapledToken {
    let text: String.SubSequence
    let semanticToken: SemanticTokenAbsolute?
    
    init(text: String.SubSequence, semanticToken: SemanticTokenAbsolute? = nil) {
        self.text = text
        self.semanticToken = semanticToken
    }
}

extension StapledToken {
    static func staple(semanticTokens: [SemanticTokenAbsolute], to text: String) -> [Self] {
        var result: [Self] = []
        var lastLine: Int = 0
        var lastChar: Int = 0
        
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        
        func stapleEmptyTokens(upToLineIndex endLine: Int) {
            for lineIndex in lastLine..<endLine {
                assert(lastLine == lineIndex)
                
                let line = lines[lastLine]
                guard let lastCharIndex = line.index(line.startIndex, offsetBy: lastChar, limitedBy: line.endIndex) else {
                    assertionFailure("bounding error")
                    continue
                }
                let remaining = line[lastCharIndex...]
                if !remaining.isEmpty {
                    result.append(.init(text: remaining))
                }
                let lineBreak = "\n"
                result.append(.init(text: lineBreak[...]))
                lastLine += 1
                lastChar = 0
            }
        }
        
        for semanticToken in semanticTokens {
            // assert order
            assert(semanticToken.line >= lastLine)
            
            stapleEmptyTokens(upToLineIndex: semanticToken.line)
            
            assert(semanticToken.line == lastLine)
            assert(semanticToken.startChar >= lastChar)
            
            let line = lines[lastLine]
            guard let emptyStart = line.index(line.startIndex, offsetBy: lastChar, limitedBy: line.endIndex),
                  let tokenStart = line.index(line.startIndex, offsetBy: semanticToken.startChar, limitedBy: line.endIndex),
                  let tokenEnd = line.index(tokenStart, offsetBy: semanticToken.length, limitedBy: line.endIndex) else {
                assertionFailure("bounding error")
                continue
            }
            
            let emptyChars = line[emptyStart..<tokenStart]
            if !emptyChars.isEmpty {
                result.append(.init(text: emptyChars))
            }
            
            result.append(.init(text: line[tokenStart..<tokenEnd], semanticToken: semanticToken))
            lastChar = semanticToken.startChar + semanticToken.length
        }
        
        // do another pass to catch the characters after the last semanticToken
        stapleEmptyTokens(upToLineIndex: lines.count)
        
        return result
    }
}

extension Language {
    // heuristic
    init?(url: URL) {
        switch url.pathExtension {
        case "swift": self = .swift
        case "c": self = .c
        case "cpp", "cc": self = .cpp
        case "m": self = .objective_c
        case "mm": self = .objective_cpp
        case "html": self = .html
        case "css": self = .css
        case "json": self = .json
        case "md": self = .markdown
        case "yml": self = .yaml
        case "xml": self = .xml
        default:
            return nil
        }
    }
}

extension Language {
    static let allKnownCases: [Self] = [
        .abap,
        .bat,
        .bibtex,
        .clojure,
        .coffeescript,
        .c,
        .cpp,
        .csharp,
        .css,
        .diff,
        .dart,
        .dockerfile,
        .fsharp,
        .git_commit,
        .git_rebase,
        .go,
        .groovy,
        .handlebars,
        .html,
        .ini,
        .java,
        .javaScript,
        .javaScriptReact,
        .json,
        .latex,
        .less,
        .lua,
        .makefile,
        .markdown,
        .objective_c,
        .objective_cpp,
        .perl,
        .perl6,
        .php,
        .powershell,
        .jade,
        .python,
        .r,
        .razor,
        .ruby,
        .rust,
        .scss,
        .sass,
        .scala,
        .shaderLab,
        .shellScript,
        .sql,
        .swift,
        .typeScript,
        .typeScriptReact,
        .tex,
        .vb,
        .xml,
        .xsl,
        .yaml,
    ]
}

extension SemanticTokenAbsolute {
    static func decode(lspEncoded: [UInt32], tokenLegend: SemanticTokensLegend) -> [Self] {
        let typeLegend: [SemanticTokenTypes] = tokenLegend.tokenTypes.map {
            SemanticTokenTypes(rawValue: $0)
        }
        let modifierLegend: [SemanticTokenModifiers] = tokenLegend.tokenModifiers.map {
            SemanticTokenModifiers(rawValue: $0)
        }
        
        var result: [Self] = []
        var previousLine: Int = 0
        var previousChar: Int = 0
        
        for headIndex in stride(from: 0, to: lspEncoded.count, by: 5) {
            // https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#tokenFormat
            let deltaLine = Int(lspEncoded[headIndex + 0])
            let deltaStartChar = Int(lspEncoded[headIndex + 1])
            let length = Int(lspEncoded[headIndex + 2])
            let tokenType = Int(lspEncoded[headIndex + 3])
            let tokenModifiers = Int(lspEncoded[headIndex + 4])
            
            let absoluteLine = previousLine + deltaLine
            let absoluteChar = (deltaLine == 0) ? previousChar + deltaStartChar : deltaStartChar
            
            let modifiers: Set<SemanticTokenModifiers> = stride(from: 0, to: tokenModifiers.bitWidth, by: 1)
                .filter { tokenModifiers & (1 << $0) != 0 }
                .map { modifierLegend[$0] }
                .reduce(into: []) { partialResult, modifier in
                    partialResult.insert(modifier)
                }
            
            result.append(.init(
                line: absoluteLine,
                startChar: absoluteChar,
                length: length,
                type: typeLegend[tokenType],
                modifiers: modifiers
            ))
            
            previousLine = absoluteLine
            previousChar = absoluteChar
        }
        
        return result
    }
}

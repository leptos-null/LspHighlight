import Foundation
import AppKit // for debugging with NSAttributedString
import ArgumentParser
import SourceKitLSP
import LanguageServerProtocol
import LanguageServerProtocolJSONRPC

// we just send a couple of requests right now - we don't need to support these messages right now
final class LspHandler: MessageHandler {
    func handle<Notification>(_ params: Notification, from clientID: ObjectIdentifier) where Notification: NotificationType {
        print("Got", params)
    }
    
    func handle<Request>(_ params: Request, id: RequestID, from clientID: ObjectIdentifier, reply: @escaping (LSPResult<Request.Response>) -> Void) where Request: RequestType {
        print("Got", params)
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
    
    @Option(completion: .list(Self.knownLanguageIds))
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
                    tokenTypes: SyntaxHighlightingToken.Kind.allCases.map(\._lspName),
                    tokenModifiers: SyntaxHighlightingToken.Modifiers.allModifiers.map(\._lspName!),
                    formats: [.relative]
                )
            )
        )
        
        let initRequest = InitializeRequest(
            rootURI: nil, // deprecated
            capabilities: clientCapabilities,
            workspaceFolders: nil
        )
        
        _ = connection.send(initRequest, queue: .main) { reply in
            let initResponse: InitializeRequest.Response
            do {
                initResponse = try reply.get()
            } catch {
                Self.exit(withError: error)
            }
            
            // sourcekit-lsp returns `nil` here, however it does provide tokens.
            // additionally, sourcekit-lsp will automatically call out to clangd
            // when needed, as well
            let semanticTokensProvider = initResponse.capabilities.semanticTokensProvider
            let tokenLegend = semanticTokensProvider?.legend ?? SemanticTokensLegend(
                tokenTypes: SyntaxHighlightingToken.Kind.allCases.map(\._lspName),
                tokenModifiers: SyntaxHighlightingToken.Modifiers.allModifiers.map(\._lspName!)
            )
            
            let sourceFileURI = DocumentURI(string: sourceFile.absoluteString)
            let sourceText = try! String(contentsOf: sourceFile)
            
            let didOpenNotif = DidOpenTextDocumentNotification(
                textDocument: TextDocumentItem(
                    uri: sourceFileURI, language: sourceLanguage,
                    version: 0, text: sourceText
                )
            )
            connection.send(didOpenNotif)
            
            let semanticTokensRequest = DocumentSemanticTokensRequest(textDocument: TextDocumentIdentifier(sourceFileURI))
            _ = connection.send(semanticTokensRequest, queue: .main) { result in
                let semanticTokensResponse: DocumentSemanticTokensResponse?
                do {
                    semanticTokensResponse = try result.get()
                } catch {
                    Self.exit(withError: error)
                }
                guard let semanticTokensResponse else {
                    Self.exit(withError: CleanExit.message("No semantic tokens response"))
                }
                let tokens: [SyntaxHighlightingToken] = Array(lspEncoded: semanticTokensResponse.data, tokenLegend: tokenLegend)
                Self.process(tokens: tokens, for: sourceText)
                Self.exit()
            }
        }
        
        dispatchMain()
    }
    
    private static func process(tokens: [SyntaxHighlightingToken], for text: String) {
        // outputting RTF for now for debugging
        
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        var attrLines = lines.map { AttributedString($0) }
        
        for token in tokens {
            let range = token.range
            var attrLine = attrLines[range.lowerBound.line]
            let head = attrLine.index(attrLine.startIndex, offsetByUnicodeScalars: range.lowerBound.utf16index)
            let tail = attrLine.index(attrLine.startIndex, offsetByUnicodeScalars: range.upperBound.utf16index)
            
            var attributes = AttributeContainer()
            switch token.kind {
            case .keyword:
                attributes.foregroundColor = NSColor.systemPink
            case .comment:
                attributes.foregroundColor = NSColor.systemGray
            case .string:
                attributes.foregroundColor = NSColor.systemOrange
            case .number:
                attributes.foregroundColor = NSColor.systemPurple
            case .enum:
                attributes.foregroundColor = NSColor.systemMint
            case .enumMember:
                attributes.foregroundColor = NSColor.systemGreen
            case .macro:
                attributes.foregroundColor = NSColor.systemBrown
            case .identifier:
                break
            default:
                attributes.foregroundColor = NSColor.systemIndigo
            }
            
            attrLine[head..<tail].mergeAttributes(attributes)
            attrLines[range.lowerBound.line] = attrLine
        }
        
        var gather = AttributedString()
        attrLines.forEach {
            gather.append($0)
            gather.append(AttributedString("\n"))
        }
        
        var globalContainer = AttributeContainer()
        globalContainer.font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
        gather.mergeAttributes(globalContainer)
        
        let nsAttributed = NSAttributedString(gather)
        let rtf = nsAttributed.rtf(from: NSRange(location: 0, length: nsAttributed.length))
        let random = UUID()
        let outputURL = URL(fileURLWithPath: "\(random.uuidString).rtf")
        try! rtf!.write(to: outputURL)
        print(outputURL.absoluteString)
        
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

extension Array where Element == SyntaxHighlightingToken {
    // designed to be the inverse of
    // https://github.com/swiftlang/sourcekit-lsp/blob/swift-5.10.1-RELEASE/Sources/SourceKitLSP/Swift/SyntaxHighlightingToken.swift#L192
    init(lspEncoded: [UInt32], tokenLegend: SemanticTokensLegend) {
        let typeLegend: [SyntaxHighlightingToken.Kind?] = tokenLegend.tokenTypes.map { tokenName in
            SyntaxHighlightingToken.Kind.allCases.first { $0._lspName == tokenName }
        }
        let modifierLegend: [SyntaxHighlightingToken.Modifiers?] = tokenLegend.tokenModifiers.map { tokenName in
            SyntaxHighlightingToken.Modifiers.allModifiers.first { $0._lspName == tokenName }
        }
        
        var previous = Position(line: 0, utf16index: 0)
        self.init()
        
        for headIndex in stride(from: 0, to: lspEncoded.count, by: 5) {
            // https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#tokenFormat
            let deltaLine = Int(lspEncoded[headIndex + 0])
            let deltaStartChar = Int(lspEncoded[headIndex + 1])
            let length = Int(lspEncoded[headIndex + 2])
            let tokenType = Int(lspEncoded[headIndex + 3])
            let tokenModifiers = lspEncoded[headIndex + 4]
            
            let position = Position(
                line: previous.line + deltaLine,
                utf16index: (deltaLine == 0) ? previous.utf16index + deltaStartChar : deltaStartChar
            )
            
            let modifiers: SyntaxHighlightingToken.Modifiers = stride(from: 0, to: tokenModifiers.bitWidth, by: 1)
                .filter { tokenModifiers & (1 << $0) != 0 }
                .map { modifierLegend[$0] }
                .reduce(into: []) { partialResult, modifier in
                    guard let modifier else { return }
                    partialResult.formUnion(modifier)
                }
            
            self.append(.init(
                start: position, utf16length: length,
                kind: typeLegend[tokenType]!,
                modifiers: modifiers
            ))
            previous = position
        }
    }
}

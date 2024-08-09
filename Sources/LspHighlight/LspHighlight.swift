import Foundation
import ArgumentParser
import ClangWrapper
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
            ),
            general: .init(
                positionEncodings: [.utf8, .utf16, .utf32]
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
        // https://microsoft.github.io/language-server-protocol/specifications/lsp/3.17/specification/#positionEncodingKind
        let positionEncoding = initResponse.capabilities.positionEncoding ?? .utf16
        
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
        let sourceLines = sourceText.split(separator: "\n", omittingEmptySubsequences: false)
        
        let semanticTokens = SemanticTokenAbsolute.decode(lspEncoded: semanticTokensResponse.data, tokenLegend: tokenLegend)
        
        let lexicalTokens: [SemanticTokenAbsolute]
        switch sourceLanguage {
        case .c, .cpp, .objective_c, .objective_cpp:
            // languages that we know of supported by libclang
            let clangTokens = try CWToken.tokens(forCommand: Self.compileCommandFor(sourceFile: sourceFile), isFull: true)
            if let clangTokens {
                lexicalTokens = switch positionEncoding {
                case .utf8:
                    SemanticTokenAbsolute.translate(clangTokens, for: sourceLines, outputEncoding: \.utf8)
                case .utf16:
                    SemanticTokenAbsolute.translate(clangTokens, for: sourceLines, outputEncoding: \.utf16)
                case .utf32:
                    SemanticTokenAbsolute.translate(clangTokens, for: sourceLines, outputEncoding: \.unicodeScalars)
                default:
                    SemanticTokenAbsolute.translate(clangTokens, for: sourceLines)
                }
            } else {
                assertionFailure("CWToken.tokens(forCommand:) failed")
                lexicalTokens = []
            }
        default:
            // no additional provider for lexical tokens
            lexicalTokens = []
        }
        
        let tokens = Self.combineTokens(semantic: semanticTokens, lexical: lexicalTokens)
        
        switch positionEncoding {
        case .utf8:
            Self.process(tokens: tokens, for: sourceLines, encodingView: \.utf8)
        case .utf16:
            Self.process(tokens: tokens, for: sourceLines, encodingView: \.utf16)
        case .utf32:
            // per Swift.String documentation:
            //   > A string's `unicodeScalars` property is a collection of Unicode scalar
            //   > values, the 21-bit codes that are the basic unit of Unicode. Each scalar
            //   > value is represented by a `Unicode.Scalar` instance and is equivalent to a
            //   > UTF-32 code unit.
            Self.process(tokens: tokens, for: sourceLines, encodingView: \.unicodeScalars)
        default:
            Self.process(tokens: tokens, for: sourceLines)
        }
    }
    
    private static func compilationDatabaseFor(sourceFile: URL, buildDirectory: URL?) -> CWCompilationDatabase? {
        // search behavior designed to match clangd
        
        if let buildDirectory, let database = CWCompilationDatabase(directory: buildDirectory) {
            return database
        }
        if let database = CWCompilationDatabase(directory: URL(fileURLWithPath: ".")) {
            return database
        }
        
        var searchPaths: [URL] = []
        for pathComponent in sourceFile.pathComponents {
            if let previous = searchPaths.last {
                searchPaths.append(previous.appendingPathComponent(pathComponent))
            } else {
                searchPaths.append(URL(fileURLWithPath: pathComponent))
            }
        }
        
        for path in searchPaths.reversed() {
            if let database = CWCompilationDatabase(directory: path) {
                return database
            }
        }
        return nil
    }
    
    private static func compileCommandFor(sourceFile: URL, buildDirectory: URL? = nil) throws -> [String] {
        let database = Self.compilationDatabaseFor(sourceFile: sourceFile, buildDirectory: buildDirectory)
        let databaseCommand: [String]?
        if let database {
            let commands = database.compileCommands(forFile: sourceFile)
            if commands.count > 1 {
                print("Warning: compilation database contains more than 1 command to compile file. Using the first one")
            }
            if let firstCommand = commands.first {
                databaseCommand = firstCommand.command
            } else {
                databaseCommand = nil
            }
        } else {
            databaseCommand = nil
        }
        
        // based on
        // https://github.com/llvm/llvm-project/blob/b6b0a240d0b51ce85624a65c6e43f501371bc61b/clang-tools-extra/clangd/CompileCommands.cpp#L199
        
        let baseCommand = databaseCommand ?? [ "clang", "--", sourceFile.absoluteURL.path ]
        let flagsEnd = baseCommand.firstIndex(of: "--") ?? baseCommand.endIndex
        let flagsPrefix = baseCommand[..<flagsEnd]
        
        var flagsToAdd: [String] = []
        
        /* currently we don't try to figure out the "resource-dir" (but clangd does) */
        
        // apparently, clang will check the "SDKROOT" environment variable for the SDK,
        // so if that is set, we don't need to pass the sysroot parameter
        if getenv("SDKROOT") == nil, !flagsPrefix.contains(where: { $0 == "-isysroot" || $0 == "--sysroot" || $0.hasPrefix("--sysroot=") }) {
            let sdkPath = try Self.xcrun([ "--show-sdk-path" ])
            flagsToAdd.append("-isysroot")
            flagsToAdd.append(sdkPath)
        }
        
        var adjustedFlags = baseCommand
        adjustedFlags.insert(contentsOf: flagsToAdd, at: flagsEnd)
        
        let compilerParam = adjustedFlags[0]
        if !compilerParam.contains("/") { // not a path - resolve with `xcrun`
            adjustedFlags[0] = try Self.xcrun([ "--find", compilerParam ])
        }
        
        return adjustedFlags
    }
    
    private static func combineTokens(semantic: [SemanticTokenAbsolute], lexical: [SemanticTokenAbsolute]) -> [SemanticTokenAbsolute] {
        var semanticPop = semantic
        var lexicalPop = lexical
        
        var result: [SemanticTokenAbsolute] = []
        
        while let semanticHead = semanticPop.first, let lexicalHead = lexicalPop.first {
            if lexicalHead.line < semanticHead.line {
                result.append(lexicalHead)
                lexicalPop.removeFirst()
                continue
            }
            if semanticHead.line < lexicalHead.line {
                result.append(semanticHead)
                semanticPop.removeFirst()
                continue
            }
            assert(semanticHead.line == lexicalHead.line)
            if lexicalHead.startChar < semanticHead.startChar {
                if lexicalHead.startChar + lexicalHead.length > semanticHead.startChar {
                    // lexical overlaps semantic, drop lexical
                    lexicalPop.removeFirst()
                    continue
                }
                result.append(lexicalHead)
                lexicalPop.removeFirst()
                continue
            }
            if semanticHead.startChar < lexicalHead.startChar {
                if semanticHead.startChar + semanticHead.length > lexicalHead.startChar {
                    // semantic overlaps lexical, drop lexical
                    lexicalPop.removeFirst()
                    continue
                }
                result.append(semanticHead)
                semanticPop.removeFirst()
                continue
            }
            assert(semanticHead.startChar == lexicalHead.startChar)
            if lexicalHead.length == 0 {
                // I'm not sure why this would be helpful, but emit the token since there's no overlap
                result.append(lexicalHead)
                lexicalPop.removeFirst()
                continue
            }
            if semanticHead.length == 0 {
                // I'm not sure why this would be helpful, but emit the token since there's no overlap
                result.append(semanticHead)
                semanticPop.removeFirst()
                continue
            }
            // lexical overlaps semantic, drop lexical
            lexicalPop.removeFirst()
        }
        
        result.append(contentsOf: semanticPop)
        result.append(contentsOf: lexicalPop)
        
        return result
    }
    
    private static func process<StringView: BidirectionalCollection>(tokens: [SemanticTokenAbsolute], for lines: [String.SubSequence], encodingView: KeyPath<String.SubSequence, StringView> = \.self) where StringView.Index == String.SubSequence.Index {
        let stapledTokens = StapledToken.staple(semanticTokens: tokens, to: lines, encodingView: encodingView)
        
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
    
    private static func xcrun(_ params: [String]) throws -> String {
        let xcrunStdout = Pipe()
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = params
        process.standardOutput = xcrunStdout
        try process.run()
        
        let data = try xcrunStdout.fileHandleForReading.readToEnd()
        process.waitUntilExit()
        
        guard let data else {
            throw CocoaError(.fileReadUnknown)
        }
        
        let result = String(decoding: data, as: UTF8.self)
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
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
    static func staple<StringView: BidirectionalCollection>(semanticTokens: [SemanticTokenAbsolute], to lines: [String.SubSequence], encodingView: KeyPath<String.SubSequence, StringView> = \.self) -> [Self] where StringView.Index == String.SubSequence.Index {
        var result: [Self] = []
        var lastLine: Int = 0
        var lastChar: Int = 0
        
        func stapleEmptyTokens(upToLineIndex endLine: Int) {
            for lineIndex in lastLine..<endLine {
                assert(lastLine == lineIndex)
                
                let line = lines[lastLine]
                let lineView = line[keyPath: encodingView]
                guard let lastCharIndex = lineView.index(lineView.startIndex, offsetBy: lastChar, limitedBy: lineView.endIndex) else {
                    assertionFailure("Bounding error: \(lastChar) out of bounds (\(lineView.count))")
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
            let lineView = line[keyPath: encodingView]
            guard let emptyStart = lineView.index(lineView.startIndex, offsetBy: lastChar, limitedBy: lineView.endIndex) else {
                assertionFailure("Bounding error: \(lastChar) out of bounds (\(lineView.count))")
                continue
            }
            guard let tokenStart = lineView.index(lineView.startIndex, offsetBy: semanticToken.startChar, limitedBy: lineView.endIndex) else {
                assertionFailure("Bounding error: \(semanticToken.startChar) out of bounds (\(lineView.count))")
                continue
            }
            guard let tokenEnd = lineView.index(tokenStart, offsetBy: semanticToken.length, limitedBy: lineView.endIndex) else {
                assertionFailure("Bounding error: \(semanticToken.startChar) + \(semanticToken.length) out of bounds (\(lineView.count))")
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

#if canImport(ClangWrapper)

import Foundation
import ClangWrapper

extension LspHighlight {
    static func clangTokensFor(sourceFile: URL, buildDirectory: URL? = nil) throws -> [CWToken]? {
        let command = try Self.compileCommandFor(sourceFile: sourceFile, buildDirectory: buildDirectory)
        return CWToken.tokens(forCommand: command, isFull: true)
    }
    
    private static func compileCommandFor(sourceFile: URL, buildDirectory: URL?) throws -> [String] {
        let database = Self.compilationDatabaseFor(sourceFile: sourceFile, buildDirectory: buildDirectory)
        let databaseCommand: [String]?
        if let database {
            let commands = database.compileCommands(forFile: sourceFile)
            if commands.count > 1 {
                print("Warning: compilation database contains more than 1 command to compile file. Using the first one", to: .standardError)
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

#endif /* canImport(ClangWrapper) */

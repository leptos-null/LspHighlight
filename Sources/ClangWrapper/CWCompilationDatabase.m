#import <ClangWrapper/CWCompilationDatabase.h>
#import <clang-c/CXCompilationDatabase.h>

#import "CWCompileCommand+Internal.h"

@implementation CWCompilationDatabase {
    CXCompilationDatabase _cxDatabase;
}

- (instancetype)initWithDirectory:(NSURL *)directory {
    if (self = [super init]) {
        CXCompilationDatabase cxDatabase = clang_CompilationDatabase_fromDirectory(directory.fileSystemRepresentation, NULL);
        if (cxDatabase == NULL) {
            return nil;
        }
        _cxDatabase = cxDatabase;
    }
    return self;
}

- (NSMutableArray<CWCompileCommand *> *)compileCommandsForFile:(NSURL *)fileURL {
    CXCompileCommands const commands = clang_CompilationDatabase_getCompileCommands(_cxDatabase, fileURL.fileSystemRepresentation);
    
    unsigned const commandCount = clang_CompileCommands_getSize(commands);
    
    NSMutableArray<CWCompileCommand *> *result = [NSMutableArray arrayWithCapacity:commandCount];
    
    for (unsigned commandIndex = 0; commandIndex < commandCount; commandIndex++) {
        CXCompileCommand *const command = clang_CompileCommands_getCommand(commands, commandIndex);
        unsigned const commandParamCount = clang_CompileCommand_getNumArgs(command);
        
        NSMutableArray<NSString *> *commandParams = [NSMutableArray arrayWithCapacity:commandParamCount];
        for (unsigned commandParamIndex = 0; commandParamIndex < commandParamCount; commandParamIndex++) {
            CXString const commandParam = clang_CompileCommand_getArg(command, commandParamIndex);
            
            commandParams[commandParamIndex] = [NSString stringWithUTF8String:clang_getCString(commandParam)];
            
            clang_disposeString(commandParam);
        }
        
        CXString const compileDirectory = clang_CompileCommand_getDirectory(command);
        CXString const compileFilename = clang_CompileCommand_getFilename(command);
        
        NSURL *directoryURL = [NSURL fileURLWithFileSystemRepresentation:clang_getCString(compileDirectory) isDirectory:YES relativeToURL:nil];
        NSURL *fileURL = [NSURL fileURLWithFileSystemRepresentation:clang_getCString(compileFilename) isDirectory:NO relativeToURL:directoryURL];
        
        result[commandIndex] = [[CWCompileCommand alloc] initWithCommand:commandParams workingDirectory:directoryURL sourceCodeFile:fileURL];
        
        clang_disposeString(compileFilename);
        clang_disposeString(compileDirectory);
    }
    
    clang_CompileCommands_dispose(commands);
    
    return result;
}

- (void)dealloc {
    clang_CompilationDatabase_dispose(_cxDatabase);
}

@end

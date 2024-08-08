#import <ClangWrapper/CWCompileCommand.h>
#import "CWCompileCommand+Internal.h"

@implementation CWCompileCommand
@end

@implementation CWCompileCommand (Internal)

- (instancetype)initWithCommand:(NSArray<NSString *> *)command workingDirectory:(NSURL *)workingDirectory sourceCodeFile:(NSURL *)sourceCodeFile {
    if (self = [super init]) {
        _command = command;
        _workingDirectory = workingDirectory;
        _sourceCodeFile = sourceCodeFile;
    }
    return self;
}

@end

#import <ClangWrapper/CWCompileCommand.h>

@interface CWCompileCommand (Internal)

- (nonnull instancetype)initWithCommand:(nonnull NSArray<NSString *> *)command workingDirectory:(nonnull NSURL *)workingDirectory sourceCodeFile:(nonnull NSURL *)sourceCodeFile;

@end

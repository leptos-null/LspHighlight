#import <Foundation/Foundation.h>
#import <ClangWrapper/CWCompileCommand.h>

@interface CWCompilationDatabase : NSObject

- (nullable instancetype)initWithDirectory:(nonnull NSURL *)directory;
- (nonnull NSArray<CWCompileCommand *> *)compileCommandsForFile:(nonnull NSURL *)fileURL;

@end

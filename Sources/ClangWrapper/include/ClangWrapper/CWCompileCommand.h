#import <Foundation/Foundation.h>

@interface CWCompileCommand : NSObject

/// Full command line parameters including the executable
@property (nonatomic, readonly, nonnull) NSArray<NSString *> *command;

@property (nonatomic, readonly, nonnull) NSURL *workingDirectory;
@property (nonatomic, readonly, nonnull) NSURL *sourceCodeFile;

@end

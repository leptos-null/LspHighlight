#import <Foundation/Foundation.h>
#import <ClangWrapper/CWCompileCommand.h>

struct CWFileLocation {
    /// one-based
    unsigned line;
    /// one-based
    unsigned column;
};

typedef NS_ENUM(NSUInteger, CWTokenType) {
    CWTokenTypeUnknown = 0,
    CWTokenTypeComment,
    CWTokenTypeKeyword,
    CWTokenTypeOperator,
    CWTokenTypeLiteralString,
    CWTokenTypeLiteralCharacter,
    CWTokenTypeLiteralNumeric,
    CWTokenTypePreprocessingDirective,
    CWTokenTypeInclusionDirective,
    CWTokenTypeMacroDefinition,
};

@interface CWToken : NSObject

@property (nonatomic) struct CWFileLocation startLocation;
@property (nonatomic) struct CWFileLocation endLocation;

@property (nonatomic) CWTokenType type;

+ (nullable NSArray<CWToken *> *)tokensForCommand:(nonnull CWCompileCommand *)command;

/// @param commands The parameters that would be passed on the command line to compile a source file
/// @param isFull @c YES if @c commands starts with the path to the compiler
+ (nullable NSArray<CWToken *> *)tokensForCommand:(nonnull NSArray<NSString *> *)commands isFull:(BOOL)isFull;

@end

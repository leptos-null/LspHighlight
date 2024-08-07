#import <Foundation/Foundation.h>

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

+ (nullable NSArray<CWToken *> *)tokensForCommand:(nonnull NSArray<NSString *> *)commands;

@end

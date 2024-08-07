#import <ClangWrapper/CWToken.h>
#import <clang-c/Index.h>

@implementation CWToken

+ (NSArray<CWToken *> *)tokensForCommand:(NSArray<NSString *> *)commands {
    NSUInteger const count = commands.count;
    const char **const bridge = malloc(sizeof(char *) * count);
    
    for (NSUInteger i = 0; i < count; i++) {
        bridge[i] = commands[i].UTF8String;
    }
    
    NSArray<CWToken *> *tokens = [self tokensForCommand:bridge count:(int)count];
    free(bridge);
    return tokens;
}

+ (NSArray<CWToken *> *)tokensForCommand:(const char *const *)commandLineParams count:(int)commandLineParamCount {
    int displayDiagnostics;
#if DEBUG
    displayDiagnostics = 1;
#else
    displayDiagnostics = 0;
#endif
    CXIndex const index = clang_createIndex(0, displayDiagnostics);
    
    CXTranslationUnit targetUnit = NULL;
    unsigned parseOptions = CXTranslationUnit_DetailedPreprocessingRecord | CXTranslationUnit_KeepGoing | CXTranslationUnit_IncludeAttributedTypes;
    enum CXErrorCode const parseCode = clang_parseTranslationUnit2(index, NULL, commandLineParams, commandLineParamCount, NULL, 0, parseOptions, &targetUnit);
    
    if (parseCode != CXError_Success) {
        return nil;
    }
    
    CXString targetFileName = clang_getTranslationUnitSpelling(targetUnit);
    CXFile targetFile = clang_getFile(targetUnit, clang_getCString(targetFileName));
    clang_disposeString(targetFileName);
    
    CXCursor initialCursor = clang_getTranslationUnitCursor(targetUnit);
    
    CXTranslationUnit cursorUnit = clang_Cursor_getTranslationUnit(initialCursor);
    CXSourceRange cursorRange = clang_getCursorExtent(initialCursor);
    
    CXToken *tokenArray = NULL;
    unsigned tokenCount = 0;
    clang_tokenize(cursorUnit, cursorRange, &tokenArray, &tokenCount);
    
    NSMutableArray<CWToken *> *result = [NSMutableArray arrayWithCapacity:tokenCount];
    
    CXCursor *cursors = malloc(sizeof(CXCursor) * tokenCount);
    clang_annotateTokens(cursorUnit, tokenArray, tokenCount, cursors);
    
    for (unsigned tokenIndex = 0; tokenIndex < tokenCount; tokenIndex++) {
        CXSourceRange tokenRange = clang_getTokenExtent(cursorUnit, tokenArray[tokenIndex]);
        
        CXSourceLocation tokenStart = clang_getRangeStart(tokenRange);
        CXSourceLocation tokenEnd = clang_getRangeEnd(tokenRange);
        
        struct CWFileLocation startLocation, endLocation;
        clang_getExpansionLocation(tokenStart, NULL, &startLocation.line, &startLocation.column, NULL);
        clang_getExpansionLocation(tokenEnd, NULL, &endLocation.line, &endLocation.column, NULL);
        
        CWToken *buildToken = [CWToken new];
        buildToken.startLocation = startLocation;
        buildToken.endLocation = endLocation;
        
        CXTokenKind const tokenKind = clang_getTokenKind(tokenArray[tokenIndex]);
        enum CXCursorKind const cursorKind = clang_getCursorKind(cursors[tokenIndex]);
        
        switch (cursorKind) {
            case CXCursor_IntegerLiteral:
                buildToken.type = CWTokenTypeLiteralNumeric;
                break;
            case CXCursor_FloatingLiteral:
                buildToken.type = CWTokenTypeLiteralNumeric;
                break;
            case CXCursor_StringLiteral:
            case CXCursor_ObjCStringLiteral:
                buildToken.type = CWTokenTypeLiteralString;
                break;
            case CXCursor_CharacterLiteral:
                buildToken.type = CWTokenTypeLiteralCharacter;
                break;
            case CXCursor_UnaryOperator:
            case CXCursor_BinaryOperator:
            case CXCursor_CompoundAssignOperator:
            case CXCursor_ConditionalOperator:
                buildToken.type = CWTokenTypeOperator;
                break;
            case CXCursor_ObjCSelfExpr:
                buildToken.type = CWTokenTypeKeyword;
                break;
            case CXCursor_PreprocessingDirective:
                buildToken.type = CWTokenTypePreprocessingDirective;
                break;
            case CXCursor_InclusionDirective:
                buildToken.type = CWTokenTypeInclusionDirective;
                break;
            case CXCursor_MacroDefinition:
                buildToken.type = CWTokenTypeMacroDefinition;
                break;
            default:
                break;
        }
        
        if (buildToken.type == CWTokenTypeUnknown) {
            switch (tokenKind) {
                case CXToken_Keyword:
                    buildToken.type = CWTokenTypeKeyword;
                    break;
                case CXToken_Comment:
                    buildToken.type = CWTokenTypeComment;
                    break;
                default:
                    break;
            }
        }
        
#if DEBUG
        CXString tokenSpelling = clang_getTokenSpelling(cursorUnit, tokenArray[tokenIndex]);
        
        const char *tokenKindSpelling = NULL;
        switch (tokenKind) {
            case CXToken_Punctuation:
                tokenKindSpelling = "Punctuation";
                break;
            case CXToken_Keyword:
                tokenKindSpelling = "Keyword";
                break;
            case CXToken_Identifier:
                tokenKindSpelling = "Identifier";
                break;
            case CXToken_Literal:
                tokenKindSpelling = "Literal";
                break;
            case CXToken_Comment:
                tokenKindSpelling = "Comment";
                break;
            default:
                break;
        }
        
        CXString cursorKindSpelling = clang_getCursorKindSpelling(cursorKind);
        printf("[%u:%u -> %u:%u] '%s' -> %s [%s]\n",
               startLocation.line, startLocation.column,
               endLocation.line, endLocation.column,
               clang_getCString(tokenSpelling), tokenKindSpelling, clang_getCString(cursorKindSpelling));
        
        clang_disposeString(cursorKindSpelling);
        clang_disposeString(tokenSpelling);
#endif
        [result addObject:buildToken];
    }
    
    free(cursors);
    clang_disposeTokens(cursorUnit, tokenArray, tokenCount);
    
    clang_disposeTranslationUnit(targetUnit);
    clang_disposeIndex(index);
    
    return result;
}

@end
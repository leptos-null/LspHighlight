import Foundation
import ArgumentParser

// inspired by https://github.com/leptos-null/HighlightCode

private struct SemanticDescriptor {
    var type: String?
    var modifiers: [String]
    
    init(_ type: String?, modifiers: [String] = []) {
        self.type = type
        self.modifiers = modifiers
    }
}

extension SemanticDescriptor {
    var selector: String {
        var result: String = ""
        if let type {
            result.append(".lsp-type-")
            result.append(type)
        }
        for modifier in modifiers {
            result.append(".lsp-modifier-")
            result.append(modifier)
        }
        return result
    }
}

@main
struct XcodeLspStyle: ParsableCommand {
    private static func cssColor(for colorDescriptor: String) -> String {
        let channelMax: UInt8 = 0xff
        
        let decimalChannels: [String] = colorDescriptor.components(separatedBy: " ")
        precondition(decimalChannels.count == 3 || decimalChannels.count == 4, "Color must have 3 channels and optionally an alpha channel")
        
        let hexChannels = decimalChannels
            .enumerated()
            .map { counter, decimal in
                guard let percentage = Double(decimal) else {
                    fatalError("Failed to convert '\(decimal)' to Double")
                }
                let scaled = UInt8(percentage * Double(channelMax))
                if counter == 3, scaled == channelMax {
                    // alpha component
                    return ""
                }
                return String(format: "%02x", scaled)
            }
        return "#" + hexChannels.joined()
    }
    
    static func cssFor(selectors: [String], cssColor: String) -> String {
        if selectors.isEmpty { return "" }
        return
"""
\(selectors.joined(separator: ",\n")) {
    color: \(cssColor);
}

"""
    }
    
    private static func cssFor(semanticDescriptors: [SemanticDescriptor], colorDescriptor: String) -> String {
        Self.cssFor(
            selectors: semanticDescriptors.map(\.selector),
            cssColor: Self.cssColor(for: colorDescriptor)
        )
    }
    
    private static func cssFor(semanticDescriptors: [SemanticDescriptor], colorMap: [String: String], key: String, automaticSystemVariant: Bool = false) -> [String] {
        var result: [String] = []
        
        if let primaryValue = colorMap[key] {
            let primary = Self.cssFor(semanticDescriptors: semanticDescriptors, colorDescriptor: primaryValue)
            result.append(primary)
        }
        
        if automaticSystemVariant, let systemValue = colorMap[key.appending(".system")] {
            let variants = semanticDescriptors.map {
                var copy = $0
                copy.modifiers.append("defaultLibrary")
                return copy
            }
            
            let system = Self.cssFor(semanticDescriptors: variants, colorDescriptor: systemValue)
            result.append(system)
        }
        
        return result
    }
    
    private static func cssForXcodeColorTheme(_ colorTheme: [String: Any]) -> String {
        let version = colorTheme["DVTFontAndColorVersion"] as? Int
        guard let version else {
            fatalError("Unsupported version: <nil>")
        }
        
        switch version {
        case 1:
            let colorMap = (colorTheme["DVTSourceTextSyntaxColors"] as? [String: String]) ?? [:]
            let styles: [[String]] = [
                Self.cssFor(semanticDescriptors: [ .init("modifier") ], colorMap: colorMap, key: "xcode.syntax.attribute", automaticSystemVariant: false),
                Self.cssFor(semanticDescriptors: [ .init("comment") ], colorMap: colorMap, key: "xcode.syntax.comment", automaticSystemVariant: false),
                Self.cssFor(semanticDescriptors: [ .init("keyword") ], colorMap: colorMap, key: "xcode.syntax.keyword", automaticSystemVariant: false),
                Self.cssFor(semanticDescriptors: [ .init("number") ], colorMap: colorMap, key: "xcode.syntax.number", automaticSystemVariant: false),
                Self.cssFor(semanticDescriptors: [ .init("regex") ], colorMap: colorMap, key: "xcode.syntax.regex", automaticSystemVariant: false),
                Self.cssFor(semanticDescriptors: [ .init("string") ], colorMap: colorMap, key: "xcode.syntax.string", automaticSystemVariant: false),
                
                Self.cssFor(semanticDescriptors: [ .init("class") ], colorMap: colorMap, key: "xcode.syntax.identifier.class", automaticSystemVariant: true),
                Self.cssFor(semanticDescriptors: [ .init("enumMember") ], colorMap: colorMap, key: "xcode.syntax.identifier.constant", automaticSystemVariant: true),
                Self.cssFor(semanticDescriptors: [ .init("function"), .init("method"), .init("property") ], colorMap: colorMap, key: "xcode.syntax.identifier.function", automaticSystemVariant: true),
                Self.cssFor(semanticDescriptors: [ .init("macro") ], colorMap: colorMap, key: "xcode.syntax.identifier.macro", automaticSystemVariant: true),
                Self.cssFor(semanticDescriptors: [ .init("type") ], colorMap: colorMap, key: "xcode.syntax.identifier.type", automaticSystemVariant: true),
                Self.cssFor(semanticDescriptors: [ .init("variable", modifiers: ["globalScope"]) ], colorMap: colorMap, key: "xcode.syntax.identifier.variable", automaticSystemVariant: true),
            ]
            
            return styles.flatMap { $0 }.joined()
        default:
            fatalError("Unsupported version: \(version)")
        }
    }
    
    @Argument(
        help: ArgumentHelp(
            "Path to the xccolortheme",
            discussion: "These can generally be found with `find $(xcode-select -p)/.. ~/Library/Developer/Xcode/UserData -name '*.xccolortheme' -type f`",
            valueName: "xccolortheme"
        ),
        completion: .file(extensions: ["xccolortheme"])
    )
    var colorThemePath: String
    
    mutating func run() throws {
        let url = URL(fileURLWithPath: colorThemePath)
        let data = try Data(contentsOf: url)
        let propertyList = try PropertyListSerialization.propertyList(from: data, format: nil)
        guard let colorTheme = propertyList as? [String: Any] else {
            fatalError("Unexpected xccolortheme format")
        }
        let css = Self.cssForXcodeColorTheme(colorTheme)
        print(css)
    }
}

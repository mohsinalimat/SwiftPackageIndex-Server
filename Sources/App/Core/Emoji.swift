import Foundation
import Vapor

fileprivate struct Emoji: Decodable {
    
    enum CodingKeys: String, CodingKey {
        case unicode = "emoji"
        case names = "aliases"
    }
    
    let unicode: String
    let names: [String]
    
}

struct EmojiStorage {
    
    static var current = EmojiStorage()
    var lookup: [String: String]
    var regularExpression: NSRegularExpression?
    
    init() {
        let pathToEmojiFile = Current.fileManager.workingDirectory()
            .appending("Resources/emoji.json")
        
        lookup = [:]
        regularExpression = nil
        
        do {
            let data = try Data(contentsOf: URL(fileURLWithPath: pathToEmojiFile))
            let emojis = try JSONDecoder().decode([Emoji].self, from: data)
            
            lookup = emojis.reduce(into: [String: String]()) { lookup, emoji in
                emoji.names.forEach {
                    lookup[":\($0):"] = emoji.unicode
                }
            }
            
            let escapedKeys = lookup.keys.map(NSRegularExpression.escapedPattern(for:))
            let pattern = "(" + escapedKeys.joined(separator: "|") + ")"
            regularExpression = try NSRegularExpression(pattern: pattern, options: [])
        } catch {
            print("🚨 Failed to decode emoji list: \(error)")
        }
    }
    
    func replace(inString string: String) -> String {
        guard let regEx = regularExpression else {
            return string
        }
        
        let nsRange = NSRange(location: 0, length: string.count)
        let results = regEx.matches(in: string, options: [], range: nsRange)
        
        var mutableString = string
        results.reversed().forEach { result in
            let shorthand = (string as NSString).substring(with: result.range)
            
            if let range = Range(result.range, in: mutableString), let unicode = lookup[shorthand] {
                mutableString = mutableString.replacingCharacters(in: range, with: unicode)
            }
        }
        
        return mutableString
    }
    
}

extension String {
    
    func replaceShorthandEmojis() -> String {
        return EmojiStorage.current.replace(inString: self)
    }
    
}

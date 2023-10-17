//
//  SourceEditorCommand.swift
//  CodableHelperEx
//
//  Created by Jiaxin Pu on 2023/10/8.
//

import Foundation
import XcodeKit

class SourceEditorCommand: NSObject, XCSourceEditorCommand {
    
    func perform(with invocation: XCSourceEditorCommandInvocation, completionHandler: @escaping (Error?) -> Void ) -> Void {
        // Implement your command here, invoking the completion handler when done. Pass it nil on success, and an NSError on failure.
        
        var lines = Array(invocation.buffer.lines) as! [String]
        
        //去除注释、空行、换行
        lines = lines.map { line in
            let line = line.replacingOccurrences(of: "\n", with: "")
                .replacingOccurrences(of: " ", with: "")
            if line.hasPrefix("//") {
                return ""
            } else {
                return line
            }
        }
        lines = lines.filter { !$0.isEmpty }
        var propertyEntities: [PropertyEntity] = []
        for line in lines {
            guard isProperty(line) else {
                continue
            }
            propertyEntities.append(transformToPropertyEntity(line))
        }
        if propertyEntities.isEmpty {
            completionHandler(nil)
            return
        }
        
        let originalLines = Array(invocation.buffer.lines) as! [String]
        var startIndex: Int = 0
        for (index, line) in originalLines.enumerated() {
            let lastPropertyName = propertyEntities.last?.propertyName ?? "xxxxxxxxxxxxxx"
            if line.contains(lastPropertyName) {
                startIndex = index + 1
                break
            }
        }
        
        let resultLines = invocation.buffer.lines
        resultLines.insert("\n", at: startIndex)
        startIndex += 1
        let codingKeys = getCodingKeysDefine(propertyEntities)
        for item in codingKeys {
            resultLines.insert(item, at: startIndex)
            startIndex += 1
        }
        
        resultLines.insert("\n", at: startIndex)
        startIndex += 1
        let initItems = getInitFuncString(propertyEntities)
        for item in initItems {
            resultLines.insert(item, at: startIndex)
            startIndex += 1
        }
        
        resultLines.insert("\n", at: startIndex)
        startIndex += 1
        let encodeItems = getEncodeFuncDefine(propertyEntities)
        for item in encodeItems {
            resultLines.insert(item, at: startIndex)
            startIndex += 1
        }
        
        resultLines.insert("\n", at: startIndex)
        startIndex += 1
        let decodeItems = getDecodeFuncDefine(propertyEntities)
        for item in decodeItems {
            resultLines.insert(item, at: startIndex)
            startIndex += 1
        }
        
        completionHandler(nil)
    }
    
    
    func isProperty(_ string: String) -> Bool {
        var string = string
        var prefixs = ["public", "private", "internal", "open"]
        prefixs.forEach({ prefix in
            if string.hasPrefix(prefix) {
                string = String(string.dropFirst(prefix.count))
            }
        })
        return string.hasPrefix("let") || string.hasPrefix("var")
    }
    
//    let name: name?    // 这是name
//    let options: [[String: Any]]?    // 这是注释
    func transformToPropertyEntity(_ string: String) -> PropertyEntity {
        var string = deleteStringBeforePropertyTag(string)
        string = string.components(separatedBy: "//").first ?? ""
        var components = string.components(separatedBy: ":")
        let propertyName = components.first ?? ""
        components.removeFirst()
        components = components.filter { component in
            var component = component
            component = component.replacingOccurrences(of: " ", with: "")
            return !component.isEmpty
        }
        var className = components.reduce("") { partialResult, item in
            if !partialResult.isEmpty {
                return partialResult + ": " + item
            } else {
                return item
            }
        }
        var isOptional = false
        if className.contains("?") {
            print("before: \(className)")
            className = className.components(separatedBy: "?").first ?? ""
            print("after: \(className)")
            isOptional = true
        }
        return .init(propertyName: propertyName, className: className, isOptional: isOptional)
    }
    
    func deleteStringBeforePropertyTag(_ string: String) -> String {
        var string = string
        var prefixs = ["public", "private", "internal", "open"]
        prefixs.forEach({ prefix in
            if string.hasPrefix(prefix) {
                string = String(string.dropFirst(prefix.count))
            }
        })
        string.removeSubrange(string.startIndex...string.index(string.startIndex, offsetBy: 2))
        return string
    }
    
//    enum CodingKeys: String, CodingKey {
//        case birthday,
//             distance
//    }
    func getCodingKeysDefine(_ entities: [PropertyEntity]) -> [String] {
        var result: [String] = []
        result.append("    enum CodingKeys: String, CodingKey {")
        for (index, entity) in entities.enumerated() {
            if index == 0 {
                result.append("        case \(entity.propertyName),")
            } else if index == entities.count - 1 {
                result.append("             \(entity.propertyName)")
            } else {
                result.append("             \(entity.propertyName),")
            }
        }
        result.append("    }")
        return result
    }
    
//    public init(
//        birthday: String?,
//        distance: Double? = nil
//    ) {
//        self.birthday = birthday
//        self.distance = distance
//    }
    func getInitFuncString(_ entities: [PropertyEntity]) -> [String] {
        var result: [String] = []
        result.append("    public init(")
        for (index, entity) in entities.enumerated() {
            if index == entities.count - 1 {
                result.append("        \(entity.propertyName): \(entity.className)\(entity.isOptional ? "?" : "")")
            } else {
                result.append("        \(entity.propertyName): \(entity.className)\(entity.isOptional ? "?" : ""),")
            }
        }
        result.append("    ) {")
        entities.forEach { entity in
            result.append("        self.\(entity.propertyName) = \(entity.propertyName)")
        }
        result.append("    }")
        return result
    }
    
//    public func encode(to encoder: Encoder) throws {
//        var container = encoder.container(keyedBy: CodingKeys.self)
//        try? container.encodeIfPresent(birthday, forKey: .birthday)
//    }
    func getEncodeFuncDefine(_ entities: [PropertyEntity]) -> [String] {
        var result: [String] = []
        result.append("    public func encode(to encoder: Encoder) throws {")
        result.append("        var container = encoder.container(keyedBy: CodingKeys.self)")
        entities.forEach { entity in
            if entity.isOptional {
                result.append("        try? container.encodeIfPresent(\(entity.propertyName), forKey: .\(entity.propertyName))")
            } else {
                result.append("        try? container.encode(\(entity.propertyName), forKey: .\(entity.propertyName))")
            }
        }
        result.append("    }")
        return result
    }
    
//    init(from decoder: Decoder) throws {
//        let container = try decoder.container(keyedBy: Key.self)
//        self.int = try container.decode(Int.self, forKey: .int)
//    }
    func getDecodeFuncDefine(_ entities: [PropertyEntity]) -> [String] {
        var result: [String] = []
        result.append("    init(from decoder: Decoder) throws {")
        result.append("        let container = try decoder.container(keyedBy: CodingKeys.self)")
        entities.forEach { entity in
            if entity.isOptional {
                result.append("        self.\(entity.propertyName) = try container.decodeIfPresent(\(entity.className).self, forKey: .\(entity.propertyName))")
            } else {
                result.append("        self.\(entity.propertyName) = try container.decode(\(entity.className).self, forKey: .\(entity.propertyName))")
            }
        }
        result.append("    }")
        return result
    }
}

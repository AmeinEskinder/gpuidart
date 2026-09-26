// External AX client. A permission denial is a failed probe, never an empty pass.
import ApplicationServices
import Foundation

enum ProbeError: Error { case failure(String), staleElement(String) }

func attribute(_ element: AXUIElement, _ key: String) throws -> CFTypeRef? {
    var value: CFTypeRef?
    let result = AXUIElementCopyAttributeValue(element, key as CFString, &value)
    if result == .invalidUIElement { throw ProbeError.staleElement(key) }
    if result == .attributeUnsupported || result == .noValue { return nil }
    guard result == .success else { throw ProbeError.failure("\(key): AXError \(result.rawValue)") }
    return value
}

func run(queryRestarts: [String]) throws {
    guard CommandLine.arguments.count == 6, let process = Int32(CommandLine.arguments[1]) else {
        throw ProbeError.failure("Usage: ax-probe PID OP NAME VALUE")
    }
    guard AXIsProcessTrusted() else {
        throw ProbeError.failure("AXIsProcessTrusted=false; external AX access requires Accessibility authorization")
    }
    let operation = CommandLine.arguments[2]
    let name = CommandLine.arguments[3]
    let value = CommandLine.arguments[4]
    let identifier = CommandLine.arguments[5]
    let app = AXUIElementCreateApplication(process)
    AXUIElementSetMessagingTimeout(app, 3)
    var elements: [(AXUIElement, Int?)] = []
    func visit(_ element: AXUIElement, _ parent: Int?) throws {
        guard elements.count < 4096 else { throw ProbeError.failure("AX tree exceeds probe bound") }
        let index = elements.count
        elements.append((element, parent))
        let children = try attribute(element, "AXChildren") as? [AXUIElement] ?? []
        for child in children { try visit(child, index) }
    }
    try visit(app, nil)
    func label(_ element: AXUIElement) throws -> String {
        let title = try attribute(element, "AXTitle") as? String ?? ""
        if !title.isEmpty { return title }
        return try attribute(element, "AXDescription") as? String ?? ""
    }
    var output: [String: Any] = ["api": "AXUIElement", "process": process, "query_restarts": queryRestarts]
    if operation == "query" {
        var nodes: [[String: Any]] = []
        for (element, parent) in elements {
            var node: [String: Any] = ["name": try label(element), "parent": parent as Any? ?? NSNull()]
            for (field, key) in [("role", "AXRole"), ("id", "AXIdentifier"), ("subrole", "AXSubrole"), ("modal", "AXModal"),
                                 ("value", "AXValue"), ("min", "AXMinValue"), ("max", "AXMaxValue"),
                                 ("enabled", "AXEnabled"), ("focused", "AXFocused"),
                                 ("selected", "AXSelected"), ("expanded", "AXExpanded")] {
                if let item = try attribute(element, key), item is String || item is NSNumber {
                    node[field] = item
                }
            }
            var actions: CFArray?
            let result = AXUIElementCopyActionNames(element, &actions)
            if result == .invalidUIElement { throw ProbeError.staleElement("AXActionNames") }
            guard result == .success || result == .notImplemented else {
                throw ProbeError.failure("AX actions: \(result.rawValue)")
            }
            node["actions"] = actions as? [String] ?? []
            nodes.append(node)
        }
        output["nodes"] = nodes
    } else {
        let matches = try elements.filter {
            if !identifier.isEmpty { return try attribute($0.0, "AXIdentifier") as? String == identifier }
            return try label($0.0) == name
        }
        guard matches.count == 1 else { throw ProbeError.failure("Expected one AX element named \(name), got \(matches.count)") }
        let element = matches[0].0
        let result: AXError
        switch operation {
        case "invoke", "toggle", "select": result = AXUIElementPerformAction(element, "AXPress" as CFString)
        case "set-value": result = AXUIElementSetAttributeValue(element, "AXValue" as CFString, value as CFString)
        case "set-range":
            guard let number = Double(value) else { throw ProbeError.failure("Invalid number") }
            result = AXUIElementSetAttributeValue(element, "AXValue" as CFString, NSNumber(value: number))
        case "focus": result = AXUIElementSetAttributeValue(element, "AXFocused" as CFString, kCFBooleanTrue)
        default: throw ProbeError.failure("Unknown operation \(operation)")
        }
        guard result == .success else { throw ProbeError.failure("AX action failed: \(result.rawValue)") }
        output["operation"] = operation
        output["accepted"] = true
    }
    let data = try JSONSerialization.data(withJSONObject: output, options: [.sortedKeys])
    print(String(decoding: data, as: UTF8.self))
}

// AX element handles can become invalid while a filtered viewport is replaced.
// Restart the entire read, retain every restart, and never retry a mutation.
var restarts: [String] = []
while true {
    do {
        try run(queryRestarts: restarts)
        break
    } catch ProbeError.staleElement(let attribute) {
        guard CommandLine.arguments.count > 2,
              CommandLine.arguments[2] == "query", restarts.count < 4 else {
            FileHandle.standardError.write(Data("Invalid AX element at \(attribute); query restarts=\(restarts)\n".utf8))
            exit(1)
        }
        restarts.append(attribute)
        Thread.sleep(forTimeInterval: 0.05)
    } catch {
        FileHandle.standardError.write(Data("\(error)\n".utf8))
        exit(1)
    }
}

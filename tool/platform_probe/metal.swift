import Foundation
import Metal

let devices = MTLCopyAllDevices().map { device in
    [
        "name": device.name,
        "registry_id": String(device.registryID),
        "low_power": device.isLowPower,
        "unified_memory": device.hasUnifiedMemory,
    ] as [String: Any]
}
let report: [String: Any] = [
    "default_device": MTLCreateSystemDefaultDevice()?.name as Any? ?? NSNull(),
    "devices": devices,
    "scope": "Metal device enumeration on this runner; no physical GPU or presentation claim",
]
let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
print(String(data: data, encoding: .utf8)!)

// Reads Apple Silicon temperature sensors via the IOHIDEventSystem private API.
// Works unprivileged: these sensors are readable without root.
import Foundation
import IOKit

let kHIDPage_AppleVendor: Int = 0xff00
let kHIDUsage_AppleVendor_TemperatureSensor: Int = 0x0005
let kIOHIDEventTypeTemperature: Int64 = 15
let kIOHIDEventFieldTemperatureLevel: Int32 = Int32(kIOHIDEventTypeTemperature << 16)

@_silgen_name("IOHIDEventSystemClientCreate")
func IOHIDEventSystemClientCreate(_ allocator: CFAllocator?) -> Unmanaged<AnyObject>?

@_silgen_name("IOHIDEventSystemClientSetMatching")
func IOHIDEventSystemClientSetMatching(_ client: AnyObject?, _ match: CFDictionary?) -> Int32

@_silgen_name("IOHIDEventSystemClientCopyServices")
func IOHIDEventSystemClientCopyServices(_ client: AnyObject?) -> CFArray?

@_silgen_name("IOHIDServiceClientCopyProperty")
func IOHIDServiceClientCopyProperty(_ service: AnyObject?, _ key: CFString) -> CFTypeRef?

@_silgen_name("IOHIDServiceClientCopyEvent")
func IOHIDServiceClientCopyEvent(_ service: AnyObject?, _ type: Int64,
                                 _ options: Int32, _ timestamp: UInt64) -> AnyObject?

@_silgen_name("IOHIDEventGetFloatValue")
func IOHIDEventGetFloatValue(_ event: AnyObject?, _ field: Int32) -> Double

guard let clientRef = IOHIDEventSystemClientCreate(kCFAllocatorDefault) else {
    print("could not create IOHIDEventSystemClient")
    exit(1)
}
let client = clientRef.takeRetainedValue()

let matching: [String: Any] = [
    "PrimaryUsagePage": kHIDPage_AppleVendor,
    "PrimaryUsage": kHIDUsage_AppleVendor_TemperatureSensor,
]
_ = IOHIDEventSystemClientSetMatching(client, matching as CFDictionary)

guard let services = IOHIDEventSystemClientCopyServices(client) as? [AnyObject] else {
    print("no temperature services returned")
    exit(1)
}

var readings: [(String, Double)] = []
for service in services {
    guard let nameRef = IOHIDServiceClientCopyProperty(service, "Product" as CFString),
          let name = nameRef as? String else { continue }
    guard let event = IOHIDServiceClientCopyEvent(service, kIOHIDEventTypeTemperature, 0, 0)
    else { continue }
    let t = IOHIDEventGetFloatValue(event, kIOHIDEventFieldTemperatureLevel)
    if t > 0 && t < 200 { readings.append((name, t)) }
}

if readings.isEmpty {
    print("found \(services.count) sensor services but no readable temperatures")
    exit(1)
}

readings.sort { $0.1 > $1.1 }
let vals = readings.map { $0.1 }
// Die sensors (CPU/GPU cluster) only — excludes the PMU calibration reference,
// which reads high and would otherwise dominate the max.
let dieVals = readings.filter { $0.0.contains("tdie") || $0.0.contains("TP") }.map { $0.1 }
let dieMax = dieVals.max() ?? vals.max()!

// -q: "maxAll avgAll maxDie" on one line, for scripted sampling.
if CommandLine.arguments.contains("-q") {
    print(String(format: "%.1f %.1f %.1f",
                 vals.max()!, vals.reduce(0,+) / Double(vals.count), dieMax))
} else {
    for (name, t) in readings {
        print(String(format: "%-28s %6.1f C", (name as NSString).utf8String!, t))
    }
    print(String(format: "\n%d sensors | max %.1f C | avg %.1f C | die max %.1f C",
                 vals.count, vals.max()!,
                 vals.reduce(0,+) / Double(vals.count), dieMax))
}

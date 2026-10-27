import Metal
import Foundation

let seconds = CommandLine.arguments.count > 1 ? (Double(CommandLine.arguments[1]) ?? 180) : 180

let src = """
#include <metal_stdlib>
using namespace metal;

kernel void burn(device float *out       [[buffer(0)]],
                 constant uint &iters    [[buffer(1)]],
                 uint gid                [[thread_position_in_grid]])
{
    float a = float(gid & 1023) * 0.000977f + 1.0f;
    float b = 1.0000001f;
    float c = 0.9999999f;
    float d = a * 0.5f;
    for (uint i = 0; i < iters; i++) {
        a = fma(a, b, c);
        d = fma(d, c, b);
        a = fma(a, c, d);
        d = fma(d, b, a);
        a = a * 0.5f + 0.25f;
        d = d * 0.5f + 0.25f;
    }
    out[gid] = a + d;
}
"""

guard let dev = MTLCreateSystemDefaultDevice() else {
    FileHandle.standardError.write("no metal device\n".data(using: .utf8)!)
    exit(1)
}
let queue = dev.makeCommandQueue()!
let lib = try dev.makeLibrary(source: src, options: nil)
let pipe = try dev.makeComputePipelineState(function: lib.makeFunction(name: "burn")!)

let threads = 1 << 21
let out = dev.makeBuffer(length: threads * MemoryLayout<Float>.size,
                         options: .storageModePrivate)!
var iters: UInt32 = 8192
let tpg = MTLSize(width: pipe.maxTotalThreadsPerThreadgroup, height: 1, depth: 1)
let grid = MTLSize(width: threads, height: 1, depth: 1)

print("GPU: \(dev.name) — burning for \(Int(seconds))s (ctrl-C or kill to stop)")
fflush(stdout)

let deadline = Date().addingTimeInterval(seconds)
var passes = 0
let inFlight = 3

while Date() < deadline {
    var last: MTLCommandBuffer?
    for _ in 0..<inFlight {
        let cb = queue.makeCommandBuffer()!
        let enc = cb.makeComputeCommandEncoder()!
        enc.setComputePipelineState(pipe)
        enc.setBuffer(out, offset: 0, index: 0)
        enc.setBytes(&iters, length: MemoryLayout<UInt32>.size, index: 1)
        enc.dispatchThreads(grid, threadsPerThreadgroup: tpg)
        enc.endEncoding()
        cb.commit()
        last = cb
    }
    last?.waitUntilCompleted()
    passes += inFlight
}
print("GPU burn done — \(passes) dispatches")

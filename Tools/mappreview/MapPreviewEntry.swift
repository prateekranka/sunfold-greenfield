import Foundation

@main
struct MapPreview {
    static func main() {
        let seed: UInt64 = 20_260_726
        let step: Float = 1.5
        let floor: Float = 0.75
        let ceiling: Float = 0.80
        var failed = false

        print("seed \(seed)  step \(step)  target \(Int(floor * 100))–\(Int(ceiling * 100))%")
        print(String(repeating: "-", count: 64))

        for id in WorldMapID.allCases {
            let map = WorldMap.map(id, seed: seed)
            let vsBounds = map.landCoverage(step: step)
            let inBand = vsBounds >= floor && vsBounds <= ceiling
            if !inBand { failed = true }
            let flag = inBand ? "OK" : "OUT"
            let pct = String(format: "%.1f", vsBounds * 100)
            print("\(id.rawValue.padding(toLength: 11, withPad: " ", startingAt: 0))  map \(Int(map.bounds.x * 2))×\(Int(map.bounds.y * 2))  land@bounds \(pct)%  \(flag)")
        }

        print(String(repeating: "-", count: 64))
        if failed {
            fputs("FAIL: one or more layouts outside \(Int(floor * 100))–\(Int(ceiling * 100))% land@bounds\n", stderr)
            exit(1)
        }
        print("PASS")
    }
}

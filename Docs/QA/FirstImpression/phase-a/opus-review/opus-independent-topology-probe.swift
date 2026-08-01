import Foundation
import simd

// Independent Opus verification of the Riverlands void-water topology.
// Deliberately NOT reusing Luna A's test code — re-derived from isNavigableVoid.
@main struct Probe {
  static func main() {
    for (name, id) in [("riverlands", WorldMapID.riverlands), ("basin", .basin), ("fjords", .fjords)] {
      for seed in [UInt64(20_260_726), 1, 99_999] {
        let map = WorldMap.map(id, seed: seed)
        let step: Float = 1.0, margin: Float = 0.75
        let cols = Int(floor(map.bounds.x * 2 / step)) + 1
        let rows = Int(floor(map.bounds.y * 2 / step)) + 1
        func pt(_ c: Int, _ r: Int) -> WorldPoint {
          WorldPoint(-map.bounds.x + Float(c) * step, -map.bounds.y + Float(r) * step)
        }
        var nav = Set<Int>()
        for r in 0..<rows { for c in 0..<cols where map.isNavigableVoid(pt(c, r), margin: margin) { nav.insert(r*cols+c) } }
        var rest = nav, comps: [(n: Int, edge: Bool)] = []
        while let s = rest.first {
          var q = [s]; rest.remove(s); var n = 0; var edge = false
          while let cur = q.popLast() {
            n += 1
            let r = cur / cols, c = cur % cols
            if r == 0 || c == 0 || r == rows-1 || c == cols-1 { edge = true }
            for (dx,dy) in [(1,0),(-1,0),(0,1),(0,-1)] {
              let nc = c+dx, nr = r+dy
              guard nc >= 0, nc < cols, nr >= 0, nr < rows else { continue }
              let nb = nr*cols+nc
              if rest.remove(nb) != nil { q.append(nb) }
            }
          }
          comps.append((n, edge))
        }
        let interior = comps.filter { !$0.edge }
        let joined = (comps.contains { $0.edge } ? 1 : 0) + interior.count
        let flag = (name == "riverlands" && joined != 1) ? "  <<< FAIL" : ""
        print("\(name) seed=\(seed): raster=\(comps.count) edgeTouching=\(comps.filter{$0.edge}.count) interior=\(interior.map{$0.n}.sorted(by: >)) exteriorJoined=\(joined)\(flag)")
      }
    }
    // Determinism: same seed twice must give an identical map hash surface.
    let a = WorldMap.map(.riverlands, seed: 20_260_726), b = WorldMap.map(.riverlands, seed: 20_260_726)
    var same = true
    for i in stride(from: Float(-110), through: 110, by: 7.3) {
      for j in stride(from: Float(-110), through: 110, by: 7.3) {
        if a.waterDepth(at: WorldPoint(i,j)) != b.waterDepth(at: WorldPoint(i,j)) { same = false }
      }
    }
    print("determinism same-seed identical field: \(same)")
  }
}

import Foundation
import XCTest
import simd
@testable import SunfoldCore

/// Focused topology proof for the Riverlands void-water network.
final class TopologyTests: XCTestCase {

    func testRiverlandsVoidWaterIsOneConnectedNavigableNetwork() {
        let map = WorldMap.map(.riverlands, seed: 20_260_726)
        let step: Float = 1.0
        let margin: Float = 0.75
        let columns = Int(floor(map.bounds.x * 2 / step)) + 1
        let rows = Int(floor(map.bounds.y * 2 / step)) + 1

        func point(_ column: Int, _ row: Int) -> WorldPoint {
            WorldPoint(
                -map.bounds.x + Float(column) * step,
                -map.bounds.y + Float(row) * step
            )
        }

        func index(_ column: Int, _ row: Int) -> Int {
            row * columns + column
        }

        var navigable = Set<Int>()
        for row in 0..<rows {
            for column in 0..<columns where map.isNavigableVoid(point(column, row), margin: margin) {
                navigable.insert(index(column, row))
            }
        }

        var components: [[Int]] = []
        var remaining = navigable
        while let start = remaining.first {
            var queue = [start]
            remaining.remove(start)
            var cells: [Int] = []

            while let current = queue.popLast() {
                cells.append(current)
                let row = current / columns
                let column = current % columns
                for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                    let nextColumn = column + dx
                    let nextRow = row + dy
                    guard nextColumn >= 0, nextColumn < columns,
                          nextRow >= 0, nextRow < rows else { continue }
                    let neighbour = index(nextColumn, nextRow)
                    if remaining.remove(neighbour) != nil {
                        queue.append(neighbour)
                    }
                }
            }
            components.append(cells)
        }

        let perimeter = Set(
            (0..<columns).flatMap { column in
                [index(column, 0), index(column, rows - 1)]
            } + (1..<(rows - 1)).flatMap { row in
                [index(0, row), index(columns - 1, row)]
            }
        )
        let perimeterComponents = components.filter { $0.contains(where: perimeter.contains) }
        let outerComponent = Set(perimeterComponents.flatMap { $0 })
        XCTAssertFalse(outerComponent.isEmpty, "Riverlands must expose navigable void on its perimeter.")
        let internalComponents = components.filter { component in
            !perimeterComponents.contains { perimeterComponent in perimeterComponent == component }
        }
        let componentCountIncludingExterior = (perimeterComponents.isEmpty ? 0 : 1)
            + internalComponents.count
        XCTAssertEqual(
            componentCountIncludingExterior,
            1,
            "Riverlands navigable void must have one component after perimeter cells join the surrounding void; internal sizes: \(internalComponents.map(\.count).sorted(by: >))"
        )

        func nearestNavigableCell(to sample: WorldPoint) -> Int? {
            let centerColumn = Int(round((sample.x + map.bounds.x) / step))
            let centerRow = Int(round((sample.y + map.bounds.y) / step))
            var best: (distance: Float, cell: Int)?
            for row in (centerRow - 1)...(centerRow + 1) {
                for column in (centerColumn - 1)...(centerColumn + 1) {
                    guard column >= 0, column < columns, row >= 0, row < rows else { continue }
                    let cell = index(column, row)
                    guard navigable.contains(cell) else { continue }
                    let distance = simd_distance(point(column, row), sample)
                    if best == nil || distance < best!.distance {
                        best = (distance, cell)
                    }
                }
            }
            return best?.cell
        }

        for (home, expansion) in [(RegionID.sunwovenHome, RegionID.sunwovenExpansion),
                                   (.gravemarkHome, .gravemarkExpansion)] {
            let from = map.fragment(home).center
            let to = map.fragment(expansion).center
            let steps = 240
            let channelCell = (0...steps).compactMap { sampleIndex -> Int? in
                let sample = from + (to - from) * (Float(sampleIndex) / Float(steps))
                guard map.isNavigableVoid(sample, margin: margin) else { return nil }
                return nearestNavigableCell(to: sample)
            }.first

            XCTAssertNotNil(channelCell, "\(home)→\(expansion) must expose a navigable channel.")
            if let channelCell {
                XCTAssertTrue(
                    outerComponent.contains(channelCell),
                    "\(home)→\(expansion) channel must reach the outer void component."
                )
            }
        }

        print("Riverlands topology: rasterComponents=\(components.count), exteriorJoinedComponents=\(componentCountIncludingExterior), sizes=\(components.map(\.count).sorted(by: >)), channelsReachOuter=true")
    }
}

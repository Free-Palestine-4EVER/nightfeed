import CoreGraphics

/// Uniform spatial hash used for O(1)-amortized neighbor queries (enemy separation, local targeting)
/// instead of naive O(n^2) all-pairs checks across hundreds of enemies.
final class SpatialGrid {
    private let cellSize: CGFloat
    private var buckets: [Int64: [Enemy]] = [:]

    init(cellSize: CGFloat = 90) {
        self.cellSize = cellSize
    }

    private func cellCoord(for point: CGPoint) -> (Int, Int) {
        (Int(floor(point.x / cellSize)), Int(floor(point.y / cellSize)))
    }

    private func key(_ x: Int, _ y: Int) -> Int64 {
        (Int64(x) << 32) | Int64(UInt32(bitPattern: Int32(truncatingIfNeeded: y)))
    }

    func clear() {
        buckets.removeAll(keepingCapacity: true)
    }

    func insert(_ enemy: Enemy) {
        let (cx, cy) = cellCoord(for: enemy.position)
        buckets[key(cx, cy), default: []].append(enemy)
    }

    /// All enemies whose cell lies within `radius` of `point`. May include a few extra beyond the exact radius —
    /// callers that need a hard cutoff should re-check distance themselves.
    func neighbors(around point: CGPoint, radius: CGFloat) -> [Enemy] {
        let (cx, cy) = cellCoord(for: point)
        let span = max(1, Int(ceil(radius / cellSize)))
        var result: [Enemy] = []
        for dx in -span...span {
            for dy in -span...span {
                if let bucket = buckets[key(cx + dx, cy + dy)] {
                    result.append(contentsOf: bucket)
                }
            }
        }
        return result
    }
}

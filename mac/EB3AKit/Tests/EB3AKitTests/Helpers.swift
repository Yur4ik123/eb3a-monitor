import Foundation
@testable import EB3AKit

func fixture(_ name: String) throws -> [UInt16: UInt16] {
    let url = Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures")!
    let json = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
    let regs = json["regs"] as! [String: Int]
    return Dictionary(uniqueKeysWithValues: regs.map { (UInt16($0.key)!, UInt16($0.value)) })
}

let sampleTime = Date(timeIntervalSince1970: 1_000_000)

/// Стан з фікстури зі зміненими полями.
func sample(soc: Int = 100, solar: Int = 0, solarPresent: Bool = false, grid: Bool = true,
            acOut: Int = 21, at: Date = sampleTime) -> StationState {
    var r = try! fixture("after_app")
    r[43] = UInt16(soc); r[36] = UInt16(solar); r[44] = solarPresent ? 1 : 0
    r[45] = grid ? 1 : 0; r[37] = grid ? UInt16(acOut) : 0; r[38] = UInt16(acOut)
    return StationState(registers: r, at: at)!
}

import Foundation
import XCTest
@testable import NotchIsland

final class SystemFocusTests: XCTestCase {
    func testSystemStoreReportsActualModeAndRejectsUnreadableData() {
        let configuration = Data(#"{"data":[{"modeConfigurations":{"com.apple.focus.reduce-interruptions":{"mode":{"name":"减少打扰","symbolImageName":"moon.fill"}}}}]}"#.utf8)
        let assertions = Data(#"{"data":[{"storeAssertionRecords":[{"assertionDetails":{"assertionDetailsModeIdentifier":"com.apple.focus.reduce-interruptions"}}]}]}"#.utf8)
        XCTAssertEqual(SystemFocusState.read(assertions: assertions, configurations: configuration),
                       .active(.init(name: "减少打扰", symbol: "sparkles", reducesInterruptions: true)))
        XCTAssertEqual(SystemFocusState.read(assertions: nil, configurations: configuration), .unavailable)
        XCTAssertEqual(SystemFocusState.read(assertions: Data(#"{"data":[{"storeAssertionRecords":[]}]}"#.utf8),
                                             configurations: nil), .inactive)
    }

    func testMenuBarDescriptionDistinguishesModesAndUnknownValues() {
        XCTAssertEqual(SystemFocusState.menuItemDescription("专注模式"), .inactive)
        XCTAssertTrue(SystemFocusState.menuItemDescription("专注模式，减少打扰").mode?.reducesInterruptions == true)
        XCTAssertEqual(SystemFocusState.menuItemDescription("Focus, Writing").mode?.name, "Writing")
        XCTAssertEqual(SystemFocusState.menuItemDescription(""), .unavailable)
    }
}

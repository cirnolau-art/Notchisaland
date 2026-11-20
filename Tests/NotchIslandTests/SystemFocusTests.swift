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
        XCTAssertEqual(SystemFocusState.read(assertions: Data(#"{"data":[{"unexpectedField":[]}]}"#.utf8),
                                             configurations: nil), .unavailable)
        XCTAssertEqual(SystemFocusState.read(assertions: Data(#"{"data":[{"storeAssertionRecords":[]}]}"#.utf8),
                                             configurations: nil), .inactive)
    }

    func testMenuBarDescriptionDistinguishesModesAndUnknownValues() {
        XCTAssertEqual(SystemFocusState.menuItemDescription("专注模式"), .inactive)
        XCTAssertTrue(SystemFocusState.menuItemDescription("专注模式，减少打扰").mode?.reducesInterruptions == true)
        XCTAssertTrue(SystemFocusState.menuItemDescription("減少干擾，開啟").mode?.reducesInterruptions == true)
        XCTAssertTrue(SystemFocusState.menuItemDescription("Reduce Interruptions, On").mode?.reducesInterruptions == true)
        XCTAssertEqual(SystemFocusState.menuItemDescription("Focus, Writing").mode?.name, "Writing")
        XCTAssertEqual(SystemFocusState.menuItemDescription(""), .unavailable)
    }

    func testMenuPrefersModeNameAndExplicitOffState() {
        XCTAssertEqual(SystemFocusState.menuItemState(labels: ["Focus", "Writing"]).mode?.name, "Writing")
        XCTAssertEqual(SystemFocusState.menuItemState(labels: ["Focus, Off", "Writing"]), .inactive)
        XCTAssertEqual(SystemFocusState.menuItemState(labels: []), .unavailable)
    }

    func testLiveMenuStateTakesPrecedenceOverIncompleteStore() {
        let mode = SystemFocusState.active(.resolve(identifier: "", name: "减少打扰"))
        XCTAssertEqual(SystemFocusState.preferredState(store: .inactive, menu: mode, event: .inactive), mode)
        XCTAssertEqual(SystemFocusState.preferredState(store: .unavailable, menu: .needsAccessibility, event: .unavailable),
                       .needsAccessibility)
        XCTAssertEqual(SystemFocusState.preferredState(store: .unavailable, menu: .menuItemUnavailable, event: mode), mode)
    }
}

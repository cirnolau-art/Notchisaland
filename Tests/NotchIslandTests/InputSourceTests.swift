import AppKit
import Carbon.HIToolbox
import XCTest
@testable import NotchIsland

final class InputSourceTests: XCTestCase {
    @MainActor func testDistributedChangeIsDeliveredOnceAndStopsWithTheModule() {
        var source = ("ABC", "test.abc")
        let monitor = InputSourceMonitor { source }
        var observed: [String] = []
        monitor.onInputSourceChange = { observed.append($0) }
        monitor.start()
        defer { monitor.stop() }
        XCTAssertTrue(observed.isEmpty)

        func postSystemEvent() {
            CFNotificationCenterPostNotification(CFNotificationCenterGetDistributedCenter(),
                                                 CFNotificationName(kTISNotifySelectedKeyboardInputSourceChanged),
                                                 nil, nil, true)
        }
        source = ("简体拼音", "test.pinyin")
        postSystemEvent()
        NotificationCenter.default.post(name: NSTextInputContext.keyboardSelectionDidChangeNotification, object: nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        XCTAssertEqual(observed, ["简体拼音"])

        source = ("ABC", "test.abc")
        postSystemEvent()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        XCTAssertEqual(observed, ["简体拼音", "ABC"])

        monitor.stop()
        source = ("简体拼音", "test.pinyin")
        postSystemEvent()
        RunLoop.main.run(until: Date().addingTimeInterval(0.12))
        XCTAssertEqual(observed, ["简体拼音", "ABC"])
    }
}

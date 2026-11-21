import XCTest
@testable import NotchIsland

final class SecondBatchTests: XCTestCase {
    func testUnsupportedGlassResolvesToBlackWithoutChangingSavedPreference() {
        XCTAssertEqual(IslandPreferences.resolvedBackground(.glass, glassAvailable: false), .black)
        XCTAssertEqual(IslandPreferences.resolvedBackground(.glass, glassAvailable: true), .glass)
        XCTAssertEqual(IslandPreferences.resolvedBackground(.black, glassAvailable: true), .black)
    }
    func testGlassDimmingUsesATranslucentNativeTint() {
        let clear = IslandBackdropConfiguration(style: .glass, material: .clear, opacity: 0)
        let dimmed = IslandBackdropConfiguration(style: .glass, opacity: 1)
        XCTAssertNil(clear.nativeTint)
        XCTAssertGreaterThan(dimmed.nativeTint?.alphaComponent ?? 0, 0)
        XCTAssertLessThan(dimmed.nativeTint?.alphaComponent ?? 1, 1)
    }
    func testModernBannerTitleAndBodyAreNotMistakenForAppAndTitle() throws {
        let payload = try XCTUnwrap(BannerSemantics.modernPayload(title: "评审开始", body: "点击加入", description: "日历 评审开始, 点击加入"))
        XCTAssertEqual(payload.source, "日历"); XCTAssertEqual(payload.title, "评审开始"); XCTAssertEqual(payload.body, "点击加入")
        XCTAssertEqual(BannerSemantics.modernPayload(title: "隐私通知", body: "", description: "")?.source, "通知")
        XCTAssertNil(BannerSemantics.modernPayload(title: "", body: "", description: ""))
        XCTAssertEqual(BannerSemantics.modernPayload(title: "Meeting", body: "Soon", description: "", header: "Calendar")?.source, "Calendar")
    }
    func testSystemCustomDismissActionUsesExactNameAndNeverShowOrClearAll() {
        XCTAssertTrue(BannerSemantics.isDismissAction("Name:关闭\nTarget:0x0\nSelector:(null)"))
        XCTAssertTrue(BannerSemantics.isDismissAction("Name:Close\nTarget:0x0"))
        for name in ["显示详细信息", "Show", "Clear All", "全部清除", "AXPress", "Close Settings"] { XCTAssertFalse(BannerSemantics.isDismissAction(name)) }
    }
    func testConferenceLinkSelectionPrefersMeetingLinkOverOtherLinks() {
        let url = IslandMeeting.meetingURL(["https://example.com/document", "会议 https://meet.google.com/abc-defg-hij", "https://us02web.zoom.us/j/123"])
        XCTAssertEqual(url?.host, "meet.google.com")
        XCTAssertNotNil(IslandMeeting.meetingURL(["https://us02web.zoom.us/j/123"]))
        XCTAssertNil(IslandMeeting.meetingURL(["https://meet.google.com.evil.test/x", "https://evilzoom.us/x", "file:///tmp/test", "javascript:alert(1)"]))
    }
    func testMeetingCountdownRespectsStartEndAndMinuteRounding() {
        let now = Date(timeIntervalSince1970: 10000)
        let meeting = IslandMeeting(id: "event", title: "Call", start: now.addingTimeInterval(301), end: now.addingTimeInterval(3600), calendar: "Work", location: "", link: nil)
        XCTAssertEqual(meeting.countdown(at: now), "6 分钟后")
        XCTAssertEqual(meeting.countdown(at: now.addingTimeInterval(280)), "不到 1 分钟后")
        XCTAssertEqual(meeting.countdown(at: now.addingTimeInterval(301)), "正在进行")
        XCTAssertEqual(meeting.countdown(at: now.addingTimeInterval(3600)), "已结束")
    }
    func testShortcutNameSurvivesURLReservedCharactersAndUnicode() throws {
        let name = "今日计划 & 音乐 + #1 / 中文?"
        let action = IslandQuickAction(title: name, kind: .shortcut, target: name)
        let url = try XCTUnwrap(action.launchURL)
        XCTAssertEqual(url.scheme, "shortcuts")
        XCTAssertEqual(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first?.value, name)
    }
    func testQuickActionsPersistOrderRemoveOnlyReferenceAndKeepCap() throws {
        let suite = "NotchIsland.quick.tests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite)); defer { defaults.removePersistentDomain(forName: suite) }
        let actions = QuickActions(defaults: defaults)
        for item in actions.actions { actions.remove(item.id) }
        let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: true); defer { try? FileManager.default.removeItem(at: temporary) }
        XCTAssertTrue(actions.add(.init(title: "Folder", kind: .folder, target: temporary.path)))
        XCTAssertFalse(actions.add(.init(title: "Again", kind: .folder, target: temporary.path)))
        for i in 0..<5 { XCTAssertTrue(actions.add(.init(title: "Action \(i)", kind: .shortcut, target: "Action \(i)"))) }
        XCTAssertFalse(actions.add(.init(title: "Overflow", kind: .shortcut, target: "Overflow")))
        let first = actions.actions[0].id; actions.move(first, by: 1)
        let restored = QuickActions(defaults: defaults)
        XCTAssertEqual(restored.actions[1].id, first)
        restored.remove(first)
        XCTAssertTrue(FileManager.default.fileExists(atPath: temporary.path))
        XCTAssertEqual(QuickActions(defaults: defaults).actions.count, 5)
    }
}

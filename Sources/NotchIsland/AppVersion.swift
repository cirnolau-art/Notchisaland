import Foundation

enum AppVersion {
    static let release = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "开发版"
    static let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
    static var display: String { build.isEmpty ? release : "\(release) (\(build))" }
}

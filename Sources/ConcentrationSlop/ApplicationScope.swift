import Foundation

struct WorkApplication: Equatable, Sendable {
    let bundleID: String
    let name: String
}

struct ApplicationScope {
    private(set) var application: WorkApplication?
    private(set) var isManuallyHidden = false
    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let id = defaults.string(forKey: "workApplicationBundleID") {
            application = WorkApplication(bundleID: id, name: defaults.string(forKey: "workApplicationName") ?? id)
        }
    }

    mutating func bind(to application: WorkApplication?) {
        self.application = application
        isManuallyHidden = false
        defaults.set(application?.bundleID, forKey: "workApplicationBundleID")
        defaults.set(application?.name, forKey: "workApplicationName")
    }

    mutating func hide() { isManuallyHidden = true }
    mutating func show() { isManuallyHidden = false }

    func shouldShow(frontmostBundleID: String?, boundWindowIsOnScreen: Bool = true) -> Bool {
        guard !isManuallyHidden else { return false }
        guard let application else { return true }
        return frontmostBundleID == application.bundleID && boundWindowIsOnScreen
    }
}

import Foundation
import Testing
@testable import ConcentrationSlop

struct ApplicationScopeTests {
    private let ownID = "com.concentrationslop.macos"
    private let editor = WorkApplication(bundleID: "dev.zed.Zed", name: "Zed")

    @Test
    func followsOnlyTheBoundApplication() {
        let suite = "ScopeTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var scope = ApplicationScope(defaults: defaults)
        #expect(scope.shouldShow(frontmostBundleID: "com.google.Chrome"))
        scope.bind(to: editor)
        #expect(scope.shouldShow(frontmostBundleID: editor.bundleID))
        #expect(!scope.shouldShow(frontmostBundleID: ownID))
        #expect(!scope.shouldShow(frontmostBundleID: "com.google.Chrome"))
        #expect(!scope.shouldShow(frontmostBundleID: nil))
        #expect(ApplicationScope(defaults: defaults).application == editor)
    }

    @Test
    func staleActivationCannotReshowVideoOnADifferentSpace() {
        let suite = "SpaceRaceTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var scope = ApplicationScope(defaults: defaults)
        scope.bind(to: editor)
        #expect(scope.shouldShow(frontmostBundleID: editor.bundleID, boundWindowIsOnScreen: true))
        // The Space changed, but NSWorkspace still reports the outgoing work app.
        #expect(!scope.shouldShow(frontmostBundleID: editor.bundleID, boundWindowIsOnScreen: false))
        #expect(!scope.shouldShow(frontmostBundleID: "com.google.Chrome", boundWindowIsOnScreen: false))
        #expect(scope.shouldShow(frontmostBundleID: editor.bundleID, boundWindowIsOnScreen: true))
        scope.bind(to: nil)
        #expect(scope.shouldShow(frontmostBundleID: editor.bundleID, boundWindowIsOnScreen: false))
    }

    @Test
    func manualHideSurvivesSwitchingAndUnbindingRestoresGlobalVisibility() {
        let suite = "ScopeTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var scope = ApplicationScope(defaults: defaults)
        scope.bind(to: editor)
        scope.hide()
        #expect(!scope.shouldShow(frontmostBundleID: editor.bundleID))
        #expect(!scope.shouldShow(frontmostBundleID: ownID))
        scope.show()
        #expect(scope.shouldShow(frontmostBundleID: editor.bundleID))
        scope.bind(to: nil)
        #expect(scope.shouldShow(frontmostBundleID: "com.google.Chrome"))
        #expect(ApplicationScope(defaults: defaults).application == nil)
    }
}

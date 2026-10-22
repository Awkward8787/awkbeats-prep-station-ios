import SwiftUI
import SwiftData

@main
struct PrepStationApp: App {
    let container: ModelContainer
    @StateObject private var reference = ReferencePlayer()
    @StateObject private var beatPlayer = BeatPlayer()

    init() {
        BeatFiles.prepare()
        let demo = LaunchFlags.demo
        if demo { BeatFiles.root = FileManager.default.temporaryDirectory.appendingPathComponent("PrepStationDemo", isDirectory: true); BeatFiles.prepare() }
        let config = ModelConfiguration(isStoredInMemoryOnly: demo)
        do {
            container = try ModelContainer(for: Beat.self, configurations: config)
        } catch {
            fatalError("Could not open the beat library: \(error)")
        }
        if demo {
            UserDefaults.standard.register(defaults: ["producerName": "Awkward J"])
            DemoLibrary.seed(container.mainContext)
        }
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(reference)
                .environmentObject(beatPlayer)
                .preferredColorScheme(.dark)
                .tint(Theme.gold)
        }
        .modelContainer(container)
    }
}

enum LaunchFlags {
    static let args = ProcessInfo.processInfo.arguments
    static var demo: Bool { args.contains("-demo") }
    static var demoEmpty: Bool { args.contains("-demoEmpty") }
    static var demoDetail: Bool { args.contains("-demoDetail") || demoBottom }
    static var demoBottom: Bool { args.contains("-demoBottom") }
    static var demoSettings: Bool { args.contains("-demoSettings") }
    static var demoFilter: Bool { args.contains("-demoFilter") }
}

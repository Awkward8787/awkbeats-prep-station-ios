import SwiftUI
import SwiftData

enum LibrarySort: String, CaseIterable, Identifiable {
    case recent = "Recently added", title = "Title", bpm = "BPM", key = "Key"
    var id: String { rawValue }
}

/// Pure filtering + sorting so it can be unit tested.
enum LibraryQuery {
    static func apply(_ beats: [Beat], search: String, status: BeatStatus?, sort: LibrarySort) -> [Beat] {
        let filtered = beats.filter { b in
            (status == nil || b.status == status) && b.matches(search: search)
        }
        switch sort {
        case .recent: return filtered.sorted { $0.importedAt > $1.importedAt }
        case .title: return filtered.sorted { $0.displayTitle.localizedCaseInsensitiveCompare($1.displayTitle) == .orderedAscending }
        case .bpm: return filtered.sorted { ($0.workingBpm ?? .infinity) < ($1.workingBpm ?? .infinity) }
        case .key: return filtered.sorted { camelotOrder($0.workingKey) < camelotOrder($1.workingKey) }
        }
    }

    static func camelotOrder(_ key: NamedKey?) -> Int {
        guard let code = key?.camelot, let n = Int(code.dropLast()) else { return 999 }
        return n * 2 + (code.hasSuffix("B") ? 1 : 0)
    }
}

struct LibraryView: View {
    @Environment(\.modelContext) private var context
    @Query private var beats: [Beat]
    @AppStorage("producerName") private var producerName = ""
    @AppStorage("librarySort") private var sortRaw = LibrarySort.recent.rawValue
    @State private var search = ""
    @State private var statusFilter: BeatStatus?
    @State private var showImporter = false
    @State private var showSettings = false
    @State private var path: [UUID] = []
    @State private var importError: String?
    @State private var importing = 0

    private var sort: LibrarySort { LibrarySort(rawValue: sortRaw) ?? .recent }
    private var visible: [Beat] { LibraryQuery.apply(beats, search: search, status: statusFilter, sort: sort) }

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if beats.isEmpty && importing == 0 {
                    EmptyLibraryView { showImporter = true }
                } else {
                    list
                }
            }
            .background(Theme.plum950.ignoresSafeArea())
            .navigationTitle("Prep Station")
            .toolbarBackground(Theme.plum900, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button { showSettings = true } label: { Image(systemName: "gearshape") }
                        .accessibilityLabel("Settings")
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if !beats.isEmpty {
                        Menu {
                            Picker("Sort by", selection: $sortRaw) {
                                ForEach(LibrarySort.allCases) { Text($0.rawValue).tag($0.rawValue) }
                            }
                        } label: { Image(systemName: "arrow.up.arrow.down") }
                        .accessibilityLabel("Sort")
                    }
                    Button { showImporter = true } label: { Image(systemName: "plus") }
                        .accessibilityLabel("Import beats")
                }
            }
            .navigationDestination(for: UUID.self) { id in
                if let beat = beats.first(where: { $0.id == id }) { BeatDetailView(beat: beat) }
            }
            .fileImporter(isPresented: $showImporter, allowedContentTypes: BeatImporter.supportedTypes, allowsMultipleSelection: true) { result in
                if case .success(let urls) = result { Task { await importAll(urls) } }
            }
            .sheet(isPresented: $showSettings) { SettingsView() }
            .alert("Couldn't import", isPresented: Binding(get: { importError != nil }, set: { if !$0 { importError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(importError ?? "") }
            .onAppear(perform: applyDemoFlags)
        }
    }

    private var list: some View {
        List {
            Section {
                StatusFilterBar(beats: beats, selection: $statusFilter)
                    .listRowInsets(EdgeInsets(top: 4, leading: 0, bottom: 8, trailing: 0))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            Section {
                if visible.isEmpty {
                    Text(search.isEmpty ? "No beats with this status yet." : "No beats match “\(search)”.")
                        .font(.subheadline).foregroundStyle(Theme.textFaint)
                        .listRowBackground(Theme.plum950)
                }
                ForEach(visible) { beat in
                    NavigationLink(value: beat.id) { BeatRow(beat: beat) }
                        .listRowBackground(Theme.plum950)
                        .listRowSeparatorTint(Theme.line)
                }
                .onDelete(perform: delete)
                if importing > 0 {
                    HStack(spacing: 10) {
                        ProgressView().tint(Theme.gold)
                        Text("Importing \(importing) \(importing == 1 ? "beat" : "beats")…").font(.subheadline).foregroundStyle(Theme.textDim)
                    }.listRowBackground(Theme.plum950)
                }
            } footer: {
                HStack { Spacer(); PoweredByAwkBeats(); Spacer() }.padding(.top, 24)
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always), prompt: "Title, artist, key or BPM")
    }

    private func importAll(_ urls: [URL]) async {
        importing += urls.count
        var failures: [String] = []
        for url in urls {
            do { try await BeatImporter.importFile(url, into: context, defaultProducer: producerName) }
            catch { failures.append(error.localizedDescription) }
            importing -= 1
        }
        if !failures.isEmpty { importError = failures.joined(separator: "\n") }
    }

    private func delete(_ offsets: IndexSet) {
        let list = visible
        for i in offsets {
            let beat = list[i]
            BeatFiles.remove(id: beat.id)
            context.delete(beat)
        }
        try? context.save()
    }

    private func applyDemoFlags() {
        if LaunchFlags.demoDetail, path.isEmpty, let first = visible.first { path = [first.id] }
        if LaunchFlags.demoSettings { showSettings = true }
        if LaunchFlags.demoFilter { statusFilter = .ready }
    }
}

struct StatusFilterBar: View {
    let beats: [Beat]
    @Binding var selection: BeatStatus?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip("All", count: beats.count, selected: selection == nil) { selection = nil }
                ForEach(BeatStatus.allCases) { s in
                    chip(s.label, count: beats.filter { $0.status == s }.count, selected: selection == s) {
                        selection = selection == s ? nil : s
                    }
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private func chip(_ label: String, count: Int, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(label).font(.subheadline.weight(selected ? .semibold : .regular))
                Text("\(count)").font(.caption.monospacedDigit()).foregroundStyle(selected ? Theme.goldText : Theme.textFaint)
            }
            .foregroundStyle(selected ? Theme.text : Theme.textDim)
            .padding(.horizontal, 12).padding(.vertical, 7)
            .background(selected ? Theme.plumActive : Theme.plum850, in: Capsule())
            .overlay(Capsule().strokeBorder(selected ? Theme.gold : Theme.line, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct BeatRow: View {
    let beat: Beat

    var body: some View {
        HStack(spacing: 12) {
            ArtworkThumb(beat: beat, size: 52)
            VStack(alignment: .leading, spacing: 4) {
                Text(beat.displayTitle).font(.body.weight(.semibold)).foregroundStyle(Theme.text).lineLimit(1)
                Text(byline).font(.footnote).foregroundStyle(Theme.textFaint).lineLimit(1)
                HStack(spacing: 6) {
                    StatusPill(status: beat.status)
                    if beat.tagsDirty && beat.tagsSavedAt != nil {
                        Text("Unsaved tags").font(.caption2).foregroundStyle(Theme.goldText)
                    }
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 6) {
                if beat.isAnalyzing {
                    ProgressView().controlSize(.small).tint(Theme.gold)
                } else {
                    Text(beat.workingBpm.map { "\(BpmMath.format($0)) BPM" } ?? "– BPM")
                        .font(.subheadline.weight(.semibold).monospacedDigit()).foregroundStyle(Theme.text)
                    if let key = beat.workingKey { CamelotBadge(code: key.camelot) }
                }
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
    }

    private var byline: String {
        let parts = [beat.artist, beat.producer.isEmpty ? "" : "prod. \(beat.producer)"].filter { !$0.isEmpty }
        if !parts.isEmpty { return parts.joined(separator: " · ") }
        return beat.workingKey?.name ?? beat.format.label
    }
}

struct ArtworkThumb: View {
    let beat: Beat
    var size: CGFloat
    var body: some View {
        Group {
            if beat.hasArtwork, let img = UIImage(contentsOfFile: beat.artworkURL.path) {
                Image(uiImage: img).resizable().scaledToFill()
            } else {
                ZStack {
                    Theme.plum800
                    Image(systemName: "waveform").font(.system(size: size * 0.38, weight: .medium)).foregroundStyle(Theme.textFaint)
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size > 100 ? 12 : 8, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: size > 100 ? 12 : 8, style: .continuous).strokeBorder(Theme.line))
        .id(beat.artworkVersion)
        .accessibilityHidden(true)
    }
}

struct EmptyLibraryView: View {
    var onImport: () -> Void
    var body: some View {
        VStack(spacing: 16) {
            Spacer()
            Image("AwkBeatsLogo").resizable().scaledToFit().frame(height: 72).accessibilityHidden(true)
            Text("Get your beats ready to send")
                .font(.title2.weight(.semibold)).foregroundStyle(Theme.text).multilineTextAlignment(.center)
            Text("Import a beat to find its key and BPM. Add the details and cover art, then save the tags into the file and share it.")
                .font(.subheadline).foregroundStyle(Theme.textDim).multilineTextAlignment(.center)
            Button(action: onImport) { Label("Import beats", systemImage: "square.and.arrow.down") }
                .buttonStyle(PrimaryButtonStyle()).padding(.top, 8)
            Text("MP3, WAV, FLAC, M4A or AIFF from Files. You can also share an audio file to Prep Station from another app.")
                .font(.footnote).foregroundStyle(Theme.textFaint).multilineTextAlignment(.center)
            Spacer()
            PoweredByAwkBeats().padding(.bottom, 8)
        }
        .padding(.horizontal, 32)
    }
}

import SwiftUI
import SwiftData
import PhotosUI

struct BeatDetailView: View {
    @Bindable var beat: Beat
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var reference: ReferencePlayer
    @EnvironmentObject private var player: BeatPlayer
    @State private var photo: PhotosPickerItem?
    @State private var saving = false
    @State private var saveMessage: String?
    @State private var saveError: String?
    @State private var showBpmEditor = false
    @State private var confirmRemove = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                header
                analysisCard
                hearCard
                detailsCard
                saveSection
                fileFooter
            }
            .padding(16)
        }
        .background(Theme.plum950.ignoresSafeArea())
        .navigationTitle(beat.displayTitle)
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(Theme.plum900, for: .navigationBar)
        .onChange(of: photo) { _, item in Task { await loadPhoto(item) } }
        .onDisappear { reference.stop(); if player.playingID == beat.id { player.stop() } }
        .sheet(isPresented: $showBpmEditor) {
            BpmEditor(beat: beat) { markDirty() }.presentationDetents([.height(300)])
        }
        .confirmationDialog("Remove \(beat.displayTitle) from Prep Station?", isPresented: $confirmRemove, titleVisibility: .visible) {
            Button("Remove", role: .destructive, action: remove)
        } message: { Text("This deletes Prep Station's copy. Files you already shared or saved elsewhere are not touched.") }
    }

    // MARK: Header

    private var header: some View {
        HStack(alignment: .top, spacing: 16) {
            PhotosPicker(selection: $photo, matching: .images) {
                ArtworkThumb(beat: beat, size: 116)
                    .overlay(alignment: .bottomTrailing) {
                        Image(systemName: beat.hasArtwork ? "pencil" : "photo.badge.plus")
                            .font(.caption.weight(.semibold)).foregroundStyle(Theme.goldInk)
                            .padding(6).background(Theme.gold, in: Circle()).padding(6)
                    }
            }
            .accessibilityLabel(beat.hasArtwork ? "Change cover art" : "Add cover art")
            VStack(alignment: .leading, spacing: 8) {
                TextField("Title", text: bind(\.title), axis: .vertical)
                    .font(.title3.weight(.semibold)).foregroundStyle(Theme.text)
                    .lineLimit(1...3)
                Menu {
                    Picker("Status", selection: Binding(get: { beat.status }, set: { beat.status = $0; touch() })) {
                        ForEach(BeatStatus.allCases) { Text($0.label).tag($0) }
                    }
                } label: {
                    HStack(spacing: 4) { StatusPill(status: beat.status); Image(systemName: "chevron.down").font(.caption2).foregroundStyle(Theme.textFaint) }
                }
                .accessibilityLabel("Status: \(beat.status.label)")
                Button { player.toggle(beat) } label: {
                    Label(player.playingID == beat.id ? "Pause beat" : "Play beat",
                          systemImage: player.playingID == beat.id ? "pause.fill" : "play.fill")
                        .font(.subheadline.weight(.semibold))
                }
                .foregroundStyle(Theme.goldText)
                .padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: Analysis

    private var analysisCard: some View {
        Card(title: "Key and tempo") {
            if beat.isAnalyzing {
                HStack(spacing: 10) { ProgressView().tint(Theme.gold); Text("Finding key and BPM…").foregroundStyle(Theme.textDim) }
            } else {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(beat.workingBpm.map(BpmMath.format) ?? "–")
                            .font(.system(size: 34, weight: .semibold).monospacedDigit()).foregroundStyle(Theme.text)
                        Text("BPM").font(.caption.weight(.semibold)).foregroundStyle(Theme.textFaint)
                        tempoScale
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Text(beat.workingKey?.name ?? "–")
                                .font(.title3.weight(.semibold)).foregroundStyle(Theme.text)
                                .minimumScaleFactor(0.8).lineLimit(1)
                        }
                        .frame(minHeight: 41, alignment: .bottomLeading)
                        if let key = beat.workingKey { CamelotBadge(code: key.camelot) }
                        keyMenu
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                if beat.analysisState == "failed" {
                    Text("Couldn't read this file's audio. You can still type the BPM and pick the key.")
                        .font(.footnote).foregroundStyle(Theme.danger)
                } else if beat.keyNeedsReview {
                    Label("Two keys scored close. Play the drone with the beat to check by ear.", systemImage: "ear")
                        .font(.footnote).foregroundStyle(Theme.textDim)
                }
                if let note = detectedNote {
                    Text(note).font(.footnote).foregroundStyle(Theme.textFaint)
                }
            }
        }
    }

    private var tempoScale: some View {
        HStack(spacing: 6) {
            ForEach([(0.5, "½×"), (1.0, "1×"), (2.0, "2×")], id: \.0) { scale, label in
                let selected = beat.bpmOverride == nil && beat.bpmScale == scale
                Button(label) {
                    beat.bpmOverride = nil; beat.bpmScale = scale; markDirty()
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(selected ? Theme.goldInk : Theme.textDim)
                .frame(width: 38, height: 28)
                .background(selected ? Theme.gold : Theme.plum800, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(selected ? Color.clear : Theme.lineControl))
                .disabled(beat.bpmDetected == nil)
                .accessibilityLabel(scale == 0.5 ? "Half time" : scale == 2 ? "Double time" : "Detected tempo")
            }
            Button { showBpmEditor = true } label: { Image(systemName: "pencil") }
                .font(.caption.weight(.semibold)).foregroundStyle(Theme.textDim)
                .frame(width: 32, height: 28)
                .background(beat.bpmOverride != nil ? Theme.plumActive : Theme.plum800, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(beat.bpmOverride != nil ? Theme.gold : Theme.lineControl))
                .accessibilityLabel("Type a BPM")
        }
        .buttonStyle(.plain)
    }

    private var keyMenu: some View {
        Menu {
            if beat.keyOverride != nil, let detected = Camelot.parse(beat.keyDetected) {
                Button("Use detected (\(detected.name))") { beat.keyOverride = nil; markDirty() }
            }
            ForEach(Camelot.allKeys, id: \.self) { key in
                Button("\(key.camelot)  \(key.name)") { beat.keyOverride = key.name; markDirty() }
            }
        } label: {
            Text("Change key").font(.caption.weight(.semibold)).foregroundStyle(Theme.textDim)
                .padding(.horizontal, 10).frame(height: 28)
                .background(Theme.plum800, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Theme.lineControl))
        }
    }

    private var detectedNote: String? {
        var parts: [String] = []
        if beat.bpmOverride != nil, let d = beat.bpmDetected { parts.append("Detected \(BpmMath.format(d)) BPM") }
        if beat.keyOverride != nil, let k = Camelot.parse(beat.keyDetected), k != beat.workingKey { parts.append("detected \(k.name)") }
        guard !parts.isEmpty else { return nil }
        let s = parts.joined(separator: ", ")
        return s.prefix(1).uppercased() + s.dropFirst() + "."
    }

    // MARK: Hear

    private var hearCard: some View {
        Card(title: "Hear the key") {
            if let key = beat.workingKey {
                HStack(spacing: 10) {
                    Button { reference.toggle(.chord, key: key) } label: {
                        Label(reference.playing == .chord ? "Stop" : "Chord", systemImage: "pianokeys")
                    }
                    .buttonStyle(SecondaryButtonStyle(minHeight: 46))
                    Button { reference.toggle(.drone, key: key) } label: {
                        Label(reference.playing == .drone ? "Stop drone" : "Drone", systemImage: reference.playing == .drone ? "stop.fill" : "waveform.path")
                    }
                    .buttonStyle(SecondaryButtonStyle(minHeight: 46))
                    .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(reference.playing == .drone ? Theme.gold : .clear, lineWidth: 1.5))
                }
                Text("\(key.root) \(key.mode == .minor ? "minor" : "major") chord: \(key.triad.map { Camelot.roots[$0] }.joined(separator: " – ")). Play the drone while the beat plays to check it by ear.")
                    .font(.footnote).foregroundStyle(Theme.textFaint)
            } else {
                Text("Pick a key above to hear its chord.").font(.footnote).foregroundStyle(Theme.textFaint)
            }
        }
    }

    // MARK: Details

    private var detailsCard: some View {
        Card(title: "Details") {
            field("Producer", text: bind(\.producer), prompt: "Your producer name")
            Divider().overlay(Theme.line)
            field("Artist", text: bind(\.artist), prompt: "Artist on this beat")
            Divider().overlay(Theme.line)
            field("Genre", text: bind(\.genre), prompt: "Trap, R&B, Drill…")
            Divider().overlay(Theme.line)
            VStack(alignment: .leading, spacing: 4) {
                Text("Notes").font(.caption).foregroundStyle(Theme.textFaint)
                TextField("Only in Prep Station, not written to the file", text: Binding(get: { beat.notes }, set: { beat.notes = $0; touch() }), axis: .vertical)
                    .lineLimit(1...4).foregroundStyle(Theme.text)
            }
        }
    }

    private func field(_ label: String, text: Binding<String>, prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.caption).foregroundStyle(Theme.textFaint)
            TextField(prompt, text: text)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .foregroundStyle(Theme.text)
        }
    }

    // MARK: Save + share

    private var saveSection: some View {
        VStack(spacing: 10) {
            Button { Task { await saveTags() } } label: {
                HStack(spacing: 8) {
                    if saving { ProgressView().tint(Theme.goldInk) }
                    Text(beat.tagsDirty ? "Save tags to file" : "Tags saved")
                }
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(saving || !beat.tagsDirty)
            .opacity(beat.tagsDirty ? 1 : 0.55)

            ShareLink(item: beat.fileURL, preview: SharePreview(beat.displayTitle)) {
                Label("Share file", systemImage: "square.and.arrow.up")
            }
            .buttonStyle(SecondaryButtonStyle())

            if let saveError {
                Text(saveError).font(.footnote).foregroundStyle(Theme.danger).frame(maxWidth: .infinity, alignment: .leading)
            } else if let saveMessage {
                Text(saveMessage).font(.footnote).foregroundStyle(Theme.mint).frame(maxWidth: .infinity, alignment: .leading)
            } else if beat.tagsDirty {
                Text(beat.tagsSavedAt == nil ? "Saves title, producer, artist, genre, BPM, key and cover art into the \(beat.format.label) file (\(beat.format.tagStandard))."
                                             : "You changed details since the last save.")
                    .font(.footnote).foregroundStyle(Theme.textFaint).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var fileFooter: some View {
        VStack(spacing: 14) {
            Text(fileInfo).font(.footnote.monospacedDigit()).foregroundStyle(Theme.textFaint)
            Button("Remove from Prep Station", role: .destructive) { confirmRemove = true }
                .font(.subheadline).foregroundStyle(Theme.danger)
            PoweredByAwkBeats().padding(.top, 8)
        }
        .padding(.top, 8)
    }

    private var fileInfo: String {
        var parts = [beat.fileName]
        if let d = beat.durationSec { parts.append(String(format: "%d:%02d", Int(d) / 60, Int(d) % 60)) }
        if let sr = beat.sampleRate { parts.append(String(format: "%.1f kHz", sr / 1000)) }
        parts.append(ByteCountFormatter.string(fromByteCount: Int64(beat.fileSize), countStyle: .file))
        return parts.joined(separator: " · ")
    }

    // MARK: Actions

    private func bind(_ keyPath: ReferenceWritableKeyPath<Beat, String>) -> Binding<String> {
        Binding(get: { beat[keyPath: keyPath] }, set: { beat[keyPath: keyPath] = $0; markDirty() })
    }

    private func touch() { beat.updatedAt = Date() }

    private func markDirty() {
        beat.tagsDirty = true
        saveMessage = nil
        touch()
    }

    private func saveTags() async {
        saving = true; saveError = nil
        defer { saving = false }
        do {
            try await TagWriter.write(beat.payload, to: beat.fileURL, format: beat.format)
            beat.tagsDirty = false
            beat.tagsSavedAt = Date()
            beat.fileSize = (try? FileManager.default.attributesOfItem(atPath: beat.fileURL.path)[.size] as? Int) ?? beat.fileSize
            try? context.save()
            saveMessage = "Saved into \(beat.fileName). Share it and the tags go with it."
        } catch {
            saveError = error.localizedDescription
        }
    }

    private func loadPhoto(_ item: PhotosPickerItem?) async {
        guard let item, let data = try? await item.loadTransferable(type: Data.self),
              let jpeg = ArtworkProcessor.normalized(data) else { return }
        do {
            try jpeg.write(to: beat.artworkURL, options: .atomic)
            beat.hasArtwork = true
            beat.artworkVersion += 1
            markDirty()
        } catch { saveError = "Couldn't save that image." }
        photo = nil
    }

    private func remove() {
        reference.stop(); player.stop()
        BeatFiles.remove(id: beat.id)
        context.delete(beat)
        try? context.save()
        dismiss()
    }
}

struct BpmEditor: View {
    let beat: Beat
    var onChange: () -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @FocusState private var focused: Bool

    private var value: Double? { Double(text.replacingOccurrences(of: ",", with: ".")) }
    private var valid: Bool { value.map(BpmMath.inRange) ?? false }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Type the BPM").font(.title3.weight(.semibold)).foregroundStyle(Theme.text)
            TextField("140", text: $text)
                .keyboardType(.decimalPad).focused($focused)
                .font(.title2.monospacedDigit())
                .padding(12)
                .background(Theme.plum850, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.lineControl))
            Text(text.isEmpty || valid ? "Between 40 and 300. Decimals like 93.5 are fine." : "BPM must be between 40 and 300.")
                .font(.footnote).foregroundStyle(text.isEmpty || valid ? Theme.textFaint : Theme.danger)
            HStack(spacing: 10) {
                if beat.bpmOverride != nil {
                    Button("Use detected") { beat.bpmOverride = nil; onChange(); dismiss() }.buttonStyle(SecondaryButtonStyle())
                }
                Button("Save") {
                    if let v = value, valid { beat.bpmOverride = BpmMath.round2(v); onChange() }
                    dismiss()
                }
                .buttonStyle(PrimaryButtonStyle()).disabled(!valid)
            }
        }
        .padding(24)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(Theme.plum900)
        .onAppear {
            if let b = beat.workingBpm { text = BpmMath.format(b) }
            focused = true
        }
    }
}

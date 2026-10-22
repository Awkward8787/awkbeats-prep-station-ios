import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Query private var beats: [Beat]
    @AppStorage("producerName") private var producerName = ""
    @State private var applied: Int?

    private var missing: [Beat] { beats.filter { $0.producer.trimmingCharacters(in: .whitespaces).isEmpty } }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Producer name", text: $producerName)
                        .textInputAutocapitalization(.words).autocorrectionDisabled()
                } header: { Text("Producer") } footer: {
                    Text("Filled in as the producer on every beat you import. The artist stays separate on each beat.")
                }
                if !producerName.trimmingCharacters(in: .whitespaces).isEmpty && !missing.isEmpty {
                    Section {
                        Button("Add \(producerName) to \(missing.count) \(missing.count == 1 ? "beat" : "beats") with no producer") {
                            for b in missing { b.producer = producerName; b.tagsDirty = true; b.updatedAt = Date() }
                            applied = missing.count
                            try? context.save()
                        }
                    }
                }
                if let applied {
                    Section { Text("Added to \(applied) \(applied == 1 ? "beat" : "beats"). Save tags on each to write it into the file.").foregroundStyle(Theme.textDim) }
                }
                Section("About") {
                    LabeledContent("Version", value: Bundle.main.versionLabel)
                    LabeledContent("Beats in library", value: "\(beats.count)")
                    Text("Key and BPM are found on your iPhone. Your files never leave it unless you share them.")
                        .font(.footnote).foregroundStyle(Theme.textDim)
                }
                Section {
                    HStack { Spacer(); PoweredByAwkBeats(); Spacer() }
                }
                .listRowBackground(Color.clear)
            }
            .scrollContentBackground(.hidden)
            .background(Theme.plum900.ignoresSafeArea())
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
        }
    }
}

extension Bundle {
    var versionLabel: String {
        let v = infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let b = infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(v) (\(b))"
    }
}

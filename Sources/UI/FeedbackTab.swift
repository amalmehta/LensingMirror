import AppKit
import SwiftUI

/// Notes about the app, saved on this Mac. Nothing is sent anywhere.
enum FeedbackStore {
    enum Kind: String, CaseIterable, Identifiable, Codable {
        case bug = "Bug", idea = "Idea", other = "Other"
        var id: String { rawValue }
        var color: Color { [.bug: Palette.feedbackBug, .idea: Palette.feedbackIdea, .other: Palette.feedbackOther][self]! }
    }

    struct Note: Codable { let date: Date; let kind: Kind; let text: String; let version: String }

    static var fileURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Lensing Mirror/Feedback.jsonl")
    }

    static func append(_ kind: Kind, _ text: String, to url: URL = fileURL) throws {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        var line = try encoder.encode(Note(date: Date(), kind: kind, text: text, version: version))
        line.append(0x0A)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: line)
        } else {
            try line.write(to: url)
        }
    }

    static func count(at url: URL = fileURL) -> Int {
        ((try? String(contentsOf: url, encoding: .utf8)) ?? "").split(separator: "\n").count
    }
}

/// A small tab on the window's right edge.
struct FeedbackTab: View {
    @State private var open = false

    var body: some View {
        Button { open.toggle() } label: {
            Text("Feedback")
                .font(.caption2.weight(.medium))
                .fixedSize()
                .rotationEffect(.degrees(-90))
                .frame(width: 20, height: 74)
        }
        .buttonStyle(.plain)
        .background(.ultraThinMaterial, in: UnevenRoundedRectangle(topLeadingRadius: 7, bottomLeadingRadius: 7))
        .environment(\.colorScheme, .dark)
        .opacity(open ? 1 : 0.6)
        .help("Send a note to yourself about the app")
        .popover(isPresented: $open, arrowEdge: .leading) { FeedbackForm(close: { open = false }) }
    }
}

private struct FeedbackForm: View {
    let close: () -> Void
    @State private var kind = FeedbackStore.Kind.idea
    @State private var text = ""
    @State private var saved = FeedbackStore.count()
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Feedback").font(.headline)
            HStack(spacing: 6) {
                ForEach(FeedbackStore.Kind.allCases) { k in
                    Button { kind = k } label: {
                        HStack(spacing: 5) {
                            Circle().fill(k.color).frame(width: 8, height: 8)
                            Text(k.rawValue)
                        }
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .background(kind == k ? k.color.opacity(0.25) : .clear, in: Capsule())
                        .overlay(Capsule().strokeBorder(k.color.opacity(kind == k ? 0.9 : 0.35)))
                    }
                    .buttonStyle(.plain)
                }
            }
            TextEditor(text: $text)
                .font(.body)
                .frame(width: 300, height: 110)
                .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(.quaternary))
            if let error { Text(error).font(.caption).foregroundStyle(.red) }
            HStack {
                Text(saved == 1 ? "1 note saved" : "\(saved) notes saved").font(.caption).foregroundStyle(.secondary)
                if saved > 0 {
                    Button("Show") { NSWorkspace.shared.activateFileViewerSelecting([FeedbackStore.fileURL]) }
                        .buttonStyle(.link).font(.caption)
                }
                Spacer()
                Button("Copy") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString("[\(kind.rawValue)] \(text)", forType: .string)
                }
                .disabled(text.isEmpty)
                Button("Save") {
                    do { try FeedbackStore.append(kind, text); text = ""; saved += 1; close() }
                    catch { self.error = error.localizedDescription }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            Text("Saved on this Mac only. Nothing is sent.").font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(14)
    }
}

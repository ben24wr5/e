import SwiftUI

struct Note: Identifiable, Codable, Hashable {
    var id = UUID()
    var text: String
    var modified: Date
    var isPinned = false

    var title: String {
        let line = text.split(whereSeparator: \.isNewline).first.map(String.init)?
            .trimmingCharacters(in: .whitespaces) ?? ""
        return line.isEmpty ? "New Note" : line
    }

    var preview: String {
        let lines = text.split(whereSeparator: \.isNewline).dropFirst()
        return lines.first.map { String($0).trimmingCharacters(in: .whitespaces) } ?? "No additional text"
    }
}

/// Orbit Notes, saved inside Orbit.
@MainActor
final class NotesStore: ObservableObject {
    @Published var notes: [Note] = [] {
        didSet { scheduleSave() }
    }

    private var saveTask: Task<Void, Never>?

    init() {
        notes = OrbitStorage.load([Note].self, from: "notes.json") ?? [
            Note(text: "Welcome to Orbit Notes\nYour notes are saved inside Orbit automatically.", modified: Date())
        ]
    }

    var sorted: [Note] {
        notes.sorted { a, b in
            if a.isPinned != b.isPinned { return a.isPinned }
            return a.modified > b.modified
        }
    }

    @discardableResult
    func create() -> Note {
        let note = Note(text: "", modified: Date())
        notes.append(note)
        return note
    }

    func update(_ id: Note.ID, text: String) {
        guard let index = notes.firstIndex(where: { $0.id == id }), notes[index].text != text else { return }
        notes[index].text = text
        notes[index].modified = Date()
    }

    func togglePin(_ id: Note.ID) {
        guard let index = notes.firstIndex(where: { $0.id == id }) else { return }
        notes[index].isPinned.toggle()
    }

    func delete(_ id: Note.ID) {
        notes.removeAll { $0.id == id }
    }

    private func scheduleSave() {
        saveTask?.cancel()
        let snapshot = notes
        saveTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            guard !Task.isCancelled else { return }
            OrbitStorage.save(snapshot, to: "notes.json")
        }
    }
}

struct NotesApp: View {
    @EnvironmentObject private var store: NotesStore
    @State private var selection: Note.ID?
    @State private var search = ""

    private var shown: [Note] {
        let q = search.trimmingCharacters(in: .whitespaces)
        let all = store.sorted
        return q.isEmpty ? all : all.filter { $0.text.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 280)
            Rectangle().fill(Theme.cardLine).frame(width: 1)
            editor
        }
        .background(Theme.background)
        .foregroundStyle(Theme.text)
        .navigationTitle("Notes")
        .onAppear {
            if selection == nil { selection = store.sorted.first?.id }
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            AppHeader(kind: .notes) {
                Button {
                    selection = store.create().id
                    search = ""
                } label: {
                    Image(systemName: "square.and.pencil")
                }
                .keyboardShortcut("n", modifiers: .command)
                .help("New note (⌘N)")
            }
            OrbitSearchField(prompt: "Search notes", text: $search)
                .padding(12)
            List(selection: $selection) {
                ForEach(shown) { note in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 4) {
                            if note.isPinned {
                                Image(systemName: "pin.fill").font(.system(size: 9)).foregroundStyle(OrbitAppKind.notes.tint)
                            }
                            Text(note.title).font(.orbit(14, .semibold)).lineLimit(1)
                        }
                        HStack(spacing: 6) {
                            Text(note.modified.formatted(date: .abbreviated, time: .omitted))
                            Text(note.preview).lineLimit(1)
                        }
                        .font(.orbit(12))
                        .foregroundStyle(Theme.secondary)
                    }
                    .padding(.vertical, 4)
                    .tag(note.id)
                    .contextMenu {
                        Button(note.isPinned ? "Unpin" : "Pin") { store.togglePin(note.id) }
                        Button("Delete", role: .destructive) { delete(note.id) }
                    }
                }
            }
            .scrollContentBackground(.hidden)
        }
    }

    @ViewBuilder private var editor: some View {
        if let id = selection, let note = store.notes.first(where: { $0.id == id }) {
            VStack(spacing: 0) {
                HStack {
                    Text(note.modified.formatted(date: .long, time: .shortened))
                        .font(.orbit(12))
                        .foregroundStyle(Theme.secondary)
                    Spacer()
                    Button { store.togglePin(id) } label: {
                        Image(systemName: note.isPinned ? "pin.slash" : "pin")
                    }
                    .help(note.isPinned ? "Unpin" : "Pin")
                    Button { delete(id) } label: { Image(systemName: "trash") }
                        .help("Delete note")
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 22)
                .frame(height: 52)

                TextEditor(text: Binding(
                    get: { store.notes.first(where: { $0.id == id })?.text ?? "" },
                    set: { store.update(id, text: $0) }
                ))
                .font(.system(size: 15))
                .scrollContentBackground(.hidden)
                .padding(.horizontal, 18)
                .padding(.bottom, 18)
            }
        } else {
            AppMessage(symbol: "note.text", title: "No note selected",
                       detail: "Choose a note on the left, or make a new one.",
                       buttonTitle: "New Note", action: { selection = store.create().id })
        }
    }

    private func delete(_ id: Note.ID) {
        let list = store.sorted
        let index = list.firstIndex(where: { $0.id == id }) ?? 0
        store.delete(id)
        let remaining = store.sorted
        selection = remaining.isEmpty ? nil : remaining[min(index, remaining.count - 1)].id
    }
}

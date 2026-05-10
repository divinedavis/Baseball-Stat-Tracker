import SwiftUI
import PhotosUI
import AVFoundation
import UIKit

/// Chat-style UI for the AI tab. Bottom composer matches the user-supplied
/// reference: a rounded text field with a paperclip for photo/video attach
/// and a send button on the right.
struct AIChatView: View {
    @EnvironmentObject private var auth: AuthStore
    @EnvironmentObject private var billing: BillingStore

    @State private var messages: [ChatItem] = []
    @State private var draft: String = ""
    @State private var attachment: PendingAttachment?
    @State private var sending = false
    @State private var error: String?
    @State private var showingPicker = false
    @State private var pickerItem: PhotosPickerItem?

    @FocusState private var inputFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if messages.isEmpty {
                    emptyState
                } else {
                    transcript
                }
                composer
            }
            .contentShape(Rectangle())
            .onTapGesture { inputFocused = false }
            .navigationTitle("AI Coach")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Text(billing.tier.displayName)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task { await loadAttachment(from: item) }
        }
    }

    // MARK: - Sections

    private var emptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "sparkles")
                .font(.system(size: 38))
                .foregroundStyle(.tint)
            Text("Ask Barrel anything")
                .font(.title3.bold())
            Text("Upload a swing, ask about timing, pitch recognition, drills — whatever you're working on.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
        }
    }

    private var transcript: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(messages) { item in
                        ChatBubble(item: item).id(item.id)
                    }
                    if sending {
                        HStack {
                            ProgressView().controlSize(.small)
                            Text("Barrel is thinking…")
                                .font(.footnote)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.leading, 16)
                        .padding(.vertical, 4)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .scrollDismissesKeyboard(.interactively)
            .onChange(of: messages.count) { _, _ in
                if let last = messages.last {
                    withAnimation(.easeOut) { proxy.scrollTo(last.id, anchor: .bottom) }
                }
            }
        }
    }

    private var composer: some View {
        VStack(spacing: 6) {
            if let err = error {
                Text(err).font(.footnote).foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
            }
            if let attachment {
                AttachmentPreview(attachment: attachment) {
                    self.attachment = nil
                }
                .padding(.horizontal, 12)
            }
            HStack(spacing: 8) {
                PhotosPicker(
                    selection: $pickerItem,
                    matching: .any(of: [.images, .videos]),
                    photoLibrary: .shared()
                ) {
                    Image(systemName: "paperclip")
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .frame(width: 36, height: 36)
                }

                TextField("Message", text: $draft, axis: .vertical)
                    .textFieldStyle(.plain)
                    .focused($inputFocused)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color(.secondarySystemBackground))
                    )
                    .lineLimit(1...5)

                Button(action: send) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(canSend ? Color.accentColor : Color.secondary.opacity(0.5))
                }
                .disabled(!canSend)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .background(.ultraThinMaterial)
    }

    // MARK: - Actions

    private var canSend: Bool {
        !sending && (attachment != nil || !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    private func loadAttachment(from item: PhotosPickerItem) async {
        do {
            if item.supportedContentTypes.contains(where: { $0.conforms(to: .movie) }) {
                if let data = try await item.loadTransferable(type: Data.self) {
                    attachment = PendingAttachment(kind: .video, data: data, fileExtension: "mp4", contentType: "video/mp4")
                }
            } else if let data = try await item.loadTransferable(type: Data.self) {
                attachment = PendingAttachment(kind: .photo, data: data, fileExtension: "jpg", contentType: "image/jpeg")
            }
        } catch {
            self.error = "Couldn't load attachment."
        }
        pickerItem = nil
    }

    private func send() {
        let trimmed = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard canSend else { return }
        sending = true
        error = nil
        let outgoing: ChatItem
        if let attachment {
            let chatKind: ChatItem.Kind = (attachment.kind == .video) ? .video : .photo
            outgoing = ChatItem(role: .user, text: trimmed.isEmpty ? "Analyze this swing." : trimmed, kind: chatKind)
        } else {
            outgoing = ChatItem(role: .user, text: trimmed, kind: nil)
        }
        messages.append(outgoing)
        draft = ""
        let attachmentSnapshot = attachment
        attachment = nil

        if attachmentSnapshot != nil {
            EventLogger.shared.log("swing_analyze_started", properties: [
                "media_kind": .string(attachmentSnapshot?.kind == .video ? "video" : "photo"),
                "has_note": .bool(!trimmed.isEmpty),
            ])
        } else {
            EventLogger.shared.log("chat_sent", properties: [
                "char_count": .integer(trimmed.count),
            ])
        }

        Task {
            do {
                if let attachmentSnapshot {
                    let path = try await AIClient.shared.uploadSwingMedia(
                        data: attachmentSnapshot.data,
                        fileExtension: attachmentSnapshot.fileExtension,
                        contentType: attachmentSnapshot.contentType
                    )
                    let result = try await AIClient.shared.analyzeSwing(
                        storagePath: path,
                        mediaKind: attachmentSnapshot.kind == .video ? "video" : "photo",
                        note: trimmed.isEmpty ? nil : trimmed
                    )
                    messages.append(ChatItem(role: .assistant, text: result.feedback, kind: nil))
                    EventLogger.shared.log("swing_analyze_completed", properties: [
                        "tier": .string(result.tier),
                    ])
                } else {
                    let result = try await AIClient.shared.chat(message: trimmed)
                    messages.append(ChatItem(role: .assistant, text: result.reply, kind: nil))
                    EventLogger.shared.log("chat_completed", properties: [
                        "tier": .string(result.tier),
                    ])
                }
            } catch {
                self.error = error.localizedDescription
                EventLogger.shared.log("ai_request_failed", properties: [
                    "kind": .string(attachmentSnapshot != nil ? "swing" : "chat"),
                    "message": .string(error.localizedDescription),
                ])
            }
            sending = false
        }
    }
}

private struct ChatItem: Identifiable, Equatable {
    enum Role { case user, assistant }
    enum Kind { case photo, video }
    let id = UUID()
    let role: Role
    let text: String
    let kind: Kind?
}

private struct PendingAttachment: Equatable {
    enum Kind { case photo, video }
    let kind: Kind
    let data: Data
    let fileExtension: String
    let contentType: String
}

private struct ChatBubble: View {
    let item: ChatItem

    var body: some View {
        HStack {
            if item.role == .user { Spacer(minLength: 32) }
            VStack(alignment: .leading, spacing: 4) {
                if let kind = item.kind {
                    Label(kind == .video ? "Video swing" : "Photo swing",
                          systemImage: kind == .video ? "video.fill" : "photo.fill")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(item.role == .user ? .white.opacity(0.85) : .secondary)
                }
                Text(item.text)
                    .font(.body)
                    .foregroundStyle(item.role == .user ? .white : .primary)
                    .textSelection(.enabled)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(item.role == .user ? Color.accentColor : Color(.secondarySystemBackground))
            )
            if item.role == .assistant { Spacer(minLength: 32) }
        }
    }
}

private struct AttachmentPreview: View {
    let attachment: PendingAttachment
    let onRemove: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: attachment.kind == .video ? "video.fill" : "photo.fill")
                .foregroundStyle(.tint)
            Text(attachment.kind == .video ? "Video attached" : "Photo attached")
                .font(.footnote)
            Spacer()
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 12).fill(Color(.secondarySystemBackground))
        )
    }
}

#Preview {
    AIChatView()
        .environmentObject(AuthStore())
        .environmentObject(BillingStore())
}

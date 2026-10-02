import AVFoundation
import MarkdownKit
import Models
import PhotosUI
import SwiftUI
import UIKit

/// The composer's `+` (the desktop's `ComposerToolsButton`): pictures from Photos or the camera, the reasoning effort,
/// Deep Research, and the tools the computer's MCP servers offer. It presents its own pickers, sheet and alert; picked
/// pictures go to `onPictures` as data (nil for one Photos could not hand over).
struct ComposerToolsButton: View {
    /// nil in a preview: the menu offers pictures only.
    let tools: ComposerTools?
    let attachments: ComposerAttachments
    let onPictures: ([Data?]) -> Void

    @State private var showsPhotos = false
    @State private var photoSelection: [PhotosPickerItem] = []
    @State private var showsCamera = false
    @State private var showsMcpTools = false
    @State private var explainsCamera = false

    var body: some View {
        Menu {
            Section {
                Button {
                    showsPhotos = true
                } label: {
                    Label("ios:chat.composer.photoLibrary", systemImage: "photo.on.rectangle.angled")
                }
                .disabled(attachments.isFull)
                // No camera on the Simulator: the entry is not offered at all.
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button {
                        Task { await openCamera() }
                    } label: {
                        Label("ios:chat.composer.takePhoto", systemImage: "camera")
                    }
                    .disabled(attachments.isFull)
                }
            }
            if let tools {
                Section {
                    if !tools.reasoningLevels.isEmpty {
                        reasoningMenu(tools)
                    }
                    Toggle(isOn: Binding(get: { tools.deepResearch }, set: { tools.setDeepResearch($0) })) {
                        Label("ios:chat.composer.deepResearch", systemImage: "binoculars")
                    }
                }
                if tools.mcpToolCount > 0 {
                    Section {
                        Button {
                            showsMcpTools = true
                        } label: {
                            Label {
                                Text("ios:chat.composer.mcpTools")
                                Text(verbatim: "\(tools.mcpToolCount)")
                            } icon: {
                                Image(systemName: "hammer")
                            }
                        }
                    }
                }
            }
        } label: {
            Label("common:action.add", systemImage: "plus")
                .labelStyle(.iconOnly)
                // Tinted while a choice is on, as the desktop's blue `+` — here the chat's tone, like the rest of it.
                .foregroundStyle(tools?.isActive == true ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
        }
        // In the order written, as on the desktop: pictures, then how the answer is made, then the tools.
        .menuOrder(.fixed)
        .menuStyle(.button)
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .accessibilityIdentifier("composerTools")
        .photosPicker(
            isPresented: $showsPhotos, selection: $photoSelection, maxSelectionCount: max(1, attachments.room),
            selectionBehavior: .ordered, matching: .images)
        .onChange(of: photoSelection) { _, items in
            guard !items.isEmpty else { return }
            photoSelection = []
            Task {
                var loaded: [Data?] = []
                for item in items { loaded.append(try? await item.loadTransferable(type: Data.self)) }
                onPictures(loaded)
            }
        }
        .fullScreenCover(isPresented: $showsCamera) {
            CameraPicker { data in
                showsCamera = false
                if let data { onPictures([data]) }
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $showsMcpTools) {
            McpToolsSheet(groups: tools?.mcpGroups ?? [])
        }
        .alert("ios:settings.pairing.cameraDeniedTitle", isPresented: $explainsCamera) {
            Button("ios:settings.pairing.openSystemSettings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            Button("common:action.cancel", role: .cancel) {}
        } message: {
            Text("ios:chat.composer.cameraDeniedMessage")
        }
        // One tick per choice the user changes, from the menu or a pill's ✕ — not when a refresh drops the level to off.
        .sensoryFeedback(.selection, trigger: tools?.userChangeCount)
    }

    /// A submenu whose row shows the level now chosen; inside, the model's levels with a check on the chosen one.
    private func reasoningMenu(_ tools: ComposerTools) -> some View {
        Menu {
            Picker(
                "ios:chat.composer.reasoning",
                selection: Binding(get: { tools.reasoningEffort }, set: { tools.setEffort($0) })
            ) {
                ForEach(tools.reasoningLevels, id: \.self) { level in
                    Text(verbatim: ComposerText.level(level)).tag(level)
                }
            }
            .pickerStyle(.inline)
            .labelsHidden()
        } label: {
            Label {
                Text("ios:chat.composer.reasoning")
                Text(verbatim: ComposerText.level(tools.reasoningEffort))
            } icon: {
                Image(systemName: "brain")
            }
        }
    }

    private func openCamera() async {
        switch CameraAccess.decision(for: AVCaptureDevice.authorizationStatus(for: .video)) {
        case .open:
            showsCamera = true
        case .ask:
            if await AVCaptureDevice.requestAccess(for: .video) { showsCamera = true }
        case .explain:
            explainsCamera = true
        }
    }
}

/// The pictures waiting in the composer (the desktop's `FilePreview`): rounded squares in pick order, each with a ✕ at
/// its corner. Scrolls sideways when ten do not fit.
struct ComposerPictureStrip: View {
    let pictures: [ComposerPicture]
    let onRemove: (ComposerPicture.ID) -> Void

    @State private var thumbnails: [ComposerPicture.ID: UIImage] = [:]
    @ScaledMetric(relativeTo: .body) private var scaledSide: CGFloat = 56

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 12) {
                ForEach(Array(pictures.enumerated()), id: \.element.id) { index, picture in
                    tile(picture, position: index + 1)
                        .transition(.scale(scale: 0.8).combined(with: .opacity))
                }
            }
            // Room for the ✕ that reaches past each square's corner.
            .padding(.top, 8)
            .padding(.trailing, 8)
        }
        .scrollIndicators(.hidden)
        .scrollClipDisabled()
        .task(id: pictures.map(\.id)) { await decode() }
    }

    private func tile(_ picture: ComposerPicture, position: Int) -> some View {
        // The desktop's 56 pt square, growing with the text size up to a point.
        let side = min(scaledSide, 88)
        return ZStack {
            if let image = thumbnails[picture.id] {
                Image(uiImage: image).resizable().scaledToFill()
            } else {
                Rectangle().fill(.fill.tertiary)
            }
        }
        .frame(width: side, height: side)
        .clipShape(.rect(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color(.separator), lineWidth: 0.5))
        .accessibilityHidden(true)
        .overlay(alignment: .topTrailing) {
            Button {
                onRemove(picture.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Color(.systemBackground))
                    .frame(width: 20, height: 20)
                    .background(Color(.label), in: .circle)
                    .overlay(Circle().strokeBorder(Color(.systemBackground), lineWidth: 2))
                    // A 44 pt target around the 20 pt mark.
                    .frame(width: 44, height: 44)
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .offset(x: 18, y: -18)
            .accessibilityLabel(Text(verbatim: ComposerText.removePicture(position, of: pictures.count)))
        }
    }

    /// Thumbnails three times the square: sharp on any phone. One for a picture gone is dropped.
    private func decode() async {
        for picture in pictures where thumbnails[picture.id] == nil {
            if let image = await ComputerUseFrameStore.decodeScreenshot(picture.dataURL, maxPixelWidth: 264) {
                thumbnails[picture.id] = image
            }
        }
        let shown = Set(pictures.map(\.id))
        thumbnails = thumbnails.filter { shown.contains($0.key) }
    }
}

/// The choices that are on, over the field (the desktop's `ActiveToolPills`): one pill each, a tap turning it off.
struct ComposerToolPills: View {
    let tools: ComposerTools

    enum Pill: Hashable {
        case reasoning(ReasoningEffort)
        case deepResearch
    }

    static func pills(for tools: ComposerTools) -> [Pill] {
        var pills: [Pill] = []
        if tools.reasoningEffort != .off { pills.append(.reasoning(tools.reasoningEffort)) }
        if tools.deepResearch { pills.append(.deepResearch) }
        return pills
    }

    static func turnOff(_ pill: Pill, in tools: ComposerTools) {
        switch pill {
        case .reasoning: tools.setEffort(.off)
        case .deepResearch: tools.setDeepResearch(false)
        }
    }

    var body: some View {
        let pills = Self.pills(for: tools)
        if !pills.isEmpty {
            // Side by side, or one under the other when a large text size leaves no room.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) { ForEach(pills, id: \.self) { pillButton($0) } }
                VStack(alignment: .leading, spacing: 6) { ForEach(pills, id: \.self) { pillButton($0) } }
            }
        }
    }

    private func pillButton(_ pill: Pill) -> some View {
        Button {
            Self.turnOff(pill, in: tools)
        } label: {
            HStack(spacing: 4) {
                switch pill {
                case .reasoning(let level):
                    Image(systemName: "brain").accessibilityHidden(true)
                    Text(verbatim: ComposerText.reasoningPill(level))
                case .deepResearch:
                    Image(systemName: "binoculars").accessibilityHidden(true)
                    Text("ios:chat.composer.deepResearch")
                }
                Image(systemName: "xmark")
                    .font(.caption2.weight(.semibold))
                    .opacity(0.6)
                    .accessibilityHidden(true)
            }
            .font(.footnote.weight(.medium))
            .foregroundStyle(.tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(.tint.opacity(0.12), in: .capsule)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityHint(Text("ios:chat.composer.turnOff"))
    }
}

/// The tools the computer's MCP servers offer (the desktop composer's MCP dialog), by server, each described in
/// Markdown. Read-only: servers are turned on and off in Settings › MCP Servers.
struct McpToolsSheet: View {
    let groups: [McpToolsResponse.Group]
    @Environment(\.dismiss) private var dismiss

    /// The server's description, or a line saying it gave none.
    static func description(of tool: McpTool) -> String {
        let text = tool.description.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty ? ComposerText.noDescription(tool.name) : text
    }

    var body: some View {
        NavigationStack {
            List {
                Text("ios:chat.composer.mcpSheet.description")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .listRowBackground(Color.clear)
                ForEach(groups, id: \.mcpServerName) { group in
                    Section {
                        ForEach(group.tools) { tool in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(verbatim: tool.name)
                                    .font(.subheadline.monospaced().weight(.medium))
                                MarkdownView(text: Self.description(of: tool), isStreaming: false)
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 2)
                        }
                    } header: {
                        Text(verbatim: group.mcpServerName)
                    }
                }
            }
            .navigationTitle(Text("ios:chat.composer.mcpSheet.title"))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("common:action.close", role: .close) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}

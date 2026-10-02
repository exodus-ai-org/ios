import AVFoundation
import MarkdownKit
import Models
import PhotosUI
import SwiftUI
import UIKit

/// The composer's `+` (the desktop's `ComposerToolsButton`): pictures from Photos or the camera, the reasoning effort,
/// Deep Research, and the tools the computer's MCP servers offer. It presents its own pickers, sheet and alert; picked
/// pictures go to `onPictures` in pick order, each as a loader the receiver calls when that one's turn comes.
struct ComposerToolsButton: View {
    /// nil in a preview: the menu offers pictures only.
    let tools: ComposerTools?
    let attachments: ComposerAttachments
    let onPictures: ([ComposerPicture.Loader]) -> Void

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
                .foregroundStyle(isActive ? AnyShapeStyle(.tint) : AnyShapeStyle(.primary))
        }
        // In the order written, as on the desktop: pictures, then how the answer is made, then the tools.
        .menuOrder(.fixed)
        .menuStyle(.button)
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        // The ink alone does not show in the Neutral tone, whose ink is the label colour: a wash of it over the glass
        // does (under it, the glass hides it).
        .overlay {
            if isActive { Circle().fill(.tint.opacity(0.12)).allowsHitTesting(false) }
        }
        .accessibilityValue(activeChoice)
        .accessibilityIdentifier("composerTools")
        .photosPicker(
            isPresented: $showsPhotos, selection: $photoSelection, maxSelectionCount: max(1, attachments.room),
            selectionBehavior: .ordered, matching: .images)
        .onChange(of: photoSelection) { _, items in
            guard !items.isEmpty else { return }
            photoSelection = []
            onPictures(items.map { item in { try? await item.loadTransferable(type: Data.self) } })
        }
        .fullScreenCover(isPresented: $showsCamera) {
            CameraPicker { data in
                showsCamera = false
                if let data { onPictures([{ data }]) }
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

    private var isActive: Bool { tools?.isActive == true }

    /// The choice that is on, as its pill names it, for VoiceOver.
    private var activeChoice: Text {
        switch tools.flatMap({ ComposerToolPills.pills(for: $0).first }) {
        case .reasoning(let level): Text(verbatim: ComposerText.reasoningPill(level))
        case .deepResearch: Text("ios:chat.composer.deepResearch")
        case nil: Text(verbatim: "")
        }
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

/// The pictures waiting in the composer (the desktop's `FilePreview`): rounded squares in pick order, each with a ✕ on
/// its corner, then a placeholder for each picked one not ready yet. Scrolls sideways when ten do not fit.
struct ComposerPictureStrip: View {
    let pictures: [ComposerPicture]
    var preparing = 0
    let onRemove: (ComposerPicture.ID) -> Void

    @State private var thumbnails: [ComposerPicture.ID: UIImage] = [:]
    @ScaledMetric(relativeTo: .body) private var scaledSide: CGFloat = 56
    @ScaledMetric(relativeTo: .caption2) private var scaledBadge: CGFloat = 20

    /// The desktop's 56 pt square, growing with the text size up to a point.
    private var side: CGFloat { min(scaledSide, 88) }
    /// The ✕'s disc; its glyph scales with it, so the two never part at a large text size.
    private var badge: CGFloat { min(scaledBadge, 28) }
    /// The ✕'s target around the disc: small enough to stay inside the strip, which clips.
    private var target: CGFloat { badge + 12 }

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 12) {
                ForEach(Array(pictures.enumerated()), id: \.element.id) { index, picture in
                    tile(picture, position: index + 1)
                        // Each square over the next, so the ✕ reaching past its corner is never under a neighbour.
                        .zIndex(Double(pictures.count - index))
                        .transition(.scale(scale: 0.8).combined(with: .opacity))
                }
                ForEach(0..<preparing, id: \.self) { _ in
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.fill.tertiary)
                        .frame(width: side, height: side)
                        .overlay { ProgressView() }
                        .transition(.opacity)
                }
            }
            // Room inside the strip for the ✕ centred on each square's corner: nothing is drawn past the composer's glass.
            .padding(.top, target / 2)
            .padding(.trailing, target / 2)
        }
        .scrollIndicators(.hidden)
        .task(id: pictures.map(\.id)) { await decode() }
    }

    private func tile(_ picture: ComposerPicture, position: Int) -> some View {
        ZStack {
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
                    .font(.system(size: badge * 0.5, weight: .bold))
                    .foregroundStyle(Color(.systemBackground))
                    .frame(width: badge, height: badge)
                    .background(Color(.label), in: .circle)
                    .overlay(Circle().strokeBorder(Color(.systemBackground), lineWidth: 2))
                    .frame(width: target, height: target)
                    .contentShape(.circle)
            }
            .buttonStyle(.plain)
            .offset(x: target / 2, y: -target / 2)
            .accessibilityLabel(Text(verbatim: ComposerText.removePicture(position, of: pictures.count)))
        }
    }

    /// How wide to decode a picture so its shorter side is three times the square (sharp on any phone, whichever way
    /// the picture is turned): never wider than the picture, nor than a panorama needs.
    static func thumbnailPixelWidth(width: Int, height: Int) -> Int {
        let shorterSide = 264
        let wanted = width > height ? width * shorterSide / max(height, 1) : shorterSide
        return min(width, wanted, 1024)
    }

    /// One thumbnail per picture; one for a picture gone is dropped.
    private func decode() async {
        for picture in pictures where thumbnails[picture.id] == nil {
            let width = Self.thumbnailPixelWidth(width: picture.pixelWidth, height: picture.pixelHeight)
            if let image = await ComputerUseFrameStore.decodeScreenshot(picture.dataURL, maxPixelWidth: width) {
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

#if DEBUG
import Foundation
import SwiftUI

/// DEBUG-only: tool cards for the owner to judge on a device, drawn by the real views from desktop-shaped results. Reached from Settings → Card prototypes (a DEBUG row) or `-CardPrototypes`;
/// `-CardPrototypesSection files|computer|research|weather|image|map|media|memory|approval|compare|artifact` shows that group alone and
/// `-CardPrototypesY <points>` scrolls to an offset.
public enum CardPrototypesLaunch {
    public static var isEnabled: Bool { ProcessInfo.processInfo.arguments.contains("-CardPrototypes") }

    static var section: ProtoGroup? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-CardPrototypesSection"), index + 1 < arguments.count else { return nil }
        return ProtoGroup(rawValue: arguments[index + 1])
    }

    /// `-CardPrototypesY <points>`: a scroll offset, for screenshots of a state deep in the page.
    static var offset: Double? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: "-CardPrototypesY"), index + 1 < arguments.count else { return nil }
        return Double(arguments[index + 1])
    }
}

enum ProtoGroup: String, CaseIterable, Identifiable {
    case files, computer, research, weather, image, map, media, memory, approval, compare, artifact

    var id: Self { self }

    var title: String {
        switch self {
        case .files: "Files · read_file / write_file / edit_file"
        case .computer: "Computer Use"
        case .research: "Deep Research"
        case .weather: "Weather"
        case .image: "Image Generation"
        case .map: "Map Itinerary"
        case .media: "Web Search · images and videos"
        case .memory: "Memory · update_memory strip / used memories"
        case .approval: "Approval · a tool asks to read a secret"
        case .compare: "Regenerate · two answers compared"
        case .artifact: "Artifact · create_artifact"
        }
    }

    var systemImage: String {
        switch self {
        case .files: "doc.text"
        case .computer: "desktopcomputer"
        case .research: "text.magnifyingglass"
        case .weather: "cloud.sun"
        case .image: "photo.on.rectangle"
        case .map: "map"
        case .media: "photo.stack"
        case .memory: "brain"
        case .approval: "key"
        case .compare: "square.on.square"
        case .artifact: "chart.bar.doc.horizontal"
        }
    }
}

public struct CardPrototypesView: View {
    /// Pushed from Settings it lives in Settings' stack; launched on its own it brings one.
    private let embedded: Bool
    @State private var position = ScrollPosition(edge: .top)

    public init(embedded: Bool = true) {
        self.embedded = embedded
    }

    public var body: some View {
        if embedded {
            content
        } else {
            NavigationStack { content }
        }
    }

    private var content: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 44) {
                    intro
                    ForEach(CardPrototypesLaunch.section.map { [$0] } ?? ProtoGroup.allCases) { group in
                        VStack(alignment: .leading, spacing: 20) {
                            Label {
                                Text(verbatim: group.title)
                            } icon: {
                                Image(systemName: group.systemImage)
                            }
                            .font(.headline)
                            .foregroundStyle(.tint)
                            Divider()
                            section(group)
                        }
                        .id(group)
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 12)
            }
            .scrollPosition($position)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        ForEach(ProtoGroup.allCases) { group in
                            Button {
                                withAnimation { proxy.scrollTo(group, anchor: .top) }
                            } label: {
                                Label {
                                    Text(verbatim: group.title)
                                } icon: {
                                    Image(systemName: group.systemImage)
                                }
                            }
                        }
                    } label: {
                        Image(systemName: "list.bullet")
                    }
                    .accessibilityLabel(Text(verbatim: "Jump to a card"))
                }
            }
            .task {
                try? await Task.sleep(for: .milliseconds(300))
                if let offset = CardPrototypesLaunch.offset { position.scrollTo(y: offset) }
            }
        }
        .navigationTitle(Text(verbatim: "Card prototypes"))
        .navigationBarTitleDisplayMode(.inline)
    }

    private var intro: some View {
        Text(verbatim: "Every card here is the real one chats draw, fed desktop-shaped results: Files, Computer Use, Deep Research, Weather, Image Generation, Map Itinerary, the search images and videos, the approval card, the memory foot and the artifact card. Each is shown inside a reply in its main states. Two states are sketches a chat never draws, and say so: the running Weather and Map Itinerary cards. Tap cards to expand them, open sheets and viewers, and try Undo.")
            .font(.footnote)
            .foregroundStyle(.secondary)
    }

    @ViewBuilder
    private func section(_ group: ProtoGroup) -> some View {
        switch group {
        case .files: ProtoFileCardsSection()
        case .computer: ProtoComputerUseSection()
        case .research: ProtoDeepResearchSection()
        case .weather: ProtoWeatherSection()
        case .image: ProtoImageGenerationSection()
        case .map: ProtoMapItinerarySection()
        case .media: ProtoSearchMediaSection()
        case .memory: ProtoMemorySection()
        case .approval: ProtoApprovalSection()
        case .compare: ProtoCompareSection()
        case .artifact: ProtoArtifactSection()
        }
    }
}
#endif

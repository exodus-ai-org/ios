import MapKit
import Models
import SwiftUI
import UIKit

/// The map_itinerary card. In the transcript: the trip on a still map, each day's route in its own colour, and the
/// first stops listed; any tap opens the full-screen map, where the days are switched, a stop is centred and its place
/// detail opens. The map is hard to use with VoiceOver, so the stop lists are the accessible path.
struct MapItineraryCard: View {
    let state: MapItineraryCardState

    var body: some View {
        switch state {
        case .itinerary(let model): MapItineraryInlineCard(model: model)
        case .failed(let title, let message): MapItineraryFailedCard(title: title, message: message)
        }
    }
}

/// Where the full-screen map opens: a day, and the stop that was tapped, if one was.
struct MapItineraryFocus: Identifiable, Equatable {
    let dayIndex: Int
    let stopId: String?

    var id: String { "\(dayIndex)-\(stopId ?? "")" }
}

// MARK: - Colours

/// A day's colour as drawn: the fill of its route, pins and number badges, and the number's colour on that fill.
struct MapDayInk {
    let fill: Color
    let glyph: Color
    let dashed: Bool

    /// The system colours in their Increase Contrast variant: vivid on both map appearances, never washed out.
    @MainActor
    static func inks(
        for model: MapItineraryCardModel, tone: ColorTone, accent: Color, accentGlyph: Color, scheme: ColorScheme
    ) -> [MapDayInk] {
        MapDayPalette.colors(dayCount: model.days.count, tone: tone).map { day in
            switch day.swatch {
            case .accent:
                return MapDayInk(fill: accent, glyph: accentGlyph, dashed: day.dashed)
            case .system(let hue):
                let base = uiColor(hue)
                let traits = UITraitCollection(userInterfaceStyle: scheme == .dark ? .dark : .light)
                    .modifyingTraits { @MainActor traits in traits.accessibilityContrast = .high }
                let resolved = base.resolvedColor(with: traits)
                let white = ColorTone.glyphIsWhite(on: rgb(resolved))
                return MapDayInk(fill: Color(uiColor: resolved), glyph: white ? .white : .black, dashed: day.dashed)
            }
        }
    }

    static func uiColor(_ hue: MapDayPalette.Hue) -> UIColor {
        switch hue {
        case .orange: .systemOrange
        case .teal: .systemTeal
        case .purple: .systemPurple
        case .green: .systemGreen
        case .pink: .systemPink
        case .brown: .systemBrown
        case .indigo: .systemIndigo
        case .blue: .systemBlue
        }
    }

    private static func rgb(_ color: UIColor) -> ColorTone.RGB {
        var (red, green, blue, alpha): (CGFloat, CGFloat, CGFloat, CGFloat) = (0, 0, 0, 0)
        color.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
        return ColorTone.RGB(red: Double(red), green: Double(green), blue: Double(blue))
    }

    static let fallback = MapDayInk(fill: .accentColor, glyph: .white, dashed: false)
}

private struct DayInksReader<Content: View>: View {
    let model: MapItineraryCardModel
    @ViewBuilder let content: ([MapDayInk]) -> Content
    @Environment(\.colorTone) private var tone
    @Environment(\.toneAccent) private var accent
    @Environment(\.accentGlyph) private var accentGlyph
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        content(MapDayInk.inks(for: model, tone: tone, accent: accent, accentGlyph: accentGlyph, scheme: scheme))
    }
}

extension [MapDayInk] {
    subscript(day index: Int) -> MapDayInk { indices.contains(index) ? self[index] : .fallback }
}

// MARK: - Map drawing

extension MapCoordinate {
    var location: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
}

extension MapRegion {
    var mapKit: MKCoordinateRegion {
        MKCoordinateRegion(
            center: center.location, span: MKCoordinateSpan(latitudeDelta: latitudeDelta, longitudeDelta: longitudeDelta))
    }
}

/// The routes and pins of an itinerary. `focusDay` nil draws every day alike (the transcript); otherwise that day is
/// drawn over the others, which fade to a thin grey line with no pins.
@MainActor @MapContentBuilder
func itineraryMapContent(
    _ model: MapItineraryCardModel, inks: [MapDayInk], focusDay: Int?, showsTitles: Bool, casing: Color
) -> some MapContent {
    ForEach(model.days) { day in
        if day.route.count > 1 {
            let isFocused = focusDay == nil || focusDay == day.index
            let ink = inks[day: day.index]
            let path = day.route.map(\.location)
            if isFocused {
                // A casing in the page's background colour keeps the route readable on any tile, or on none.
                MapPolyline(coordinates: path).stroke(casing, style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
                MapPolyline(coordinates: path)
                    .stroke(
                        ink.fill,
                        style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round, dash: ink.dashed ? [8, 6] : []))
            } else {
                MapPolyline(coordinates: path).stroke(Color.gray.opacity(0.45), lineWidth: 2.5)
            }
        }
    }
    ForEach(model.days.filter { focusDay == nil || focusDay == $0.index }) { day in
        ForEach(day.mappedStops) { stop in
            if let coordinate = stop.coordinate {
                if showsTitles {
                    Marker(stop.place.name, monogram: Text(verbatim: "\(stop.number)"), coordinate: coordinate.location)
                        .tint(inks[day: day.index].fill)
                        .tag(stop.id)
                } else {
                    // A small badge on the point itself: balloons would bury a dense day's route in the small map.
                    Annotation(stop.place.name, coordinate: coordinate.location, anchor: .center) {
                        StopBadge(number: stop.number, ink: inks[day: day.index])
                            .overlay(Circle().strokeBorder(casing, lineWidth: 1.5))
                            .dynamicTypeSize(.large)
                    }
                    .tag(stop.id)
                }
            }
        }
    }
    .annotationTitles(showsTitles ? .automatic : .hidden)
}

// MARK: - Inline card

private struct MapItineraryInlineCard: View {
    let model: MapItineraryCardModel
    @State private var focus: MapItineraryFocus?
    @ScaledMetric(relativeTo: .body) private var mapHeight: CGFloat = 190

    var body: some View {
        DayInksReader(model: model) { inks in
            VStack(alignment: .leading, spacing: 0) {
                MapItineraryHeader(model: model)
                if let notice = model.notice {
                    MapItineraryNotice(notice: notice)
                }
                if model.hasMap {
                    Button {
                        focus = MapItineraryFocus(dayIndex: 0, stopId: nil)
                    } label: {
                        InlineMap(model: model, inks: inks)
                            .frame(height: min(max(mapHeight, 170), 260))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("ios:chat.card.map.mapLabel"))
                    .accessibilityHint(Text("ios:chat.card.map.openHint"))
                }
                if model.days.count > 1 {
                    DayLegend(model: model, inks: inks)
                }
                stops(inks)
            }
            .modifier(CardSurface())
        }
        .fullScreenCover(item: $focus) { focus in
            MapItineraryFullView(model: model, start: focus)
        }
    }

    @ViewBuilder
    private func stops(_ inks: [MapDayInk]) -> some View {
        if model.stopCount == 0 {
            Text("ios:chat.card.map.noStops")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(12)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(model.inlineStops) { stop in
                    Button {
                        focus = MapItineraryFocus(dayIndex: stop.dayIndex, stopId: stop.id)
                    } label: {
                        MapStopRow(
                            stop: stop, ink: inks[day: stop.dayIndex],
                            dayLabel: model.days.count > 1 ? MapItineraryText.dayLabel(model.days[stop.dayIndex]) : nil)
                    }
                    .buttonStyle(.plain)
                    if stop.id != model.inlineStops.last?.id || model.moreCount > 0 {
                        Divider().padding(.leading, 44)
                    }
                }
                if model.moreCount > 0 {
                    Button {
                        focus = MapItineraryFocus(dayIndex: 0, stopId: nil)
                    } label: {
                        HStack(spacing: 6) {
                            Text(verbatim: MapItineraryText.more(model.moreCount))
                            Image(systemName: "arrow.up.left.and.arrow.down.right")
                                .imageScale(.small)
                                .accessibilityHidden(true)
                        }
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.tint)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityHint(Text("ios:chat.card.map.openHint"))
                }
            }
        }
    }
}

private struct InlineMap: View {
    let model: MapItineraryCardModel
    let inks: [MapDayInk]

    var body: some View {
        Map(initialPosition: model.region.map { .region($0.mapKit) } ?? .automatic, interactionModes: []) {
            itineraryMapContent(model, inks: inks, focusDay: nil, showsTitles: false, casing: Color(.systemBackground))
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
        // Still in the transcript: a drag scrolls the chat; the full-screen map is where it moves.
        .allowsHitTesting(false)
        .background(Color(.secondarySystemFill))
        .accessibilityHidden(true)
    }
}

private struct MapItineraryHeader: View {
    let model: MapItineraryCardModel

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: "map")
                .foregroundStyle(.tint)
                .frame(minWidth: 20)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 1) {
                Text(verbatim: model.title ?? ToolPresentation.displayName("map_itinerary"))
                    .font(.subheadline.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)
                Text(verbatim: ToolPresentation.itineraryText(ItineraryScale(days: model.days.count, stops: model.stopCount)))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Color(.tertiarySystemFill))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }
}

/// Enrichment failed for a reason the user can fix (an expired Google key): the stops are the model's own, without
/// ratings, photos or hours. The message is the computer's text, shown as it is.
struct MapItineraryNotice: View {
    let notice: ToolNotice

    private var isWarning: Bool { notice.level != "info" }

    var body: some View {
        Label {
            Text(verbatim: notice.message)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: isWarning ? "exclamationmark.triangle.fill" : "info.circle")  // l10n:ignore: SF Symbol names
                .foregroundStyle(isWarning ? Color.orange : Color.secondary)
        }
        .font(.caption)
        .foregroundStyle(isWarning ? Color.primary : Color.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(isWarning ? Color.orange.opacity(0.12) : Color(.secondarySystemFill))
    }
}

/// Which colour is which day, under the map of a trip of several days.
private struct DayLegend: View {
    let model: MapItineraryCardModel
    let inks: [MapDayInk]

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 14) {
                ForEach(model.days) { day in
                    HStack(spacing: 6) {
                        DaySwatch(ink: inks[day: day.index])
                        Text(verbatim: MapItineraryText.dayLabel(day))
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .scrollIndicators(.hidden)
        // The stop rows name their day; the legend only explains the colours to the eye.
        .accessibilityHidden(true)
    }
}

private struct DaySwatch: View {
    let ink: MapDayInk

    var body: some View {
        Capsule()
            .stroke(ink.fill, style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: ink.dashed ? [4, 3] : []))
            .frame(width: 16, height: 3)
            .accessibilityHidden(true)
    }
}

/// A stop in a list: its number in its day's colour, its name and time, and what is known of it.
struct MapStopRow: View {
    let stop: MapItineraryCardModel.Stop
    let ink: MapDayInk
    /// Named when the list mixes days (the transcript's first stops).
    var dayLabel: String?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            StopBadge(number: stop.number, ink: ink)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                let layout =
                    dynamicTypeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
                    : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 6))
                layout {
                    Text(verbatim: stop.place.name)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if let time = stop.place.timeLabel {
                        Text(verbatim: time)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                }
                let meta = MapItineraryText.meta(stop.place)
                if !meta.isEmpty {
                    Text(verbatim: meta)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if stop.coordinate == nil {
                    Label("ios:chat.card.map.notOnMap", systemImage: "mappin.slash")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .contentShape(.rect)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: MapItineraryText.accessibilityLabel(stop, dayLabel: dayLabel)))
        .accessibilityAddTraits(.isButton)
    }
}

private struct StopBadge: View {
    let number: Int
    let ink: MapDayInk
    @ScaledMetric(relativeTo: .caption2) private var size: CGFloat = 22

    var body: some View {
        Text(verbatim: "\(number)")
            .font(.caption2.weight(.bold).monospacedDigit())
            .foregroundStyle(ink.glyph)
            .minimumScaleFactor(0.6)
            .frame(width: min(size, 34), height: min(size, 34))
            .background(Circle().fill(ink.fill))
    }
}

private struct MapItineraryFailedCard: View {
    let title: String?
    let message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "map")
                    .foregroundStyle(.tint)
                    .frame(minWidth: 20)
                    .accessibilityHidden(true)
                Text(verbatim: title ?? ToolPresentation.displayName("map_itinerary"))
                    .font(.subheadline.weight(.medium))
                    .frame(maxWidth: .infinity, alignment: .leading)
                FileCardFailedIcon()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(Color(.tertiarySystemFill))
            .accessibilityElement(children: .combine)
            FileCardError(message: message ?? ToolPresentation.failedText("map_itinerary"))
        }
        .modifier(CardSurface())
    }
}

// MARK: - Full-screen map

/// A cover rather than a pushed page: the chat's drawer answers an edge swipe and the transcript is a lazy stack, and
/// a map needs every drag for itself. The place detail is a sheet over the lower half, leaving the map in view.
struct MapItineraryFullView: View {
    let model: MapItineraryCardModel
    let start: MapItineraryFocus

    @State private var dayIndex: Int
    @State private var selection: String?
    @State private var position: MapCameraPosition
    @State private var visibleRegion: MapRegion?
    @State private var copyCount = 0
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    init(model: MapItineraryCardModel, start: MapItineraryFocus) {
        self.model = model
        self.start = start
        let day = model.days.indices.contains(start.dayIndex) ? start.dayIndex : 0
        _dayIndex = State(initialValue: day)
        _position = State(initialValue: Self.position(for: model.days.indices.contains(day) ? model.days[day].region : nil))
    }

    private var day: MapItineraryCardModel.Day? { model.days.indices.contains(dayIndex) ? model.days[dayIndex] : nil }
    private var motion: Animation? { reduceMotion ? nil : .smooth(duration: 0.45) }

    var body: some View {
        DayInksReader(model: model) { inks in
            NavigationStack {
                VStack(spacing: 0) {
                    // Above the map, so a place's detail at the medium detent never covers them: switching day
                    // needs no dragging the sheet down first.
                    if model.days.count > 1 { dayChips(inks) }
                    if model.hasMap {
                        map(inks)
                            .containerRelativeFrame(.vertical) { height, _ in
                                height * (dynamicTypeSize.isAccessibilitySize ? 0.34 : 0.46)
                            }
                    }
                    stopList(inks)
                }
                .navigationTitle(Text(verbatim: model.title ?? ToolPresentation.displayName("map_itinerary")))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar { toolbar }
                .sheet(isPresented: detailIsOpen) {
                    if let stop = model.stop(id: selection) {
                        PlaceDetailSheet(
                            stop: stop, dayLabel: MapItineraryText.dayLabel(model.days[stop.dayIndex]),
                            total: model.days[stop.dayIndex].stops.count, ink: inks[day: stop.dayIndex]
                        ) { step in
                            selection = model.neighbour(of: stop.id, step: step)?.id
                        }
                        .presentationDetents([.medium, .large])
                        .presentationBackgroundInteraction(.enabled(upThrough: .medium))
                        .presentationContentInteraction(.scrolls)
                    }
                }
            }
        }
        .onChange(of: dayIndex) {
            selection = nil
            withAnimation(motion) { position = Self.position(for: day?.region) }
        }
        .onChange(of: selection) { _, id in
            guard let stop = model.stop(id: id), let coordinate = stop.coordinate else { return }
            withAnimation(motion) {
                position = .region(MapRegionMath.centered(on: coordinate, keeping: visibleRegion ?? day?.region).mapKit)
            }
        }
        .task {
            // The detail waits for the cover to finish arriving: two presentations at once is refused.
            guard let stopId = start.stopId else { return }
            try? await Task.sleep(for: .milliseconds(reduceMotion ? 50 : 450))
            selection = stopId
        }
        .sensoryFeedback(.success, trigger: copyCount)
    }

    private var detailIsOpen: Binding<Bool> {
        Binding(get: { selection != nil }, set: { if !$0 { selection = nil } })
    }

    static func position(for region: MapRegion?) -> MapCameraPosition {
        region.map { .region($0.mapKit) } ?? .automatic
    }

    private func map(_ inks: [MapDayInk]) -> some View {
        Map(position: $position, selection: $selection) {
            itineraryMapContent(model, inks: inks, focusDay: dayIndex, showsTitles: true, casing: Color(.systemBackground))
        }
        .mapStyle(.standard(elevation: .flat, pointsOfInterest: .excludingAll))
        .onMapCameraChange(frequency: .onEnd) { context in
            let region = context.region
            visibleRegion = MapRegion(
                center: MapCoordinate(latitude: region.center.latitude, longitude: region.center.longitude),
                latitudeDelta: region.span.latitudeDelta, longitudeDelta: region.span.longitudeDelta)
        }
        .background(Color(.secondarySystemFill))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text("ios:chat.card.map.mapLabel"))
    }

    private func dayChips(_ inks: [MapDayInk]) -> some View {
        ScrollView(.horizontal) {
            HStack(spacing: 8) {
                ForEach(model.days) { day in
                    let isSelected = day.index == dayIndex
                    let ink = inks[day: day.index]
                    Button {
                        dayIndex = day.index
                    } label: {
                        HStack(spacing: 6) {
                            DaySwatch(ink: ink)
                            Text(verbatim: MapItineraryText.dayLabel(day))
                                .font(.subheadline.weight(isSelected ? .semibold : .regular))
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .frame(minHeight: 44)
                        .background(
                            Capsule().fill(isSelected ? ink.fill.opacity(0.16) : Color(.tertiarySystemFill))
                                .frame(minHeight: 34)
                        )
                        .overlay(Capsule().strokeBorder(isSelected ? ink.fill : .clear, lineWidth: 1.5).frame(minHeight: 34))
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityAddTraits(isSelected ? .isSelected : [])
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        }
        .scrollIndicators(.hidden)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("chat:mapItineraryCard.tabsAriaLabel"))
    }

    @ViewBuilder
    private func stopList(_ inks: [MapDayInk]) -> some View {
        if let day {
            List {
                // In the list, not over the map: at large text sizes the notice alone would fill the screen.
                if let notice = model.notice {
                    MapItineraryNotice(notice: notice)
                        .clipShape(.rect(cornerRadius: 10))
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                        .listRowSeparator(.hidden)
                }
                if day.title != nil || day.summary != nil {
                    VStack(alignment: .leading, spacing: 2) {
                        if let title = day.title {
                            Text(verbatim: title).font(.headline)
                        }
                        if let summary = day.summary {
                            Text(verbatim: summary).font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityAddTraits(.isHeader)
                    .listRowSeparator(.hidden)
                }
                if day.stops.isEmpty {
                    Text("ios:chat.card.map.noStops").foregroundStyle(.secondary)
                }
                ForEach(day.stops) { stop in
                    Button {
                        selection = stop.id
                    } label: {
                        MapStopRow(stop: stop, ink: inks[day: day.index])
                    }
                    .buttonStyle(.plain)
                    .listRowInsets(EdgeInsets(top: 0, leading: 4, bottom: 0, trailing: 4))
                    .listRowBackground(selection == stop.id ? inks[day: day.index].fill.opacity(0.12) : Color.clear)
                }
            }
            .listStyle(.plain)
        } else {
            Spacer()
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button {
                dismiss()
            } label: {
                Label("common:action.close", systemImage: "xmark")
            }
        }
        if let day {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    UIPasteboard.general.string = MapItineraryExport.markdown(day)
                    copyCount += 1
                } label: {
                    Label("chat:mapItineraryCard.copyMarkdownTitle", systemImage: "doc.on.doc")
                }
                if let url = MapItineraryExport.routeURL(day) {
                    Button {
                        openURL(url)
                    } label: {
                        Label("chat:mapItineraryCard.openRouteTitle", systemImage: "arrow.up.forward.square")
                    }
                }
            }
        }
    }
}

// MARK: - Place detail

/// The desktop's place detail: a photo, the day and time, name, rating and type; Overview (notes, address, phone,
/// website), Reviews and Hours when there are any; and paging through the day's stops. Places photos come through the
/// computer's proxy, which adds the Google key; the tinted placeholder stays when one cannot be loaded.
struct PlaceDetailSheet: View {
    let stop: MapItineraryCardModel.Stop
    let dayLabel: String
    let total: Int
    let ink: MapDayInk
    let onStep: (Int) -> Void

    enum Tab: Hashable { case overview, reviews, hours }

    @State private var tab = Tab.overview
    @Environment(\.dismiss) private var dismiss

    private var place: MapItineraryDetails.Place { stop.place }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    hero
                    header
                    if !place.reviews.isEmpty || !place.openingHours.isEmpty {
                        Picker(selection: $tab) {
                            Text("chat:placeDetail.tabOverview").tag(Tab.overview)
                            if !place.reviews.isEmpty { Text("chat:placeDetail.tabReviews").tag(Tab.reviews) }
                            if !place.openingHours.isEmpty { Text("chat:placeDetail.tabHours").tag(Tab.hours) }
                        } label: {
                            Text("chat:placeDetail.tabsAriaLabel")
                        }
                        .pickerStyle(.segmented)
                    }
                    switch tab {
                    case .overview: overview
                    case .reviews: reviews
                    case .hours: hours
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 16)
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button {
                        dismiss()
                    } label: {
                        Label("common:action.close", systemImage: "xmark")
                    }
                }
                // In the top bar, not a bottom one: at the medium detent a bottom bar floats over the first rows.
                ToolbarItem(placement: .principal) {
                    Text(verbatim: MapItineraryText.pagination(stop.number, total))
                        .font(.footnote.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        onStep(-1)
                    } label: {
                        Label("chat:placeDetail.previousAriaLabel", systemImage: "chevron.left")
                    }
                    .disabled(total <= 1)
                    Button {
                        onStep(1)
                    } label: {
                        Label("chat:placeDetail.nextAriaLabel", systemImage: "chevron.right")
                    }
                    .disabled(total <= 1)
                }
            }
        }
        .onChange(of: stop.id) { tab = .overview }
    }

    private var hero: some View {
        PlacePhotoHero(names: place.photoNames, ink: ink)
            .id(stop.id)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) { headerLine(separated: true) }
                VStack(alignment: .leading, spacing: 2) { headerLine(separated: false) }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            Text(verbatim: place.name)
                .font(.title3.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            if place.rating != nil || place.type != nil {
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 5) { ratingLine(separated: true) }
                    VStack(alignment: .leading, spacing: 2) { ratingLine(separated: false) }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: MapItineraryText.ratingAndType(place)))
            }
        }
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private func ratingLine(separated: Bool) -> some View {
        if let rating = place.rating {
            HStack(spacing: 5) {
                Text(verbatim: MapItineraryText.ratingNumber(rating)).foregroundStyle(.primary).fontWeight(.medium)
                Image(systemName: "star.fill").foregroundStyle(.orange).imageScale(.small)
                if let count = place.reviewCount {
                    Text(verbatim: "(\(MapItineraryText.compactCount(count)))")
                }
            }
        }
        if separated, place.rating != nil, place.type != nil { Text(verbatim: "·") }
        if let type = place.type { Text(verbatim: type) }
    }

    @ViewBuilder
    private func headerLine(separated: Bool) -> some View {
        Text(verbatim: dayLabel)
        if let time = place.timeLabel {
            if separated { Text(verbatim: "·").accessibilityHidden(true) }
            Text(verbatim: time)
        }
        if let open = place.openNow {
            if separated { Text(verbatim: "·").accessibilityHidden(true) }
            Group {
                if open {
                    Text("chat:placeDetail.open").foregroundStyle(.green)
                } else {
                    Text("chat:placeDetail.closed")
                }
            }
            .fontWeight(.medium)
        }
    }

    @ViewBuilder
    private var overview: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let note = place.note {
                VStack(alignment: .leading, spacing: 4) {
                    Text("chat:placeDetail.notes")
                        .font(.caption2.weight(.semibold))
                        .textCase(.uppercase)
                        .foregroundStyle(.secondary)
                    Text(verbatim: note)
                        .font(.subheadline)
                        .textSelection(.enabled)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color(.secondarySystemFill), in: .rect(cornerRadius: 10))
                .accessibilityElement(children: .combine)
            }
            if let address = place.address {
                contactRow(
                    systemImage: "mappin", text: address,
                    url: MapItineraryExport.webURL(place.googleMapsUri)
                        ?? stop.coordinate.flatMap { URL(string: MapItineraryExport.searchLink($0)) })
            }
            if let phone = place.phone {
                contactRow(systemImage: "phone", text: phone, url: MapItineraryExport.phoneURL(phone))
            }
            if let website = place.websiteUri, let url = MapItineraryExport.webURL(website) {
                contactRow(systemImage: "globe", text: MapItineraryText.bareHost(website), url: url)
            }
        }
    }

    @ViewBuilder
    private func contactRow(systemImage: String, text: String, url: URL?) -> some View {
        let label = Label {
            Text(verbatim: text).multilineTextAlignment(.leading)
        } icon: {
            Image(systemName: systemImage)
        }
        .font(.subheadline)
        .frame(maxWidth: .infinity, minHeight: 32, alignment: .leading)
        if let url {
            Link(destination: url) { label }
        } else {
            label.foregroundStyle(.secondary)
        }
    }

    private var reviews: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(Array(place.reviews.enumerated()), id: \.offset) { _, review in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(verbatim: MapItineraryText.initial(review.author))
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 28, height: 28)
                            .background(Circle().fill(Color(.tertiarySystemFill)))
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 1) {
                            Group {
                                if let author = review.author {
                                    Text(verbatim: author)
                                } else {
                                    Text("chat:placeDetail.anonymousReviewer")
                                }
                            }
                            .font(.subheadline.weight(.medium))
                            HStack(spacing: 4) {
                                if let rating = review.rating {
                                    HStack(spacing: 1) {
                                        ForEach(0..<5, id: \.self) { index in
                                            Image(systemName: "star.fill")
                                                .foregroundStyle(Double(index) < rating.rounded() ? Color.orange : Color(.quaternaryLabel))
                                        }
                                    }
                                    .imageScale(.small)
                                    .font(.caption2)
                                    .accessibilityElement(children: .ignore)
                                    .accessibilityLabel(Text(verbatim: MapItineraryText.rated(rating)))
                                }
                                if let time = review.relativeTime {
                                    Text(verbatim: time)
                                }
                            }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    }
                    if let text = review.text {
                        Text(verbatim: text)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Color(.separator), lineWidth: 0.5))
                .accessibilityElement(children: .combine)
            }
        }
    }

    private var hours: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(place.openingHours.enumerated()), id: \.offset) { _, line in
                let row = MapItineraryExport.hoursRow(line)
                ViewThatFits(in: .horizontal) {
                    HStack {
                        Text(verbatim: row.day).fontWeight(.medium)
                        Spacer(minLength: 8)
                        Text(verbatim: row.hours).foregroundStyle(.secondary)
                    }
                    VStack(alignment: .leading, spacing: 1) {
                        Text(verbatim: row.day).fontWeight(.medium)
                        Text(verbatim: row.hours).foregroundStyle(.secondary)
                    }
                }
                .font(.subheadline)
                .accessibilityElement(children: .combine)
            }
        }
    }
}

// MARK: - Text

enum MapItineraryText {
    static func dayLabel(_ day: MapItineraryCardModel.Day) -> String {
        day.label.isEmpty
            ? String(localized: "ios:chat.card.map.dayFallback", defaultValue: "Day \(day.index + 1)", comment: "A day of an itinerary that has no name of its own. %lld is its number.")
            : day.label
    }

    static func more(_ count: Int) -> String {
        String(localized: "ios:chat.card.map.moreStops", defaultValue: "+\(count) more", comment: "Under the first stops of an itinerary card: how many other stops open with the full map.")
    }

    static func pagination(_ index: Int, _ total: Int) -> String { PageIndexText.position(index, of: total) }

    static func ratingNumber(_ rating: Double) -> String {
        rating.formatted(.number.precision(.fractionLength(1)))
    }

    /// "61K": the desktop's short review count, in the phone's own notation.
    static func compactCount(_ count: Int) -> String {
        count.formatted(.number.notation(.compactName).precision(.significantDigits(1...3)))
    }

    static func rated(_ rating: Double) -> String {
        String(localized: "ios:chat.card.map.rated", defaultValue: "Rated \(ratingNumber(rating)) out of 5", comment: "VoiceOver: a place's or a review's star rating. %@ is the rating, such as 4.7.")
    }

    static func ratedWithCount(_ rating: Double, _ count: Int) -> String {
        String(localized: "ios:chat.card.map.ratedWithCount", defaultValue: "Rated \(ratingNumber(rating)) out of 5 from \(count.formatted()) reviews", comment: "VoiceOver: a place's star rating. The first %@ is the rating, such as 4.7; the second how many reviews it comes from.")
    }

    /// The meta line under a stop's name: its type, its rating and whether it is open.
    static func meta(_ place: MapItineraryDetails.Place) -> String {
        var parts: [String] = []
        if let type = place.type { parts.append(type) }
        if let rating = place.rating {
            parts.append("★ \(ratingNumber(rating))" + (place.reviewCount.map { " (\(compactCount($0)))" } ?? ""))
        }
        if let open = place.openNow { parts.append(open ? openText : closedText) }
        return parts.joined(separator: " · ")
    }

    static func ratingAndType(_ place: MapItineraryDetails.Place) -> String {
        var parts: [String] = []
        if let rating = place.rating {
            parts.append(place.reviewCount.map { ratedWithCount(rating, $0) } ?? rated(rating))
        }
        if let type = place.type { parts.append(type) }
        return parts.joined(separator: ", ")
    }

    static func accessibilityLabel(_ stop: MapItineraryCardModel.Stop, dayLabel: String?) -> String {
        let number =
            if let dayLabel {
                String(localized: "ios:chat.card.map.dayStop", defaultValue: "\(dayLabel), stop \(stop.number)", comment: "VoiceOver: a stop listed with its day. %1$@ is the day, such as Day 2; %2$lld its number in that day.")
            } else {
                String(localized: "ios:chat.card.map.stopNumber", defaultValue: "Stop \(stop.number)", comment: "VoiceOver: a stop's number in its day.")
            }
        var parts = [number, stop.place.name]
        if let time = stop.place.timeLabel { parts.append(time) }
        if let type = stop.place.type { parts.append(type) }
        if let rating = stop.place.rating { parts.append(rated(rating)) }
        if let open = stop.place.openNow { parts.append(open ? openText : closedText) }
        if stop.coordinate == nil { parts.append(notOnMapText) }
        return parts.joined(separator: ", ")
    }

    static var openText: String { String(localized: "chat:placeDetail.open", defaultValue: "Open", comment: "A place is open now.") }
    static var closedText: String { String(localized: "chat:placeDetail.closed", defaultValue: "Closed", comment: "A place is closed now.") }
    static var notOnMapText: String {
        String(localized: "ios:chat.card.map.notOnMap", defaultValue: "Not on the map", comment: "A stop whose position the itinerary does not give, so it has no pin.")
    }

    static func bareHost(_ website: String) -> String {
        var text = website
        for prefix in ["https://", "http://"] where text.lowercased().hasPrefix(prefix) {
            text.removeFirst(prefix.count)
        }
        return text
    }

    static func initial(_ author: String?) -> String {
        author?.first.map { String($0).uppercased() } ?? "·"
    }
}

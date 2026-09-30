import Charts
import SwiftUI

extension EnvironmentValues {
    /// Whether a weather card starts open on Details; the prototype page shows both states.
    @Entry var weatherCardStartsOpen = false
}

/// The weather card, the desktop's: compact in the transcript — a line of now, the day's temperature curve and the
/// first three days as a segmented control — and the whole picture on Details, which opens it in place: the headline,
/// the readings, and the week as range-bar rows that also pick the day. The curve is the constant. Times are the
/// place's own; the condition's colour is in its icon, the curve takes the colour tone.
struct WeatherCard: View {
    let state: WeatherCardState

    var body: some View {
        switch state {
        case .forecast(let model): WeatherForecastCard(model: model)
        case .failed(let place, let message): WeatherFailedCard(place: place, message: message)
        }
    }
}

private struct WeatherForecastCard: View {
    let model: WeatherCardModel
    @State private var openState: Bool?
    @State private var dayIndex = 0
    @State private var scrubX: Double?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.weatherCardStartsOpen) private var startsOpen

    /// What a segmented control can hold; the rest waits behind Details.
    private static let compactDays = 3

    private var day: WeatherCardModel.Day? { model.days.indices.contains(dayIndex) ? model.days[dayIndex] : nil }
    private var now: WeatherCardModel.Now { model.now }
    private var expanded: Bool { openState ?? startsOpen }
    private var isLarge: Bool { dynamicTypeSize.isAccessibilitySize }
    private var motion: Animation? { reduceMotion ? nil : .snappy(duration: 0.25) }
    /// Under reduced motion the parts that come and go only fade.
    private var reveal: AnyTransition { reduceMotion ? .opacity : .opacity.combined(with: .move(edge: .top)) }

    /// The hourly slot under the finger while the curve is scrubbed.
    private var scrubbed: WeatherCardModel.Hour? {
        guard let scrubX, let day else { return nil }
        return day.hours.min { abs($0.x - scrubX) < abs($1.x - scrubX) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if expanded {
                headline.transition(reveal)
                if !model.readings.isEmpty { readings.transition(reveal) }
            } else {
                compactHeader.transition(.opacity)
            }
            if let day {
                if expanded {
                    Divider().padding(.horizontal, 16)
                    caption(day).transition(reveal)
                }
                if day.hasCurve { curve(day) }
                if expanded {
                    week.transition(reveal)
                } else {
                    segmentedDays.transition(.opacity)
                }
            }
            Divider()
            toggle
        }
        .clipped()
        .modifier(CardSurface())
    }

    private var toggle: some View {
        Button {
            withAnimation(motion) {
                // The compact control holds three days; leaving the week on a later one selects a tab that is not there.
                if expanded, dayIndex >= Self.compactDays { dayIndex = 0 }
                openState = !expanded
            }
        } label: {
            HStack(spacing: 4) {
                if expanded { Text("chat:weatherCard.less") } else { Text("chat:weatherCard.details") }
                Image(systemName: "chevron.down")
                    .rotationEffect(.degrees(expanded ? 180 : 0))
                    .accessibilityHidden(true)
            }
            .font(.caption.weight(.medium))
            .frame(maxWidth: .infinity, minHeight: 44)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .accessibilityValue(expanded ? Text("ios:chat.message.timeline.expanded") : Text("ios:chat.message.timeline.collapsed"))
    }

    // MARK: Now

    private var conditionIcon: some View {
        WeatherIcon(symbol: now.symbol)
            .accessibilityHidden(true)
    }

    private var place: Text {
        WeatherRuns.text((now.condition, .primary), (" · ", .tertiary), (model.location, .primary))
    }

    @ViewBuilder
    private var compactHeader: some View {
        Group {
            if isLarge {
                // At accessibility sizes the line of now cannot share a row with the day's hi/lo: one reading per line.
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 10) {
                        conditionIcon
                        Text(verbatim: "\(now.temp)°").fontWeight(.medium).monospacedDigit()
                    }
                    .font(.largeTitle)
                    Text(verbatim: WeatherCardText.feelsLike(now.feelsLike)).foregroundStyle(.secondary)
                    place.foregroundStyle(.secondary).lineLimit(4)
                    if let day { dayValue(day) }
                }
                .font(.caption)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.top, 14)
            } else {
                HStack(alignment: .center, spacing: 12) {
                    conditionIcon.font(.system(size: 32))
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(verbatim: "\(now.temp)°").font(.largeTitle.weight(.medium)).monospacedDigit()
                            Text(verbatim: WeatherCardText.feelsLike(now.feelsLike))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        place.font(.caption).foregroundStyle(.secondary).lineLimit(2)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    if let day {
                        VStack(alignment: .trailing, spacing: 2) {
                            dayValue(day)
                            Text(verbatim: dayDetail(day)).foregroundStyle(.secondary).lineLimit(1)
                        }
                        .font(.caption)
                        .fixedSize()
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 4)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(verbatim: WeatherCardText.summary(model)))
        .accessibilityValue(Text(verbatim: day.map(WeatherCardText.dayRange) ?? ""))
    }

    private var headline: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(alignment: .top, spacing: 0) {
                    Text(verbatim: now.temp).font(.system(size: 60, weight: .light)).monospacedDigit()
                    Text(verbatim: "°").font(.title.weight(.light)).foregroundStyle(.secondary).padding(.top, 6)
                }
                WeatherRuns.text((now.condition, .primary), (" · ", .tertiary), (model.location, .secondary))
                    .font(.subheadline)
                    .fixedSize(horizontal: false, vertical: true)
                Group {
                    if now.observedAt.isEmpty {
                        Text(verbatim: WeatherCardText.feelsLike(now.feelsLike))
                    } else {
                        WeatherRuns.text(
                            (WeatherCardText.feelsLike(now.feelsLike), .secondary), (" · ", .tertiary),
                            (WeatherCardText.observedAt(now.observedAt), .secondary))
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
            }
            Spacer(minLength: 8)
            conditionIcon.font(.system(size: 36))
        }
        .padding(16)
        .accessibilityElement(children: .combine)
    }

    private var readings: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), alignment: .topLeading), count: isLarge ? 1 : 3),
            alignment: .leading, spacing: 12
        ) {
            ForEach(model.readings, id: \.reading) { item in
                VStack(alignment: .leading, spacing: 3) {
                    Text(verbatim: WeatherCardText.label(item.reading)).font(.caption2).foregroundStyle(.secondary)
                    Text(verbatim: item.value).font(.subheadline.weight(.medium)).monospacedDigit()
                }
                .accessibilityElement(children: .combine)
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 14)
    }

    // MARK: The day

    /// The selected day's high/low, or the scrubbed hour's temperature and clock.
    private func dayValue(_ day: WeatherCardModel.Day) -> Text {
        if let hour = scrubbed {
            WeatherRuns.text(("\(hour.tempText)° ", .primary), (WeatherClock.format(hour.time, minutes: false), .secondary))
        } else {
            WeatherRuns.text(("\(day.high)°", .primary), ("/\(day.low)°", .secondary))
        }
    }

    private func dayDetail(_ day: WeatherCardModel.Day) -> String {
        scrubbed.map { WeatherCardText.rainChance($0.rainChance) } ?? day.condition
    }

    /// Open, the curve's caption: the compact header carried it.
    private func caption(_ day: WeatherCardModel.Day) -> some View {
        let layout = isLarge ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2)) : AnyLayout(HStackLayout())
        return layout {
            WeatherRuns.text((WeatherCardText.weekday(day), .primary), (" · \(day.condition)", .secondary))
            if !isLarge { Spacer(minLength: 8) }
            HStack(spacing: 0) {
                dayValue(day)
                Text(verbatim: " · \(dayDetail(day))").foregroundStyle(.secondary)
            }
        }
        .font(.caption)
        .monospacedDigit()
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .accessibilityElement(children: .combine)
    }

    private func curve(_ day: WeatherCardModel.Day) -> some View {
        let domain = day.curveDomain ?? 0...1
        let floor = domain.lowerBound
        return VStack(spacing: 2) {
            Chart(day.hours) { hour in
                AreaMark(x: .value("Hour", hour.x), yStart: .value("Floor", floor), yEnd: .value("Temperature", hour.temp))
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(.tint.opacity(0.14))
                LineMark(x: .value("Hour", hour.x), y: .value("Temperature", hour.temp))
                    .interpolationMethod(.catmullRom)
                    .foregroundStyle(.tint)
                    .lineStyle(StrokeStyle(lineWidth: 1.5, lineCap: .round))
                if let scrubbed, scrubbed.id == hour.id {
                    RuleMark(x: .value("Hour", hour.x)).foregroundStyle(.secondary.opacity(0.5))
                    PointMark(x: .value("Hour", hour.x), y: .value("Temperature", hour.temp)).foregroundStyle(.tint)
                }
            }
            .chartXAxis {
                AxisMarks(values: [0.0, 6, 12, 18]) { value in
                    // The first label starts at the plot's edge: centred on it, half of "12 AM" is cut off.
                    AxisValueLabel(anchor: value.index == 0 ? .topLeading : .top, collisionResolution: .disabled) {
                        if let hours = value.as(Double.self) {
                            Text(verbatim: WeatherClock.format(hours: hours, minutes: false))
                        }
                    }
                }
            }
            .chartYAxis(.hidden)
            .chartXScale(domain: 0...max(day.lastHour, 1))
            .chartYScale(domain: (floor - 1)...domain.upperBound)
            .chartXSelection(value: $scrubX)
            .frame(height: 76)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: WeatherCardText.chartLabel))
            .accessibilityValue(Text(verbatim: WeatherCardText.chartValue(day) ?? ""))
            HStack {
                sunTime(day.sunrise, systemImage: "sunrise.fill", label: Text("chat:weatherCard.sunrise"))
                Spacer()
                sunTime(day.sunset, systemImage: "sunset.fill", label: Text("chat:weatherCard.sunset"))
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func sunTime(_ time: String, systemImage: String, label: Text) -> some View {
        if !time.isEmpty {
            Label {
                Text(verbatim: WeatherClock.format(time)).monospacedDigit()
            } icon: {
                Image(systemName: systemImage)
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(label)
            .accessibilityValue(Text(verbatim: WeatherClock.format(time)))
        }
    }

    // MARK: Days

    private func select(_ index: Int) {
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.15)) {
            dayIndex = index
            scrubX = nil
        }
    }

    private var segmentedDays: some View {
        let layout = isLarge ? AnyLayout(VStackLayout(spacing: 4)) : AnyLayout(HStackLayout(spacing: 4))
        return layout {
            ForEach(model.days.prefix(Self.compactDays)) { forecast in
                let selected = forecast.id == dayIndex
                Button {
                    select(forecast.id)
                } label: {
                    HStack(spacing: 5) {
                        Text(verbatim: WeatherCardText.weekday(forecast)).lineLimit(1)
                        WeatherIcon(symbol: forecast.symbol)
                        WeatherRuns.text(("\(forecast.high)°", .primary), ("/\(forecast.low)°", .secondary))
                            .monospacedDigit()
                            .lineLimit(1)
                    }
                    .font(.caption.weight(selected ? .semibold : .regular))
                    .minimumScaleFactor(0.8)
                    .padding(.horizontal, 4)
                    .frame(maxWidth: .infinity, minHeight: 34)
                    .background {
                        if selected {
                            RoundedRectangle(cornerRadius: CardStyle.innerRadius - 3, style: .continuous)
                                .fill(Color(.systemBackground))
                                .shadow(color: .black.opacity(0.08), radius: 1, y: 1)
                        }
                    }
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .foregroundStyle(selected ? .primary : .secondary)
                .accessibilityLabel(Text(verbatim: WeatherCardText.dayRange(forecast)))
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        // A control set into the card, with the card's margin around it — not a band from edge to edge.
        .padding(3)
        .background(.fill.tertiary, in: CardStyle.innerShape)
        .padding(.horizontal, CardStyle.inset - 4)
        .padding(.top, 2)
        .padding(.bottom, 10)
    }

    private var week: some View {
        VStack(spacing: 0) {
            ForEach(model.days) { forecast in
                let selected = forecast.id == dayIndex
                Button {
                    select(forecast.id)
                } label: {
                    weekRow(forecast, selected: selected)
                        .font(.subheadline)
                        .padding(.horizontal, 8)
                        .padding(.vertical, isLarge ? 8 : 0)
                        .frame(minHeight: 40)
                        // The selected day is a row set into the card: it keeps the card's margin and its corner.
                        .background(selected ? AnyShapeStyle(.fill.tertiary) : AnyShapeStyle(.clear), in: CardStyle.innerShape)
                        .padding(.horizontal, CardStyle.inset - 8)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(Text(verbatim: WeatherCardText.dayRange(forecast)))
                .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private func weekRow(_ forecast: WeatherCardModel.Day, selected: Bool) -> some View {
        let name = Text(verbatim: WeatherCardText.weekday(forecast)).lineLimit(1)
        let icon = WeatherIcon(symbol: forecast.symbol)
        let low = Text(verbatim: "\(forecast.low)°").foregroundStyle(.secondary).monospacedDigit()
        let high = Text(verbatim: "\(forecast.high)°").fontWeight(.medium).monospacedDigit()
        if isLarge {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    icon
                    name
                }
                HStack(spacing: 8) {
                    low
                    RangeBar(bar: forecast.bar, selected: selected)
                    high
                }
            }
        } else {
            HStack(spacing: 10) {
                name.frame(width: 64, alignment: .leading).minimumScaleFactor(0.8)
                icon.frame(width: 24)
                low.frame(width: 34, alignment: .trailing)
                RangeBar(bar: forecast.bar, selected: selected)
                high.frame(width: 34, alignment: .trailing)
            }
        }
    }
}

/// A condition's symbol. Multicolour draws every cloud white, which vanishes on a light card, so a cloud is muted and
/// only what falls or shines from it keeps its colour (the desktop tints a condition the same way).
private struct WeatherIcon: View {
    let symbol: String

    var body: some View {
        if let accent = WeatherCondition.accent(of: symbol) {
            Image(systemName: symbol).symbolRenderingMode(.palette).foregroundStyle(Color.secondary, accent)
        } else if symbol.hasPrefix("cloud") {
            Image(systemName: symbol).symbolRenderingMode(.hierarchical).foregroundStyle(.secondary)
        } else {
            Image(systemName: symbol).symbolRenderingMode(.multicolor)
        }
    }
}

/// Text in runs of primary and secondary colour, the way the desktop sets a value beside its muted unit or context.
private enum WeatherRuns {
    enum Tone { case primary, secondary, tertiary }

    static func text(_ runs: (String, Tone)...) -> Text {
        var result = AttributedString()
        for (string, tone) in runs {
            var run = AttributedString(string)
            switch tone {
            case .primary: break
            case .secondary: run.foregroundColor = Color.secondary
            case .tertiary: run.foregroundColor = Color(.tertiaryLabel)
            }
            result += run
        }
        return Text(result)
    }
}

/// A day's low-to-high on the week's scale; the selected day's bar takes the curve's colour.
private struct RangeBar: View {
    let bar: WeatherCardModel.Bar?
    let selected: Bool
    /// A bar is a shape in the tone: its fill.
    @Environment(\.toneAccent) private var fill

    var body: some View {
        GeometryReader { proxy in
            Capsule()
                .fill(.fill.tertiary)
                .overlay(alignment: .leading) {
                    if let bar {
                        Capsule()
                            .fill(selected ? AnyShapeStyle(fill) : AnyShapeStyle(.primary.opacity(0.3)))
                            .frame(width: proxy.size.width * bar.width)
                            .offset(x: proxy.size.width * bar.start)
                    }
                }
        }
        .frame(height: 5)
        .accessibilityHidden(true)
    }
}

/// A failed call: the place it was asked for, and the tool's message.
private struct WeatherFailedCard: View {
    let place: String
    let message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "cloud.sun")
                    .foregroundStyle(.tint)
                    .frame(minWidth: 20)
                    .accessibilityLabel(Text(verbatim: ToolPresentation.displayName("weather")))
                Text(verbatim: place.isEmpty ? ToolPresentation.displayName("weather") : place)
                    .font(.subheadline.weight(.medium))
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                FileCardFailedIcon()
            }
            .cardHeader()
            .accessibilityElement(children: .combine)
            Divider()
            FileCardError(message: message ?? ToolPresentation.failedText("weather"))
        }
        .modifier(CardSurface())
    }
}

#if DEBUG
import Foundation
import Models

// The result `details` (and call arguments) each card reads, with the desktop's field names: read_file / write_file /
// edit_file / computer_use / deep_research / image_generation / map_itinerary in src/main/lib/ai/calling-tools, weather in
// packages/shared/src/types/weather.ts, memory in packages/shared/src/types/memory.ts. Decoded from JSON so a renamed
// field fails loudly here rather than drifting.

enum ProtoFixtures {
    static func decode<T: Decodable>(_ json: String) -> T {
        do {
            return try JSONDecoder().decode(T.self, from: Data(json.utf8))
        } catch {
            fatalError("Card prototype fixture does not decode: \(error)")
        }
    }
}

// MARK: - Files

/// read_file: arguments `{path, encoding?}`, details `{path, content, size}`. write_file: arguments `{path, content,
/// append?}`, details `{path, bytes, appended}`. edit_file: arguments `{path, old_string, new_string, replace_all?}`,
/// details `{path, replacements, linesBefore, linesAfter}` (the diff is the arguments'; the result only counts). The
/// real cards read these through `ToolCard`, the way the transcript builds them.
extension ProtoFixtures {
    static func json(_ text: String) -> JSONValue { decode(text) }

    static let readmeShort = json(#"""
        {"path":"/Users/me/Code/exodus/README.md","size":612,"content":"# Exodus\n\nA desktop AI chat app with a phone remote.\n\n## Getting started\n\n```bash\nbun install\nbun run start\n```\n\n- Configure a provider in Settings\n- Pair your iPhone from Settings → Devices\n\nSee docs/ for the design specs."}
        """#)

    static let longFile: JSONValue = {
        let lines = (1...300).map { index -> String in
            switch index % 10 {
            case 1: "// MARK: - Section \(index / 10 + 1)"
            case 2: "func step\(index)(input: [Int]) -> Int {"
            case 3: "    let filtered = input.filter { $0.isMultiple(of: \(index % 7 + 2)) }"
            case 4: "    return filtered.reduce(0, +) // a line long enough to wrap on a phone, which a file viewer must handle"
            case 5: "}"
            default: ""
            }
        }
        let content = lines.joined(separator: "\n")
        return .object([
            "path": .string("/Users/me/Code/app/Sources/Engine/Pipeline.swift"), "content": .string(content),
            "size": .number(Double(content.utf8.count)),
        ])
    }()

    static let writeArguments = json(#"""
        {"path":"/Users/me/.exodus/workspace/c1/notes/trip-plan.md","content":"# Kyoto, 3 days\n\n## Day 1\n- Fushimi Inari at 7:00, before the crowds\n- Lunch near Tofuku-ji\n- Gion in the evening\n\n## Day 2\n- Arashiyama bamboo grove\n- Tenryu-ji garden\n\n## Day 3\n- Nishiki Market\n- Train to Osaka at 16:00"}
        """#)

    static let writeDetails = json(#"""
        {"path":"/Users/me/.exodus/workspace/c1/notes/trip-plan.md","bytes":284,"appended":false}
        """#)

    static let appendArguments = json(#"""
        {"path":"/Users/me/Code/app/CHANGELOG.md","content":"## 1.4.1\n- Retry 429s with backoff","append":true}
        """#)

    static let appendDetails = json(#"""
        {"path":"/Users/me/Code/app/CHANGELOG.md","bytes":96,"appended":true}
        """#)

    static let editArguments = json(#"""
        {"path":"/Users/me/Code/app/Sources/Networking/RetryPolicy.swift","old_string":"struct RetryPolicy {\n    var maxAttempts = 3\n    var delay: Duration = .seconds(1)\n\n    func shouldRetry(_ status: Int) -> Bool {\n        status >= 500\n    }\n}","new_string":"struct RetryPolicy {\n    var maxAttempts = 5\n    var delay: Duration = .milliseconds(250)\n    var backoff = 2.0\n\n    func shouldRetry(_ status: Int) -> Bool {\n        status == 429 || status >= 500\n    }\n}","replace_all":false}
        """#)

    static let editDetails = json(#"""
        {"path":"/Users/me/Code/app/Sources/Networking/RetryPolicy.swift","replacements":1,"linesBefore":42,"linesAfter":43}
        """#)

    static let replaceAllArguments = json(#"""
        {"path":"/Users/me/Code/app/Sources/App/Theme.swift","old_string":"Color.blue","new_string":"Color.accentColor","replace_all":true}
        """#)

    static let replaceAllDetails = json(#"""
        {"path":"/Users/me/Code/app/Sources/App/Theme.swift","replacements":4,"linesBefore":88,"linesAfter":88}
        """#)
}

// MARK: - Computer use

extension ProtoFixtures {
    static let computerTask = "Export the Q3 revenue sheet as a PDF to the Desktop"
    static let computerTarget = "Numbers"
}

// MARK: - Deep research

/// deep_research: the result is `{id, toolCallId}`; the card reads the job's row from `GET /api/v1/deep-research/result/:id`
/// (`jobStatus` streaming → archived, `finalReport`, `webSources`, `startTime`, `endTime`) and, while it streams, its
/// progress messages from `/messages/:id` (JSON-RPC notifications, `params.data.type` the `DeepResearchProgress` number).
extension ProtoFixtures {
    static let researchSubject = "How are European cities cutting car traffic, and what worked?"

    static func researchRow(
        _ id: String, status: String, report: String? = nil, sources: String = "null", errorMessage: String? = nil
    ) -> String {
        let reportJSON = report.map { String(data: try! JSONEncoder().encode($0), encoding: .utf8)! } ?? "null"
        let errorJSON = errorMessage.map { String(data: try! JSONEncoder().encode($0), encoding: .utf8)! } ?? "null"
        return #"{"id":"\#(id)","toolCallId":"k","title":"\#(researchSubject)","jobStatus":"\#(status)","finalReport":\#(reportJSON),"webSources":\#(sources),"startTime":"2026-09-24T09:00:00.000Z","endTime":"2026-09-24T09:12:40.000Z","errorMessage":\#(errorJSON)}"#
    }

    private static func researchMessage(_ id: Int, _ data: String) -> String {
        #"{"id":"m\#(id)","deepResearchId":"dr","message":{"jsonrpc":"2.0","method":"message/deep-research","params":{"data":\#(data)}},"createdAt":"2026-09-24T09:\#(String(format: "%02d", id)):00.000Z"}"#
    }

    private static let researchQueries = [
        ("Paris 15-minute city car traffic results", "Measured change in car trips"),
        ("Barcelona superblocks traffic evaluation", "Before/after studies"),
        ("Ghent circulation plan 2017 outcomes", "Modal shift numbers"),
        ("Oslo car-free city centre retail impact", "Economic side effects"),
    ]

    /// The progress messages of a job `searched` searches in (each with its results and learnings), optionally writing.
    static func researchMessages(searched: Int, writing: Bool = false) -> String {
        var rows = [researchMessage(0, #"{"type":0}"#)]
        let planned = researchQueries.map { #"{"query":"\#($0.0)","researchGoal":"\#($0.1)"}"# }.joined(separator: ",")
        rows.append(researchMessage(1, #"{"type":1,"query":"\#(researchSubject)","searchQueries":[\#(planned)]}"#))
        for (index, query) in researchQueries.prefix(searched).enumerated() {
            let results = (0..<6).map { #"{"rank":\#($0 + 1),"link":"https://source\#(index)-\#($0).example.org/","title":"Result"}"# }
                .joined(separator: ",")
            rows.append(researchMessage(2 + index * 2, #"{"type":2,"query":"\#(query.0)","webSearchResults":[\#(results)]}"#))
            rows.append(
                researchMessage(3 + index * 2, #"{"type":3,"learnings":[{"learning":"a"},{"learning":"b"},{"learning":"c"}]}"#))
        }
        if writing { rows.append(researchMessage(9, #"{"type":4}"#)) }
        return "[" + rows.joined(separator: ",") + "]"
    }

    static let researchSources =
        #"[{"rank":1,"title":"Superblocks: evaluation report","link":"https://ajuntament.barcelona.cat/superilles","snippet":"Traffic inside the blocks fell by more than half.","hostname":"ajuntament.barcelona.cat"},{"rank":2,"title":"Ghent's circulation plan, five years on","link":"https://stad.gent/mobility","snippet":"Car trips in the centre fell by roughly a quarter.","hostname":"stad.gent"},{"rank":3,"title":"Paris: fewer cars, more bikes","link":"https://www.apur.org/en","snippet":"","hostname":"www.apur.org"},{"rank":4,"title":"Oslo's car-free liveability programme","link":"https://www.oslo.kommune.no/","snippet":"","hostname":"www.oslo.kommune.no"}]"#

    static let researchReport =
        "# Cutting car traffic in European cities\n\n## Summary\n\nThree approaches recur: **filtering through-traffic** out of neighbourhoods, **re-allocating street space** to walking, cycling and transit, and **pricing** entry. Ghent's circulation plan cut car trips in the centre by roughly a quarter within two years \u{3010}2-source\u{3011}, while Barcelona's superblocks reduced traffic inside the blocks by more than half \u{3010}1-source\u{3011}.\n\n## What worked\n\n- Quick, cheap interventions (planters, signage) that could be reversed if they failed\n- Measuring before and after, and publishing the numbers \u{3010}3-source\u{3011}\n- Pairing restrictions with better buses\n\n## What did not\n\n- Announcing plans without interim measures\n- Leaving delivery traffic out of the design\n\n| City | Measure | Change |\n| --- | --- | --- |\n| Ghent | Circulation plan | −25% car trips |\n| Barcelona | Superblocks | −58% traffic |"
}

// MARK: - Weather

/// weather: `{location, current{...}, forecast[{date, condition, weatherCode, maxTempC, minTempC, sunrise, sunset,
/// hourly[{time, tempC, weatherCode, condition, rainChance}]}]}`, numbers as strings, ISO local times; the legacy row is
/// wttr.in's (WWO codes, "06:52 AM" and "300" times, 8 slots a day, no `isDay`). The real card reads these through
/// `ToolCard`.
extension ProtoFixtures {
    private static func hourly(date: String, base: Double, codes: [String]) -> String {
        (0..<24).map { hour in
            let temp = base + 6 * sin((Double(hour) - 9) / 24 * 2 * .pi)
            let code = codes[hour * codes.count / 24]
            let rain = code == "61" || code == "63" || code == "80" ? 60 + hour % 4 * 5 : hour % 5 * 3
            return #"{"time":"\#(date)T\#(String(format: "%02d", hour)):00","tempC":"\#(Int(temp.rounded()))","weatherCode":"\#(code)","condition":"x","rainChance":"\#(rain)"}"#
        }
        .joined(separator: ",")
    }

    private static func weatherJSON(location: String, isDay: Bool) -> String {
        let days: [(String, String, String, Int, Int, [String])] = [
            ("2026-09-24", "Partly cloudy", "2", 24, 17, ["0", "1", "2", "2", "3", "2"]),
            ("2026-09-25", "Rain", "63", 20, 15, ["3", "61", "63", "63", "61", "3"]),
            ("2026-09-26", "Overcast", "3", 21, 14, ["3"]),
            ("2026-09-27", "Clear sky", "0", 25, 15, ["0"]),
            ("2026-09-28", "Mainly clear", "1", 26, 16, ["1"]),
            ("2026-09-29", "Thunderstorm", "95", 23, 18, ["2", "95", "95", "3"]),
            ("2026-09-30", "Fog", "45", 19, 13, ["45", "3"]),
        ]
        let forecast = days.map { day in
            #"{"date":"\#(day.0)","condition":"\#(day.1)","weatherCode":"\#(day.2)","maxTempC":"\#(day.3)","minTempC":"\#(day.4)","sunrise":"\#(day.0)T06:02","sunset":"\#(day.0)T18:11","hourly":[\#(hourly(date: day.0, base: Double(day.3 + day.4) / 2, codes: day.5))]}"#
        }
        return #"""
            {"location":"\#(location)","current":{"condition":"Partly cloudy","weatherCode":"2","tempC":"22","feelsLikeC":"21","humidity":"64","windKmph":"14","windDirDegree":"225","windDir":"SW","precipMM":"0.0","uvIndex":"5","visibility":"24","pressure":"1014","observedAt":"2026-09-24T14:15","isDay":\#(isDay)},"forecast":[\#(forecast.joined(separator: ","))]}
            """#
    }

    static let weatherShanghai = json(weatherJSON(location: "Shanghai, China", isDay: true))
    static let weatherLongName = json(
        weatherJSON(location: "Llanfairpwllgwyngyll-gogerychwyrndrobwllllantysiliogogogoch, Anglesey, Wales, United Kingdom", isDay: false))

    static let weatherLegacy: JSONValue = {
        let days: [(String, String, String, Int, Int)] = [
            ("2025-11-02", "Light rain shower", "353", 14, 9), ("2025-11-03", "Overcast", "122", 12, 8),
            ("2025-11-04", "Sunny", "113", 15, 7),
        ]
        let forecast = days.map { day in
            let hourly = stride(from: 0, through: 2100, by: 300).map { slot in
                let temp = day.4 + (day.3 - day.4) * (slot <= 1500 ? slot : 3000 - slot) / 1500
                return #"{"time":"\#(slot)","tempC":"\#(temp)","weatherCode":"\#(day.2)","condition":"\#(day.1)","rainChance":"\#(slot / 100)"}"#
            }
            return #"{"date":"\#(day.0)","condition":"\#(day.1)","weatherCode":"\#(day.2)","maxTempC":"\#(day.3)","minTempC":"\#(day.4)","sunrise":"06:52 AM","sunset":"04:58 PM","hourly":[\#(hourly.joined(separator: ","))]}"#
        }
        return json(#"""
            {"location":"Edinburgh, United Kingdom","current":{"condition":"Light rain shower","weatherCode":"353","tempC":"11","feelsLikeC":"8","humidity":"87","windKmph":"22","windDirDegree":"250","windDir":"WSW","precipMM":"0.4","uvIndex":"1","visibility":"10","pressure":"1006","observedAt":"02:15 PM"},"forecast":[\#(forecast.joined(separator: ","))]}
            """#)
    }()
}

// MARK: - Image generation

/// image_generation: arguments `{prompt}`, details `{images: [{mediaId, chatId, mimeType, width?, height?,
/// revisedPrompt?}], size?}`; legacy rows `{url}` (a `data:` URL or a DALL·E link).
extension ProtoFixtures {
    static let imagePrompt = "A lighthouse on a cliff at sunset, flat vector poster style"
    static let imageChatId = "3f0c2a4e-1b7d-4c1e-9a55-0d2b8f6c7e11"
    static let imageRevised =
        "A flat vector poster of a white lighthouse on a green cliff at sunset, warm orange and pink sky, a sun low on the horizon, simple geometric shapes."

    static func imageDetails(_ media: [String], size: String = "1024x1536", width: Int = 1024, height: Int = 1536) -> String {
        let images = media.map {
            #"{"mediaId":"\#($0)","chatId":"\#(imageChatId)","mimeType":"image/png","width":\#(width),"height":\#(height),"revisedPrompt":"\#(imageRevised)"}"#
        }
        return #"{"size":"\#(size)","images":[\#(images.joined(separator: ","))]}"#
    }

    static let imageError = "Image Generation requires an OpenAI API Key. Please add it in Settings → Providers."
}

// MARK: - Map itinerary

/// map_itinerary: arguments `{title?, days[{label, title?, summary?, routeMode?, places[{name, lat, lng, type?, timeLabel?,
/// note?}]}]}`, details `{type: "mapItinerary", title?, days[...places enriched with rating?, reviewCount?, phone?,
/// websiteUri?, googleMapsUri?, address?, openNow?, openingHours?, photoNames?, reviews?]], notice?}`.
extension ProtoFixtures {
    static let kyoto = json(#"""
        {"type":"mapItinerary","title":"Kyoto in two days","days":[
          {"label":"Day 1","title":"Southern Higashiyama","summary":"Shrines early, Gion by evening.","routeMode":"walking","places":[
            {"name":"Fushimi Inari Taisha","lat":34.9671,"lng":135.7727,"type":"Shinto shrine","timeLabel":"07:00","note":"Go before 8 to beat the crowds; the upper loop takes two hours.","rating":4.7,"reviewCount":61234,"address":"68 Fukakusa Yabunouchicho, Fushimi Ward, Kyoto","phone":"+81 75-641-7331","websiteUri":"https://inari.jp/","googleMapsUri":"https://maps.google.com/?cid=1","openNow":true,
             "openingHours":["Monday: Open 24 hours","Tuesday: Open 24 hours","Wednesday: Open 24 hours","Thursday: Open 24 hours","Friday: Open 24 hours","Saturday: Open 24 hours","Sunday: Open 24 hours"],
             "photoNames":["places/A/photos/1","places/A/photos/2"],
             "reviews":[{"author":"Mika Tanaka","authorPhotoUrl":"https://lh3.googleusercontent.com/a","rating":5,"text":"Thousands of vermilion gates. Early morning is magical and nearly empty.","relativeTime":"a month ago"},{"rating":4,"text":"Crowded at the bottom, but it thins out past the first viewpoint.","relativeTime":"2 weeks ago"}]},
            {"name":"Tofuku-ji","lat":34.9760,"lng":135.7737,"type":"Buddhist temple","timeLabel":"09:30","rating":4.6,"reviewCount":10321},
            {"name":"Sanjusangen-do","lat":34.9879,"lng":135.7717,"type":"Buddhist temple","timeLabel":"11:00","rating":4.7,"reviewCount":15877},
            {"name":"Kyoto National Museum","lat":34.9900,"lng":135.7730,"type":"Museum","timeLabel":"12:00","rating":4.4,"reviewCount":6210,"openNow":false},
            {"name":"Kiyomizu-dera","lat":34.9949,"lng":135.7850,"type":"Buddhist temple","timeLabel":"14:00","rating":4.6,"reviewCount":52011},
            {"name":"Sannenzaka","lat":34.9965,"lng":135.7811,"type":"Street","timeLabel":"15:30"},
            {"name":"Kodai-ji","lat":35.0005,"lng":135.7811,"type":"Buddhist temple","timeLabel":"16:15","rating":4.5,"reviewCount":8420},
            {"name":"Yasaka Shrine","lat":35.0037,"lng":135.7785,"type":"Shinto shrine","timeLabel":"17:30","rating":4.4,"reviewCount":30114},
            {"name":"Gion Shirakawa","lat":35.0056,"lng":135.7746,"type":"Neighbourhood","timeLabel":"19:00","note":"Dinner along the canal."}]},
          {"label":"Day 2","title":"Arashiyama","routeMode":"transit","places":[
            {"name":"Arashiyama Bamboo Grove","lat":35.0170,"lng":135.6713,"type":"Park","timeLabel":"08:00","rating":4.4,"reviewCount":41023},
            {"name":"Tenryu-ji","lat":35.0158,"lng":135.6737,"type":"Buddhist temple","timeLabel":"09:00","rating":4.5,"reviewCount":14200},
            {"name":"Togetsukyo Bridge","lat":35.0129,"lng":135.6778,"type":"Bridge","timeLabel":"11:00","rating":4.5,"reviewCount":16000}]}],
         "notice":{"level":"warning","message":"Live place data is unavailable — the Google API key has expired. The map shows your stops, but ratings, photos, phone numbers, and opening hours are missing. Check your key in Settings → Google Cloud."}}
        """#)

    /// Four days in Vienna, each its own colour; one stop the model gave no position for.
    static let vienna = json(#"""
        {"type":"mapItinerary","title":"Vienna, a music week","days":[
          {"label":"Mon","title":"Ring","routeMode":"walking","places":[
            {"name":"Staatsoper","lat":48.2030,"lng":16.3690,"type":"Opera house","timeLabel":"10:00"},
            {"name":"Musikverein","lat":48.2005,"lng":16.3726,"type":"Concert hall","timeLabel":"19:30"}]},
          {"label":"Tue","title":"Composers","places":[
            {"name":"Mozarthaus","lat":48.2079,"lng":16.3749,"type":"Museum"},
            {"name":"Beethoven Pasqualatihaus","lat":48.2139,"lng":16.3616,"type":"Museum"},
            {"name":"A café the guide recommends","type":"Café","note":"Ask at the hotel for the name."}]},
          {"label":"Wed","places":[
            {"name":"Schönbrunn Palace","lat":48.1845,"lng":16.3122,"type":"Palace"},
            {"name":"Gloriette","lat":48.1780,"lng":16.3087,"type":"Monument"}]},
          {"label":"Thu","routeMode":"transit","places":[
            {"name":"Zentralfriedhof","lat":48.1522,"lng":16.4406,"type":"Cemetery"},
            {"name":"Prater","lat":48.2166,"lng":16.3955,"type":"Park"}]}]}
        """#)

    /// A week in Phuket: seven days, so the day picker scrolls; times that only make sense under their day's name.
    static let phuket = json(#"""
        {"type":"mapItinerary","title":"Phuket, seven days","days":[
          {"label":"D1","title":"Arrival in Kamala","summary":"Land, check in, sunset on the beach.","places":[
            {"name":"Phuket International Airport","lat":8.1132,"lng":98.3169,"type":"Airport","timeLabel":"15:10"},
            {"name":"Kamala Beach","lat":7.9530,"lng":98.2830,"type":"Beach","timeLabel":"17:45"},
            {"name":"Cafe del Mar Phuket","lat":7.9589,"lng":98.2823,"type":"Beach club","timeLabel":"19:00","rating":4.4,"reviewCount":5120}]},
          {"label":"D2","title":"Old Town","places":[
            {"name":"Thalang Road","lat":7.8852,"lng":98.3885,"type":"Street","timeLabel":"10:00"},
            {"name":"Soi Romanee","lat":7.8858,"lng":98.3879,"type":"Street","timeLabel":"11:00"},
            {"name":"Khao Rang Viewpoint","lat":7.8934,"lng":98.3797,"type":"Viewpoint","timeLabel":"afternoon"}]},
          {"label":"D3","title":"Phi Phi by boat","routeMode":"transit","places":[
            {"name":"Rassada Pier","lat":7.8581,"lng":98.4156,"type":"Pier","timeLabel":"08:30"},
            {"name":"Maya Bay","lat":7.6781,"lng":98.7656,"type":"Bay","timeLabel":"all day"}]},
          {"label":"D4","title":"Big Buddha and Chalong","places":[
            {"name":"Big Buddha","lat":7.8276,"lng":98.3128,"type":"Monument","timeLabel":"09:00"},
            {"name":"Wat Chalong","lat":7.8467,"lng":98.3369,"type":"Temple","timeLabel":"11:00"}]},
          {"label":"D5","title":"Kata and Karon","places":[
            {"name":"Kata Beach","lat":7.8205,"lng":98.2976,"type":"Beach","timeLabel":"all day"},
            {"name":"Karon Viewpoint","lat":7.7986,"lng":98.3062,"type":"Viewpoint","timeLabel":"17:30"}]},
          {"label":"D6","title":"Phang Nga Bay","places":[
            {"name":"Ao Po Grand Marina","lat":8.0689,"lng":98.4446,"type":"Marina","timeLabel":"08:00"},
            {"name":"James Bond Island","lat":8.2745,"lng":98.5012,"type":"Island","timeLabel":"11:30"}]},
          {"label":"D7","title":"Departure","places":[
            {"name":"Naka Weekend Market","lat":7.8787,"lng":98.3732,"type":"Market","timeLabel":"morning"},
            {"name":"Phuket International Airport","lat":8.1132,"lng":98.3169,"type":"Airport","timeLabel":"18:20"}]}]}
        """#)

    /// A single lookup: one day, one stop.
    static let lookup = json(#"""
        {"type":"mapItinerary","days":[{"label":"Stop","places":[{"name":"Café Central","lat":48.2104,"lng":16.3655,"type":"Café","rating":4.4,"reviewCount":23810,"address":"Herrengasse 14, 1010 Wien","openNow":true}]}]}
        """#)

    /// No stop has a position: the card is a list.
    static let unplaced = json(#"""
        {"type":"mapItinerary","title":"Somewhere quiet","days":[{"label":"Day 1","places":[{"name":"The old harbour"},{"name":"A bakery by the station","note":"Opens at 6."}]}],"notice":{"level":"info","message":"Places enrichment was skipped."}}
        """#)

    static let mapError = "Map Itinerary requires a Google API Key. Please add it in Settings → Google Cloud."
}

// MARK: - Memory

/// update_memory's changes (`MemoryChange`: `{op, id, before, after}` of `MemorySnapshot` `{section, key, summary,
/// details, isActive}`), a run's used memories (`UsedMemory` `{id, key, section}`) and `GET /api/v1/memory` rows.
extension ProtoFixtures {
    static let memoryChanges: [MemoryChange] = decode(#"""
        [{"op":"update","id":"m1","before":{"section":"topic","key":"Classical Music","summary":"Listens to late Romantic symphonies.","details":["Favourite: Mahler 2","Prefers live recordings"],"isActive":true},
          "after":{"section":"topic","key":"Classical Music","summary":"Listens to late Romantic symphonies and Baroque keyboard music.","details":["Favourite: Mahler 2","Learning Bach's Goldberg Variations"],"isActive":true}},
         {"op":"create","id":"m2","before":null,"after":{"section":"profile","key":"Work setup","summary":"Works on a MacBook Pro with an external 5K display.","details":["Uses Xcode and VS Code"],"isActive":true}},
         {"op":"delete","id":"m3","before":{"section":"person","key":"Alex (old manager)","summary":"Former manager at the previous job.","details":[],"isActive":true},"after":null}]
        """#)

    static let usedMemories: [UsedMemory] = decode(#"""
        [{"id":"m2","key":"Work setup","section":"profile"},{"id":"m1","key":"Classical Music","section":"topic"},{"id":"m9","key":"Tokyo trip 2025","section":"topic"}]
        """#)

    /// The entries as they read now: each change above still as it left it; `m9` has been deleted since.
    static let currentMemories: [MemoryEntry] = decode(#"""
        [{"id":"m1","userId":"local","section":"topic","key":"Classical Music","summary":"Listens to late Romantic symphonies and Baroque keyboard music.","details":["Favourite: Mahler 2","Learning Bach's Goldberg Variations"],"confidence":null,"source":"explicit","isActive":true},
         {"id":"m2","userId":"local","section":"profile","key":"Work setup","summary":"Works on a MacBook Pro with an external 5K display.","details":["Uses Xcode and VS Code"],"confidence":null,"source":"explicit","isActive":null}]
        """#)
}
#endif

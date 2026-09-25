import Foundation
import Models

// The card prototypes' fixtures (Sources/ChatFeature/Prototypes/PrototypeFixtures.swift) as raw JSON, with the
// desktop's field names, plus the newer image_generation row shapes.
enum ToolResultFixtures {
    static func json(_ text: String) -> JSONValue {
        try! JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
    }

    static let readmeShort = #"""
        {"path":"/Users/me/Code/exodus/README.md","size":612,"content":"# Exodus\n\nA desktop AI chat app with a phone remote.\n\n## Getting started\n\n```bash\nbun install\nbun run start\n```\n\n- Configure a provider in Settings\n- Pair your iPhone from Settings → Devices\n\nSee docs/ for the design specs."}
        """#

    static let writeArguments = #"""
        {"path":"/Users/me/.exodus/workspace/c1/notes/trip-plan.md","content":"# Kyoto, 3 days\n\n## Day 1\n- Fushimi Inari at 7:00, before the crowds\n- Lunch near Tofuku-ji\n- Gion in the evening\n\n## Day 2\n- Arashiyama bamboo grove\n- Tenryu-ji garden\n\n## Day 3\n- Nishiki Market\n- Train to Osaka at 16:00"}
        """#

    static let writeDetails = #"""
        {"path":"/Users/me/.exodus/workspace/c1/notes/trip-plan.md","bytes":284,"appended":false}
        """#

    static let appendDetails = #"""
        {"path":"/Users/me/Code/app/CHANGELOG.md","bytes":96,"appended":true}
        """#

    static let editArguments = #"""
        {"path":"/Users/me/Code/app/Sources/Networking/RetryPolicy.swift","old_string":"struct RetryPolicy {\n    var maxAttempts = 3\n    var delay: Duration = .seconds(1)\n\n    func shouldRetry(_ status: Int) -> Bool {\n        status >= 500\n    }\n}","new_string":"struct RetryPolicy {\n    var maxAttempts = 5\n    var delay: Duration = .milliseconds(250)\n    var backoff = 2.0\n\n    func shouldRetry(_ status: Int) -> Bool {\n        status == 429 || status >= 500\n    }\n}","replace_all":false}
        """#

    static let editDetails = #"""
        {"path":"/Users/me/Code/app/Sources/Networking/RetryPolicy.swift","replacements":1,"linesBefore":42,"linesAfter":43}
        """#

    static let replaceAllArguments = #"""
        {"path":"/Users/me/Code/app/Sources/App/Theme.swift","old_string":"Color.blue","new_string":"Color.accentColor","replace_all":true}
        """#

    static let replaceAllDetails = #"""
        {"path":"/Users/me/Code/app/Sources/App/Theme.swift","replacements":4,"linesBefore":88,"linesAfter":88}
        """#

    static let computerRunning = #"""
        {"sessionId":"cu_7f3a","step":4,"action":"click File ▸ Export To ▸ PDF…","thumbnail":"<base64 png>"}
        """#

    static let computerAsking = #"""
        {"sessionId":"cu_7f3a","step":6,"action":"wait","thumbnail":"<base64 png>","awaitingHuman":{"question":"Numbers asks for a password to export this sheet. Type it on the computer, then tell me to continue."}}
        """#

    static let computerDone = #"""
        {"sessionId":"cu_7f3a","outcome":"success","steps":9,"summary":"Exported “Q3 Revenue” as Q3 Revenue.pdf on the Desktop (2 pages)."}
        """#

    static let computerStuck = #"""
        {"sessionId":"cu_91bc","outcome":"stuck","steps":25,"summary":"The Export dialog kept reopening after Save; I stopped after 25 steps without exporting."}
        """#

    static let computerError = #"{"error":"not-allowed"}"#

    static let researchStarted = #"{"id":"dr_42","toolCallId":"call_9"}"#

    static func hourly(date: String, base: Double, codes: [String]) -> String {
        (0..<24).map { hour in
            let temp = base + 6 * sin((Double(hour) - 9) / 24 * 2 * .pi)
            let code = codes[hour * codes.count / 24]
            let rain = code == "61" || code == "63" || code == "80" ? 60 + hour % 4 * 5 : hour % 5 * 3
            return #"{"time":"\#(date)T\#(String(format: "%02d", hour)):00","tempC":"\#(Int(temp.rounded()))","weatherCode":"\#(code)","condition":"x","rainChance":"\#(rain)"}"#
        }
        .joined(separator: ",")
    }

    static func weather(location: String, isDay: Bool) -> String {
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

    static let imageOne = #"""
        {"images":[{"url":"https://example.invalid/img-1.png","revisedPrompt":"A flat vector poster of a white lighthouse on a green cliff at sunset, warm orange and pink sky, a sun low on the horizon, simple geometric shapes."}]}
        """#

    static let imageTwo = #"""
        {"images":[{"url":"https://example.invalid/img-1.png","revisedPrompt":"Variant one."},{"url":"https://example.invalid/img-2.png","revisedPrompt":"Variant two."}]}
        """#

    static let kyoto = #"""
        {"type":"mapItinerary","title":"Kyoto in two days","days":[
          {"label":"Day 1","title":"Southern Higashiyama","summary":"Shrines early, Gion by evening.","routeMode":"walking","places":[
            {"name":"Fushimi Inari Taisha","lat":34.9671,"lng":135.7727,"type":"Shrine","timeLabel":"07:00","note":"Go before 8 to beat the crowds.","rating":4.7,"reviewCount":61234,"address":"68 Fukakusa Yabunouchicho","openNow":true},
            {"name":"Tofuku-ji","lat":34.9760,"lng":135.7737,"type":"Temple","timeLabel":"09:30","rating":4.6,"reviewCount":10321},
            {"name":"Sanjusangen-do","lat":34.9879,"lng":135.7717,"type":"Temple","timeLabel":"11:00","rating":4.7,"reviewCount":15877},
            {"name":"Kyoto National Museum","lat":34.9900,"lng":135.7730,"type":"Museum","timeLabel":"12:00","rating":4.4,"reviewCount":6210,"openNow":false},
            {"name":"Kiyomizu-dera","lat":34.9949,"lng":135.7850,"type":"Temple","timeLabel":"14:00","rating":4.6,"reviewCount":52011},
            {"name":"Sannenzaka","lat":34.9965,"lng":135.7811,"type":"Street","timeLabel":"15:30"},
            {"name":"Kodai-ji","lat":35.0005,"lng":135.7811,"type":"Temple","timeLabel":"16:15","rating":4.5,"reviewCount":8420},
            {"name":"Yasaka Shrine","lat":35.0037,"lng":135.7785,"type":"Shrine","timeLabel":"17:30","rating":4.4,"reviewCount":30114},
            {"name":"Gion Shirakawa","lat":35.0056,"lng":135.7746,"type":"Neighbourhood","timeLabel":"19:00","note":"Dinner along the canal."}]},
          {"label":"Day 2","title":"Arashiyama","routeMode":"transit","places":[
            {"name":"Arashiyama Bamboo Grove","lat":35.0170,"lng":135.6713,"type":"Park","timeLabel":"08:00","rating":4.4,"reviewCount":41023},
            {"name":"Tenryu-ji","lat":35.0158,"lng":135.6737,"type":"Temple","timeLabel":"09:00","rating":4.5,"reviewCount":14200},
            {"name":"Togetsukyo Bridge","lat":35.0129,"lng":135.6778,"type":"Landmark","timeLabel":"11:00","rating":4.5,"reviewCount":16000}]}],
         "notice":{"level":"warning","message":"The Places key has expired, so ratings and opening hours may be missing."}}
        """#

    /// A place as the desktop writes it after Places enrichment, with the notice an expired key leaves.
    static let enrichedPlace = #"""
        {"type":"mapItinerary","days":[{"label":"Day 1","routeMode":"walking","places":[
          {"name":"Kiyomizu-dera","lat":34.9949,"lng":135.785,"type":"Buddhist temple","timeLabel":"14:00","note":"Sunset from the stage.","rating":4.6,"reviewCount":52011,"phone":"+81 75-561-1234","websiteUri":"https://www.kiyomizudera.or.jp/","googleMapsUri":"https://maps.google.com/?cid=1","address":"1-294 Kiyomizu, Higashiyama Ward, Kyoto","openNow":true,
           "openingHours":["Monday: 6:00 AM – 6:00 PM","Tuesday: 6:00 AM – 6:00 PM"],"photoNames":["places/X/photos/A","places/X/photos/B"],
           "reviews":[{"author":"Ann","authorPhotoUrl":"https://lh3.googleusercontent.com/a","rating":5,"text":"Stunning.","relativeTime":"a month ago"},{"rating":4,"text":"Crowded but worth it.","relativeTime":"2 weeks ago"}]}]}],
         "notice":{"level":"warning","message":"Live place data is unavailable — the Google API key has expired. The map shows your stops, but ratings, photos, phone numbers, and opening hours are missing. Check your key in Settings → Google Cloud."}}
        """#

    static let memoryChanges = #"""
        [{"op":"update","id":"m1","before":{"section":"topic","key":"Classical Music","summary":"Listens to late Romantic symphonies.","details":["Favourite: Mahler 2","Prefers live recordings"],"isActive":true},
          "after":{"section":"topic","key":"Classical Music","summary":"Listens to late Romantic symphonies and Baroque keyboard music.","details":["Favourite: Mahler 2","Learning Bach's Goldberg Variations"],"isActive":true}},
         {"op":"create","id":"m2","before":null,"after":{"section":"profile","key":"Work setup","summary":"Works on a MacBook Pro with an external 5K display.","details":["Uses Xcode and VS Code"],"isActive":true}},
         {"op":"delete","id":"m3","before":{"section":"person","key":"Alex (old manager)","summary":"Former manager at the previous job.","details":[],"isActive":true},"after":null}]
        """#

    static let usedMemories = #"""
        [{"id":"m2","key":"Work setup","section":"profile"},{"id":"m1","key":"Classical Music","section":"topic"},{"id":"m9","key":"Tokyo trip 2025","section":"topic"}]
        """#
}

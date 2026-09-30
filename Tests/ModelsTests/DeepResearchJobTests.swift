import Foundation
import Models
import Testing

// Shapes of exodus's src/main/lib/server/routes/deep-research.ts: `/result/:id` is the `deep_research` row, `/messages/:id`
// the `deep_research_message` rows, each `message` the JSON-RPC notification `notifyClients` saved.

private func json(_ text: String) -> JSONValue {
    try! JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
}

enum DeepResearchFixtures {
    static let archived = #"""
        {"id":"0b6f1f7e-2c1d-4a53-9a55-1f0c3e0e9a11","toolCallId":"call_9","title":"Car traffic in European cities",
         "jobStatus":"archived","finalReport":"# Car traffic\n\nGhent cut trips 【2-source】.",
         "webSources":[{"rank":1,"link":"https://a.example/x","title":"A","content":"long","snippet":"s","hostname":"a.example"},
                       {"rank":2,"link":"https://b.example/y","title":"B","content":"","snippet":"","siteName":"B site","age":"2 days ago"},
                       {"rank":"x","link":"https://bad.example"}],
         "startTime":"2026-09-24T09:00:00.000Z","endTime":"2026-09-24T09:12:40.500Z"}
        """#

    static func message(_ id: String, _ data: String, at: String = "2026-09-24T09:01:00.000Z") -> String {
        #"{"id":"\#(id)","deepResearchId":"dr","message":{"jsonrpc":"2.0","method":"message/deep-research","params":{"data":\#(data)}},"createdAt":"\#(at)"}"#
    }
}

@Suite("Deep research: the job row and its progress messages")
struct DeepResearchJobTests {
    @Test("an archived row: status, report, dated times, and the sources that decode")
    func archived() throws {
        let job = try #require(DeepResearchJob(json: json(DeepResearchFixtures.archived)))
        #expect(job.status == .archived)
        #expect(job.title == "Car traffic in European cities")
        #expect(job.finalReport?.hasPrefix("# Car traffic") == true)
        #expect(job.webSources.map(\.rank) == [1, 2])
        #expect(job.webSources[0].hostname == "a.example")
        #expect(job.webSources[1].siteName == "B site")
        #expect(job.webSources[1].age == "2 days ago")
        let start = try #require(job.startTime)
        let end = try #require(job.endTime)
        #expect(end.timeIntervalSince(start) == 760.5)
    }

    @Test("every status of the schema is told apart; an unknown one is kept by name; no id or status is no row")
    func statuses() {
        func status(_ raw: String) -> DeepResearchJob.Status? {
            DeepResearchJob(json: json(#"{"id":"d","jobStatus":"\#(raw)","finalReport":null,"webSources":null}"#))?.status
        }
        #expect(status("streaming") == .streaming)
        #expect(status("failed") == .failed)
        #expect(status("terminated") == .terminated)
        #expect(status("paused") == .other("paused"))
        #expect(DeepResearchJob(json: json(#"{"id":"d","jobStatus":"streaming"}"#))?.webSources == [])
        #expect(DeepResearchJob(json: json(#"{"jobStatus":"archived"}"#)) == nil)
        #expect(DeepResearchJob(json: json(#"{"id":"d"}"#)) == nil)
        #expect(DeepResearchJob(json: json(#"{"id":"d","jobStatus":"archived","startTime":"yesterday"}"#))?.startTime == nil)
    }

    @Test("a failed row: its errorMessage and endTime; an older row has neither and still decodes")
    func failedRow() throws {
        let failed = try #require(
            DeepResearchJob(
                json: json(
                    #"{"id":"d","jobStatus":"failed","errorMessage":"APICallError: rate limited","finalReport":null,"webSources":null,"startTime":"2026-09-24T09:00:00.000Z","endTime":"2026-09-24T09:03:00.000Z"}"#
                )))
        #expect(failed.status == .failed)
        #expect(failed.errorMessage == "APICallError: rate limited")
        #expect(failed.endTime != nil)
        let blank = DeepResearchJob(json: json(#"{"id":"d","jobStatus":"failed","errorMessage":""}"#))
        #expect(blank?.errorMessage == nil)
        let older = try #require(DeepResearchJob(json: json(DeepResearchFixtures.archived)))
        #expect(older.errorMessage == nil)
    }

    @Test("each progress payload type decodes to its event; an unknown type is kept as unknown")
    func events() throws {
        func event(_ data: String) throws -> DeepResearchEvent {
            try #require(DeepResearchMessage(json: json(DeepResearchFixtures.message("m", data)))).event
        }
        #expect(try event(#"{"type":0}"#) == .started)
        let queries = try event(
            #"{"type":1,"query":"Cars","searchQueries":[{"query":"Ghent plan","researchGoal":"Numbers"},{"researchGoal":"no query"}],"deeper":true}"#)
        guard case .queries(let topic, let list, let deeper) = queries else {
            Issue.record("not queries")
            return
        }
        #expect(topic == "Cars")
        #expect(list.map(\.query) == ["Ghent plan"])
        #expect(list.first?.researchGoal == "Numbers")
        #expect(deeper)
        guard case .searched(let query, let results) = try event(
            #"{"type":2,"query":"Ghent plan","webSearchResults":[{"rank":1,"link":"https://g.example","title":"G","snippet":"","content":""}]}"#)
        else {
            Issue.record("not results")
            return
        }
        #expect(query == "Ghent plan")
        #expect(results.map(\.link) == ["https://g.example"])
        #expect(
            try event(#"{"type":3,"learnings":[{"learning":"Trips fell","citations":[1],"image":null},{"citations":[]}]}"#)
                == .learned(["Trips fell"]))
        #expect(try event(#"{"type":4}"#) == .writing)
        #expect(try event(#"{"type":5,"query":"Cars"}"#) == .completed(query: "Cars"))
        #expect(try event(#"{"type":6,"error":"TypeError: fetch failed"}"#) == .failed(error: "TypeError: fetch failed"))
        #expect(try event(#"{"type":6}"#) == .failed(error: ""))
        #expect(try event(#"{"type":9}"#) == .unknown)
        let message = try #require(DeepResearchMessage(json: json(DeepResearchFixtures.message("m1", #"{"type":0}"#))))
        #expect(message.id == "m1")
        #expect(message.createdAt != nil)
        #expect(DeepResearchMessage(json: json(#"{"id":"m","message":{"jsonrpc":"2.0"}}"#)) == nil)
    }
}

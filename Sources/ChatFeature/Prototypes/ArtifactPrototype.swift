#if DEBUG
import Foundation
import Models
import NetworkingKit
import SwiftUI

/// The artifact card, and its preview against a sandbox build on disk instead of a computer:
/// `-ArtifactSandboxDir <renderer build dir>` serves `exodus-artifact://sandbox/…` from that directory (a desktop
/// `vite build` of `vite.renderer.config.mts`; the Simulator reads the Mac's disk). Without it every request is a 404,
/// so Preview shows the "update Exodus on your computer" state. `-ArtifactPreviewOpen ok|broken` opens the preview of
/// the working or the broken sample at launch.
struct ProtoArtifactSection: View {
    @State private var opened: ArtifactResult?

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            UserBubble(text: "Chart our weekly active users against signups.")
            ProtoInReply(
                state: "Done · Preview renders it with the computer's sandbox", header: "Worked for 9 sec",
                answer: "Here is the chart: signups lead active users by about a week."
            ) {
                ToolCardView(card: Self.card(ProtoArtifactFixtures.working))
            }
            ProtoInReply(state: "Code that does not render · Preview falls back") {
                ToolCardView(card: Self.card(ProtoArtifactFixtures.broken))
            }
        }
        .environment(\.artifactSandbox, ProtoArtifactFixtures.source)
        .fullScreenCover(item: $opened) { artifact in
            ArtifactPreviewScreen(artifact: artifact)
                .environment(\.artifactSandbox, ProtoArtifactFixtures.source)
        }
        .task {
            switch ProtoArtifactFixtures.openAtLaunch {
            case "ok": opened = ProtoArtifactFixtures.working
            case "broken": opened = ProtoArtifactFixtures.broken
            default: break
            }
        }
    }

    private static func card(_ artifact: ArtifactResult) -> ToolCard {
        ToolCard(
            id: artifact.artifactId, toolName: "create_artifact", kind: .artifact,
            payload: .object([
                "type": .string("artifact"), "artifactId": .string(artifact.artifactId),
                "chatId": .string(artifact.chatId ?? ""), "title": .string(artifact.title), "code": .string(artifact.code),
            ]))
    }
}

extension ArtifactResult: @retroactive Identifiable {
    public var id: String { artifactId }
}

enum ProtoArtifactFixtures {
    static var openAtLaunch: String? { argument(after: "-ArtifactPreviewOpen") }

    /// Files from `-ArtifactSandboxDir`, typed by extension the way the computer types them; a 404 without it.
    static let source = ArtifactSandboxSource(
        file: { path, _ in
            guard let dir = argument(after: "-ArtifactSandboxDir"), path.hasPrefix(ArtifactSandboxRoute.apiPrefix) else {
                throw HTTPError(statusCode: 404, code: "NOT_FOUND", message: "Not found")
            }
            let relative = String(path.dropFirst(ArtifactSandboxRoute.apiPrefix.count))
            let url = URL(fileURLWithPath: dir).appendingPathComponent(relative)
            guard let data = FileManager.default.contents(atPath: url.path) else {
                throw HTTPError(statusCode: 404, code: "NOT_FOUND", message: "Not found")
            }
            return FetchedFile(data: data, contentType: contentType(url.pathExtension))
        },
        code: { _, _ in throw HTTPError(statusCode: 404, code: "NOT_FOUND", message: "Not found") })

    private static func contentType(_ ext: String) -> String {
        switch ext {
        case "html": "text/html; charset=utf-8"
        case "js", "mjs": "text/javascript; charset=utf-8"
        case "css": "text/css; charset=utf-8"
        case "woff2": "font/woff2"
        case "svg": "image/svg+xml"
        default: "application/octet-stream"
        }
    }

    private static func argument(after flag: String) -> String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }

    static let working = ArtifactResult(
        artifactId: "proto-artifact-ok", chatId: "proto-chat", title: "Weekly actives vs signups", code: workingCode)

    static let broken = ArtifactResult(
        artifactId: "proto-artifact-broken", chatId: "proto-chat", title: "Revenue by region",
        code: """
            const React = require('react')
            function Revenue() {
              const rows = undefined
              return <div>{rows.map((r) => <p key={r}>{r}</p>)}</div>
            }
            module.exports = { default: Revenue }
            """)

    private static let workingCode = """
        const React = require('react')
        const { useState } = React
        const { motion, useReducedMotion } = require('framer-motion')
        const { Card, CardContent } = require('@/ui/card')
        const { ResponsiveContainer, LineChart, Line, XAxis, YAxis, Tooltip, CartesianGrid } = require('recharts')

        const WEEKS = [
          { w: 'W1', active: 1200, signups: 180 }, { w: 'W2', active: 1310, signups: 240 },
          { w: 'W3', active: 1405, signups: 260 }, { w: 'W4', active: 1630, signups: 310 },
          { w: 'W5', active: 1790, signups: 290 }, { w: 'W6', active: 1920, signups: 350 }
        ]
        const EASE = [0.23, 1, 0.32, 1]

        function Growth() {
          const [series, setSeries] = useState('active')
          const reduced = useReducedMotion()
          const last = WEEKS[WEEKS.length - 1]
          return (
            <motion.div
              initial={{ opacity: 0, y: reduced ? 0 : 6 }}
              animate={{ opacity: 1, y: 0 }}
              transition={{ duration: 0.25, ease: EASE }}
              className="bg-background text-foreground"
              style={{ padding: 16 }}
            >
              <Card className="bg-card border-border rounded-lg shadow-xs">
                <CardContent className="divide-y divide-border" style={{ padding: 0 }}>
                  <div style={{ padding: '16px 16px 12px' }}>
                    <div className="text-muted-foreground" style={{ fontSize: 11, letterSpacing: '0.06em', textTransform: 'uppercase' }}>
                      Last six weeks
                    </div>
                    <div style={{ fontSize: 20, fontWeight: 600, marginTop: 4 }}>Weekly actives vs signups</div>
                    <div className="tabular-nums text-muted-foreground" style={{ fontSize: 13, marginTop: 6 }}>
                      Active <span className="text-primary" style={{ fontWeight: 500 }}>{last.active}</span> · Signups {last.signups}
                    </div>
                  </div>
                  <div style={{ padding: '12px 8px 4px', height: 220 }}>
                    <ResponsiveContainer width="100%" height="100%">
                      <LineChart data={WEEKS} margin={{ top: 8, right: 8, bottom: 0, left: -16 }}>
                        <CartesianGrid strokeDasharray="2 4" stroke="var(--border)" vertical={false} />
                        <XAxis dataKey="w" stroke="var(--muted-foreground)" fontSize={11} tickLine={false} axisLine={false} />
                        <YAxis stroke="var(--muted-foreground)" fontSize={11} tickLine={false} axisLine={false} />
                        <Tooltip contentStyle={{ background: 'var(--popover)', border: '1px solid var(--border)', borderRadius: 8, fontSize: 12 }} />
                        <Line type="monotone" dataKey={series} stroke="var(--primary)" strokeWidth={2} dot={false} isAnimationActive={!reduced} animationDuration={300} />
                      </LineChart>
                    </ResponsiveContainer>
                  </div>
                  <div className="bg-muted/40" style={{ display: 'flex', gap: 4, padding: 4 }}>
                    {['active', 'signups'].map((id) => (
                      <motion.button
                        key={id}
                        type="button"
                        whileTap={{ scale: 0.97 }}
                        onClick={() => setSeries(id)}
                        className={series === id ? 'bg-card text-foreground shadow-xs rounded-md' : 'text-muted-foreground rounded-md'}
                        style={{ flex: 1, padding: '6px 10px', fontSize: 13 }}
                      >
                        {id === 'active' ? 'Active' : 'Signups'}
                      </motion.button>
                    ))}
                  </div>
                </CardContent>
              </Card>
            </motion.div>
          )
        }

        module.exports = { default: Growth }
        """
}
#endif

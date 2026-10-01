// Sources/HealthFeature/UI/ReportCard.swift
import MarkdownKit
import Models
import OdyKit
import SwiftUI

/// The day's note: Ody writing while it is written, then the note easing in — as insight stories, or as the Markdown
/// note a report from before them carries; or why there is none.
struct ReportCard: View {
    let report: HealthHomeModel.Report
    let onConsent: () -> Void

    var body: some View {
        if case .ready(let summary) = report, let story = ReportStory(summary) {
            story.transition(.opacity)
        } else if report != .idle {
            Group {
                switch report {
                case .ready(let summary):
                    MarkdownView(text: summary.summary, isStreaming: false)
                        .transition(.blurReplace)
                case .writing:
                    row(.writing, "ios:health.report.writing")
                case .needsConsent:
                    VStack(alignment: .leading, spacing: 10) {
                        row(.permission, "ios:health.report.consentPrompt")
                        Button("ios:health.report.consentButton", action: onConsent)
                            .buttonStyle(.borderedProminent)
                            .tint(OdyPalette.marigold)
                    }
                case .offline: row(.offline, "ios:health.report.offline")
                case .needsModel: row(.noData, "ios:health.report.needsModel")
                case .failed: row(.noData, "ios:health.report.failed")
                case .idle: EmptyView()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(HealthSurface.card, in: .rect(cornerRadius: 18))
            .animation(.smooth, value: report)
        }
    }

    private func row(_ scene: OdyScene, _ text: LocalizedStringResource) -> some View {
        HStack(spacing: 12) {
            OdySceneView(scene).frame(width: 56, height: 56).clipShape(.rect(cornerRadius: 14))
            Text(text).font(.subheadline).foregroundStyle(.secondary)
        }
    }
}

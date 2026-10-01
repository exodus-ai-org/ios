#if DEBUG
import OdyKit
import SwiftUI

/// DEBUG-only visual check of OdyKit: `-OdyGallery` shows every scene, every expression, the sky through a day, the
/// heartbeat wave and a confetti button. Compare against `.superpowers/brainstorm/…/ody-states-v2.html`.
enum OdyGalleryLaunch {
    static var isEnabled: Bool { ProcessInfo.processInfo.arguments.contains("-OdyGallery") }
}

struct OdyGalleryView: View {
    @State private var confetti = 0

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 10)], spacing: 10) {
                    ForEach(OdyScene.allCases, id: \.self) { scene in
                        VStack(spacing: 4) {
                            OdySceneView(scene, pokable: true).clipShape(.rect(cornerRadius: 18))
                            Text(verbatim: scene.rawValue).font(.caption2)
                        }
                    }
                }
                HStack(spacing: 6) {
                    ForEach(OdyExpression.allCases, id: \.self) { e in
                        OdyView(expression: e).frame(height: 44)
                    }
                }
                HStack(spacing: 4) {
                    ForEach([0.0, 5.5, 6.2, 8, 12, 18, 19.5, 22], id: \.self) { h in
                        DaySkyView(clockHour: h).frame(height: 60).clipShape(.rect(cornerRadius: 8))
                    }
                }
                HeartbeatWave(bpm: 61, color: OdyPalette.hex(0xFF7E95)).frame(height: 90)
                    .background(OdyPalette.hex(0x4A0F1C), in: .rect(cornerRadius: 16))
                Button {
                    confetti += 1
                } label: {
                    Text(verbatim: "Confetti")
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(16)
        }
        .overlay { ConfettiView(trigger: confetti) }
    }
}
#endif

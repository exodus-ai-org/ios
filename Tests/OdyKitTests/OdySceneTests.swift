import SwiftUI
import Testing

@testable import OdyKit

struct OdySceneTests {
    @Test func placementConvertsTheMockupsUseElement() {
        // <use href="#ody-body" x="33" y="44" width="84" height="90"/> in the 150-unit scene.
        let r = OdyPlacement(x: 33, y: 44, w: 84, h: 90).bodyRect
        #expect(abs(r.minX - (33 + 32.0 / 624 * 84)) < 0.001)
        #expect(abs(r.width - 560.0 / 624 * 84) < 0.001)
        #expect(abs(r.minY - (44 + 30.0 / 660 * 90)) < 0.001)
        #expect(abs(r.height - 600.0 / 660 * 90) < 0.001)
    }

    @Test func everySceneHasArtThatParses() {
        for scene in OdyScene.allCases {
            for layer in SceneArt.layers(scene) {
                #expect(!SVGPath.path(layer.d).isEmpty, "\(scene) has an empty path")
            }
        }
    }

    @Test func theParsedCacheHoldsEveryLayer() {
        for scene in OdyScene.allCases {
            let parsed = ParsedArt.layers(scene)
            #expect(parsed.count == SceneArt.layers(scene).count, "\(scene)")
            #expect(parsed.allSatisfy { !$0.path.isEmpty }, "\(scene)")
        }
    }

    @Test func onlyScenesWithLoopingPropsTick() {
        let still: Set<OdyScene> = [.rested, .active, .noData, .permission, .offline]
        for scene in OdyScene.allCases {
            #expect(ParsedArt.loops(scene) == !still.contains(scene), "\(scene)")
        }
    }

    @Test func floatingPropsAreStaggered() {
        let phases = ParsedArt.layers(.hydrating).filter { $0.motion == .float }.map(\.phaseOffset)
        #expect(Set(phases).count == phases.count)
    }

    @Test @MainActor func everySceneRendersSmallAndLarge() {
        for scene in OdyScene.allCases {
            for side in [44.0, 300.0] {
                let r = ImageRenderer(content: OdySceneView(scene).frame(width: side, height: side))
                #expect(r.uiImage != nil)
            }
        }
    }
}

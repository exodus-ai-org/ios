// Sources/HealthFeature/UI/HealthOnboardingView.swift
import OdyKit
import SwiftUI

/// First visit: Ody with its heart asks for Apple Health, then for leave to send the day's summary to the user's AI
/// provider. Without the second, Health still shows the data and Ody — just no written note.
struct HealthOnboardingView: View {
    let model: HealthHomeModel
    @State private var step = 0

    var body: some View {
        VStack(spacing: 18) {
            Spacer()
            OdySceneView(step == 0 ? .permission : .writing, pokable: true)
                .frame(width: 200, height: 200)
                .clipShape(.rect(cornerRadius: 36))
                .contentTransition(.opacity)
            Text(step == 0 ? Self.titleText : Self.consentTitleText)
                .font(.title2.weight(.bold))
                .multilineTextAlignment(.center)
            Text(step == 0 ? Self.bodyText : Self.consentBodyText)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
            if step == 0 {
                Button {
                    Task {
                        await model.authorize()
                        withAnimation(.smooth) { step = 1 }
                    }
                } label: {
                    Text("ios:health.onboarding.connect").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
            } else {
                Button {
                    Task {
                        await model.grantConsent()
                        model.finishOnboarding()
                    }
                } label: {
                    Text("ios:health.onboarding.allow").frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                Button("ios:health.onboarding.notNow") {
                    model.finishOnboarding()
                    Task { await model.load() }
                }
            }
        }
        .padding(24)
    }

    // Resources, not bare literals: a ternary of literals can pick `Text`'s verbatim overload.
    private static let titleText = LocalizedStringResource("ios:health.onboarding.title")
    private static let bodyText = LocalizedStringResource("ios:health.onboarding.body")
    private static let consentTitleText = LocalizedStringResource("ios:health.onboarding.consentTitle")
    private static let consentBodyText = LocalizedStringResource("ios:health.onboarding.consentBody")
}

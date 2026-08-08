import SwiftUI

struct OnboardingView: View {
    let onComplete: (ASCCredentials) -> Void
    @State private var showAPIKeySetup = false

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            Image(systemName: "doc.badge.gearshape.fill")
                .font(.system(size: 72))
                .foregroundStyle(.blue)

            VStack(spacing: 12) {
                Text("Welcome to Stor")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("Manage your App Store Connect metadata with version history, keyword research, and screenshot creation — directly from your Mac.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 440)
            }

            VStack(spacing: 10) {
                Button("Connect App Store Connect") {
                    showAPIKeySetup = true
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)

                Text("Requires an API key from App Store Connect → Users and Access → Keys")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 20) {
                featurePill(icon: "lock.shield.fill", label: "Keychain stored")
                featurePill(icon: "network.slash", label: "No third-party relay")
                featurePill(icon: "arrow.clockwise", label: "Direct Apple API")
            }
            .padding(.bottom, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .sheet(isPresented: $showAPIKeySetup) {
            AddAPIKeyView(onSave: onComplete)
        }
    }

    private func featurePill(icon: String, label: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .foregroundStyle(.blue)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.quaternary, in: Capsule())
    }
}

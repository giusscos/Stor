import SwiftUI

struct OnboardingView: View {
    let onComplete: (ASCCredentials) -> Void
    @State private var showAPIKeySetup = false
    @State private var existingAccounts: [ASCCredentials] = []

    var body: some View {
        Group {
            if showAPIKeySetup {
                AddAPIKeyView(
                    onSave: onComplete,
                    onCancel: { showAPIKeySetup = false },
                    existingAccounts: existingAccounts,
                    initiallyShowForm: existingAccounts.isEmpty
                )
            } else {
                welcomeContent
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            existingAccounts = (try? KeychainService.shared.allAccounts()) ?? []
        }
    }

    private var welcomeContent: some View {
        VStack(spacing: 32) {
            Spacer()

            Image(systemName: "doc.badge.gearshape.fill")
                .font(.system(size: 72))
                .foregroundStyle(.blue)

            VStack(spacing: 12) {
                Text("Welcome to AscendKit")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                Text("Manage your App Store Connect metadata with version history, keyword research, and screenshot creation — directly from your Mac.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 440)
            }

            VStack(spacing: 10) {
                Button(existingAccounts.isEmpty ? "Connect App Store Connect" : "Choose Account") {
                    showAPIKeySetup = true
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .keyboardShortcut(.defaultAction)

                Text(
                    existingAccounts.isEmpty
                        ? "Requires an API key from App Store Connect → Users and Access → Keys"
                        : "You have \(existingAccounts.count) saved account\(existingAccounts.count == 1 ? "" : "s")"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            HStack(spacing: 20) {
                featurePill(icon: "lock.shield.fill", label: "Keychain stored")
                featurePill(icon: "person.2.fill", label: "Multi-account")
                featurePill(icon: "network.slash", label: "No third-party relay")
            }
            .padding(.bottom, 32)
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

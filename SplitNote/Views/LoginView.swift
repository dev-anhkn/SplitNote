//
//  LoginView.swift
//  SplitNote
//

import SwiftUI

struct LoginView: View {
    @StateObject private var viewModel = AuthViewModel()

    var body: some View {
        Group {
            if let user = viewModel.currentUser {
                WorkspaceListView(userDisplayName: user.displayName, userEmail: user.email, onSignOut: viewModel.signOut)
            } else {
                signInPrompt
            }
        }
        .task {
            await viewModel.restorePreviousSignIn()
        }
    }

    private var signInPrompt: some View {
        VStack(spacing: 40) {
            Spacer()

            VStack(spacing: 8) {
                Image(systemName: "square.split.2x1")
                    .font(.system(size: 48))
                    .foregroundStyle(.tint)
                Text("SplitNote")
                    .font(.largeTitle)
                    .fontWeight(.bold)
                Text("Split expenses with a single line of text")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(spacing: 12) {
                Button {
                    Task { await viewModel.signIn() }
                } label: {
                    HStack(spacing: 10) {
                        if viewModel.isSigningIn {
                            ProgressView()
                        } else {
                            Text("G")
                                .font(.system(size: 16, weight: .bold))
                        }
                        Text("Sign in with Google")
                            .font(.system(size: 16, weight: .medium))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.bordered)
                .tint(.primary)
                .disabled(viewModel.isSigningIn)

                if let message = viewModel.signInErrorMessage {
                    Text(message)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }
            .padding(.horizontal, 32)

            Spacer()
        }
    }
}

#Preview {
    LoginView()
}

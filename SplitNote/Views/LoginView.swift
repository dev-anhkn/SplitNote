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
        VStack(spacing: 28) {
            Spacer()
            appHeader
            featureCard
            Spacer()
            signInSection
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 24)
        .frame(maxWidth: 480)
        .frame(maxWidth: .infinity)
    }

    private var appHeader: some View {
        VStack(spacing: 14) {
            // Quầng sáng mờ sau icon cho màn chào bớt trống.
            ZStack {
                Circle()
                    .fill(Color.accentColor.opacity(0.18))
                    .frame(width: 130, height: 130)
                    .blur(radius: 18)
                IconBadge(systemName: "square.split.2x1.fill", color: .accentColor, size: 84)
                    .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
            }

            VStack(spacing: 6) {
                Text("SplitNote")
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                Text("Ghi chi tiêu và chia tiền chỉ bằng một dòng chữ")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var featureCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            FeatureRow(icon: "text.cursor", color: .blue, title: "Nhập nhanh", detail: "Gõ số tiền và nội dung, SplitNote tự phân loại.")
            FeatureRow(icon: "person.2.fill", color: .orange, title: "Chia cho gia đình", detail: "Ghi ai chi, chia cho ai trong cùng một sheet.")
            FeatureRow(icon: "tablecells.fill", color: .green, title: "Lưu trên Google Sheets", detail: "Dữ liệu nằm trong Drive của bạn.")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardStyle()
    }

    private var signInSection: some View {
        VStack(spacing: 12) {
            Button {
                Task { await viewModel.signIn() }
            } label: {
                HStack(spacing: 10) {
                    if viewModel.isSigningIn {
                        ProgressView()
                    } else {
                        Text("G")
                            .font(.system(size: 17, weight: .bold, design: .rounded))
                    }
                    Text("Đăng nhập với Google")
                        .font(.headline)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(viewModel.isSigningIn)

            if let message = viewModel.signInErrorMessage {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.red)
            }
        }
    }
}

private struct FeatureRow: View {
    let icon: String
    let color: Color
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            IconBadge(systemName: icon, color: color, size: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    LoginView()
}

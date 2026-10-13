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
        Group {
            #if os(macOS)
            macLayout
            #else
            iOSLayout
            #endif
        }
        .background(AppBackground())
    }

    // MARK: - Layouts

    /// macOS: theo Figma — nút đăng nhập ngay dưới header, cả khối căn giữa cửa sổ.
    private var macLayout: some View {
        VStack(spacing: 28) {
            appHeader
            signInSection
            featureList
            privacyFooter
        }
        .padding(40)
        .frame(maxWidth: LoginMetrics.contentMaxWidth)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// iOS: nút ghim ở đáy cho vùng ngón cái; nội dung cuộn được khi Dynamic Type lớn hoặc màn nhỏ.
    private var iOSLayout: some View {
        ScrollView {
            VStack(spacing: 36) {
                appHeader
                featureList
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 32)
            .frame(maxWidth: LoginMetrics.contentMaxWidth)
            .frame(maxWidth: .infinity)
        }
        .defaultScrollAnchor(.center, for: .alignment)
        .scrollBounceBehavior(.basedOnSize)
        .safeAreaBar(edge: .bottom) {
            VStack(spacing: 16) {
                signInSection
                privacyFooter
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 8)
            .frame(maxWidth: LoginMetrics.contentMaxWidth)
        }
    }

    // MARK: - Sections

    private var appHeader: some View {
        VStack(spacing: 20) {
            // Quầng sáng mờ sau icon cho màn chào bớt trống.
            ZStack {
                Circle()
                    .fill(AppStyle.gold.opacity(0.25))
                    .frame(width: LoginMetrics.logoSize * 1.5, height: LoginMetrics.logoSize * 1.5)
                    .blur(radius: 20)
                // Dùng chính icon app để màn chào và Dock/Home Screen khớp nhau.
                Image("AppLogo")
                    .resizable()
                    .frame(width: LoginMetrics.logoSize, height: LoginMetrics.logoSize)
            }

            VStack(spacing: 12) {
                Text("Chào mừng đến SplitNote")
                    .font(LoginMetrics.titleFont)
                Text("Ghi chi tiêu và chia tiền gia đình, đơn giản như ghi chú.")
                    .font(LoginMetrics.subtitleFont)
                    .foregroundStyle(.secondary)
            }
            .multilineTextAlignment(.center)
        }
    }

    private var featureList: some View {
        VStack(alignment: .leading, spacing: 20) {
            FeatureRow(icon: "bolt", color: AppStyle.gold, title: "Nhập nhanh", detail: "Ghi chi tiêu, chia theo người chỉ trong vài giây.")
            FeatureRow(icon: "person.2", color: AppStyle.indigo, title: "Chia cho gia đình", detail: "Rõ ai chi, chia cho ai trong cùng một nhóm.")
            FeatureRow(icon: "tablecells", color: .green, title: "Lưu trên Google Sheets", detail: "Dễ xem, xuất và kiểm tra ngay trong bảng tính.")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var signInSection: some View {
        VStack(spacing: 12) {
            GoogleSignInButton(isLoading: viewModel.isSigningIn) {
                Task { await viewModel.signIn() }
            }

            if let message = viewModel.signInErrorMessage {
                ErrorLabel(message: message)
                    .font(.footnote)
            }
        }
    }

    private var privacyFooter: some View {
        VStack(alignment: .leading, spacing: 14) {
            Divider()
            Label {
                Text("Dữ liệu trên Google Drive của bạn. SplitNote không có máy chủ riêng.")
            } icon: {
                Image(systemName: "lock")
                    .foregroundStyle(.green)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Kích thước khác nhau theo nền tảng: macOS dùng cỡ cố định, iOS theo Dynamic Type.
private enum LoginMetrics {
    static let contentMaxWidth: CGFloat = 480
    #if os(macOS)
    static let logoSize: CGFloat = 80
    static let featureIconSize: CGFloat = 52
    static let titleFont: Font = .system(size: 36, weight: .bold)
    static let subtitleFont: Font = .title3
    #else
    static let logoSize: CGFloat = 72
    static let featureIconSize: CGFloat = 48
    static let titleFont: Font = .largeTitle.bold()
    static let subtitleFont: Font = .body
    #endif
}

/// Theo hướng dẫn thương hiệu của Google: logo "G" chính thức, nền trắng/tối trung tính, viền xám.
private struct GoogleSignInButton: View {
    let isLoading: Bool
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    private var isDark: Bool { colorScheme == .dark }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 20, height: 20)
                } else {
                    Image("GoogleG")
                        .resizable()
                        .frame(width: 20, height: 20)
                }
                Text("Đăng nhập với Google")
                    .font(.system(size: 15, weight: .medium))
            }
            .foregroundStyle(isDark ? Color(white: 0.89) : Color(white: 0.12))
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(isDark ? Color(red: 0.075, green: 0.075, blue: 0.078) : .white, in: Capsule())
            .overlay(Capsule().stroke(isDark ? Color(white: 0.56) : Color(white: 0.46), lineWidth: 1))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isLoading)
    }
}

private struct FeatureRow: View {
    let icon: String
    let color: Color
    let title: String
    let detail: String

    var body: some View {
        HStack(spacing: 16) {
            IconBadge(systemName: icon, color: color, size: LoginMetrics.featureIconSize)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

#Preview {
    LoginView()
}

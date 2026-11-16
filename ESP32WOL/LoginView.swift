//
//  LoginView.swift
//  登录页：账号 + 密码，服务器内置不显示
//

import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var state: AppState

    @State private var user = AppConfig.defaultUser
    @State private var pass = AppConfig.defaultPassword
    @State private var showPass = false
    @FocusState private var focus: Field?

    private enum Field { case user, pass }

    var body: some View {
        ZStack {
            Palette.bg.ignoresSafeArea()

            VStack(spacing: 22) {
                Spacer(minLength: 40)
                brand
                fields
                loginButton
                hint
                Spacer(minLength: 20)
            }
            .padding(.horizontal, 26)
            .frame(maxWidth: 480)
        }
        .onAppear {
            user = state.currentUser
            focus = pass
        }
    }

    // MARK: - 品牌区

    private var brand: some View {
        VStack(spacing: 14) {
            ZStack {
                Circle()
                    .stroke(Palette.stroke, lineWidth: 5)
                    .frame(width: 76, height: 76)
                Circle()
                    .trim(from: 0, to: 0.86)
                    .stroke(
                        AngularGradient(colors: [Palette.accent,
                                                 Color(red: 0.20, green: 0.62, blue: 0.95),
                                                 Palette.accent],
                                        center: .center),
                        style: StrokeStyle(lineWidth: 5, lineCap: .round)
                    )
                    .rotationEffect(.degrees(-90))
                    .frame(width: 76, height: 76)
                Image(systemName: "power")
                    .font(.system(size: 26, weight: .heavy))
                    .foregroundStyle(Palette.accent)
            }

            VStack(spacing: 5) {
                Text("远程开机")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(Palette.text)
                Text("登录后唤醒你的电脑")
                    .font(.footnote)
                    .foregroundStyle(Palette.sub)
            }
        }
    }

    // MARK: - 输入

    private var fields: some View {
        VStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("账号")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Palette.sub)
                TextField("账号", text: $user)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .submitLabel(.next)
                    .focused($focus, equals: .user)
                    .onSubmit { focus = .pass }
                    .inputShell()
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("密码")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Palette.sub)
                HStack(spacing: 8) {
                    Group {
                        if showPass {
                            TextField("密码", text: $pass)
                        } else {
                            SecureField("密码", text: $pass)
                        }
                    }
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled(true)
                    .submitLabel(.go)
                    .focused($focus, equals: .pass)
                    .onSubmit { submit() }
                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                    .foregroundStyle(Palette.text)

                    Button {
                        showPass.toggle()
                    } label: {
                        Image(systemName: showPass ? "eye.slash" : "eye")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(Palette.sub)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 11)
                .background(Palette.bg)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }

            if !state.loginError.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.circle.fill")
                        .font(.system(size: 11, weight: .semibold))
                    Text(state.loginError)
                        .font(.caption2)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .foregroundStyle(Palette.bad)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var loginButton: some View {
        Button {
            submit()
        } label: {
            HStack(spacing: 8) {
                if state.loginBusy {
                    ProgressView().tint(Palette.ink).scaleEffect(0.85)
                } else {
                    Image(systemName: "lock.open.fill")
                        .font(.system(size: 12, weight: .semibold))
                }
                Text(state.loginBusy ? "登录中…" : "登录")
                    .font(.subheadline.weight(.bold))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(Palette.accent)
            .foregroundStyle(Palette.ink)
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .shadow(color: Palette.accent.opacity(0.20), radius: 16, y: 8)
        }
        .buttonStyle(PressStyle())
        .disabled(state.loginBusy)
    }

    private var hint: some View {
        VStack(spacing: 6) {
            HStack(spacing: 5) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 9, weight: .semibold))
                Text(AppConfig.serverLabel + " · 已连接")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
            }
            .foregroundStyle(Palette.sub.opacity(0.8))

            Text("账号密码和固件网页那组一致（默认账号 admin）。密码存在系统钥匙串，本机不上传。")
                .font(.caption2)
                .foregroundStyle(Palette.sub.opacity(0.7))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, 4)
    }

    private func submit() {
        let u = user
        let p = pass
        Task {
            await state.login(user: u, pass: p)
        }
    }
}

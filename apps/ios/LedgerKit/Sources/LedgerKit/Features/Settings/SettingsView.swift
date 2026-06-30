import ComposableArchitecture
import SwiftUI

/// App settings, presented as a native grouped Form sheet.
struct SettingsView: View {
    let store: StoreOf<SettingsFeature>

    // Bind controls straight to the shared storage (not through the presentation
    // store), so a text field committing as the sheet dismisses can't deliver a
    // presentation action to an absent destination.
    private var serverBinding: Binding<String> { Binding(store.state.$serverAddress) }
    private var tokenBinding: Binding<String> { Binding(store.state.$apiToken) }
    private var cameraBinding: Binding<Bool> { Binding(store.state.$cameraAuthorized) }
    private var themeBinding: Binding<AppTheme> { Binding(store.state.$theme) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Endereço") {
                        TextField("nfce.meucasa.app", text: serverBinding)
                            .multilineTextAlignment(.trailing)
                            .font(.body.monospaced())
                            .foregroundStyle(.secondary)
                    }
                    LabeledContent("Token de API") {
                        SecureField("••••••••••", text: tokenBinding)
                            .multilineTextAlignment(.trailing)
                    }
                } header: {
                    Text("Servidor")
                } footer: {
                    Text("Guardado com segurança no Keychain do dispositivo.")
                }

                Section {
                    Button { store.send(.testConnectionTapped) } label: {
                        HStack {
                            Spacer()
                            if store.connection == .testing {
                                ProgressView().controlSize(.small)
                                Text("Testando…").fontWeight(.semibold)
                            } else {
                                Text("Testar conexão").fontWeight(.semibold)
                            }
                            Spacer()
                        }
                    }
                    .disabled(store.connection == .testing)

                    connectionResult
                }

                Section {
                    Toggle(isOn: cameraBinding) {
                        Label("Câmera", systemImage: "camera.fill")
                    }
                    .tint(.green)
                    Picker(selection: themeBinding) {
                        ForEach(AppTheme.allCases, id: \.self) { theme in
                            Text(theme.label).tag(theme)
                        }
                    } label: {
                        Text("Tema")
                    }
                    .pickerStyle(.menu)
                } header: {
                    Text("Permissões")
                } footer: {
                    Text(store.cameraHint)
                }

                Section {
                } footer: {
                    Text("Caderneta 1.0 (12)")
                        .font(.footnote.monospaced())
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                }
            }
            .navigationTitle("Ajustes")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Concluído") { store.send(.doneTapped) }.fontWeight(.semibold)
                }
            }
        }
    }

    @ViewBuilder
    private var connectionResult: some View {
        switch store.connection {
        case let .ok(info):
            Label {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Conectado").font(.subheadline.weight(.semibold))
                    Text("servidor \(info.serverVersion) · \(info.purchaseCount) notas sincronizadas")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            }
        case .failed:
            Label {
                VStack(alignment: .leading, spacing: 1) {
                    Text("Não foi possível conectar").font(.subheadline.weight(.semibold))
                    Text("O servidor não respondeu em 10s. Verifique o endereço e o token.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            } icon: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
            }
        case .idle, .testing:
            EmptyView()
        }
    }
}

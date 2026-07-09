import ComposableArchitecture
import SwiftUI

struct ScanView: View {
    let store: StoreOf<ScanFeature>
    var isActive = true

    private var detecting: Bool { store.phase == .detecting }
    private var photoMode: Bool { store.scanMode == .photo }

    private var hintTitle: String {
        if photoMode { return detecting ? "Item reconhecido" : "Fotografe qualquer item" }
        return detecting ? "Nota detectada" : "Aponte para o QR code da nota"
    }

    private var hintSubtitle: String {
        if photoMode { return detecting ? "Identificando com IA…" : "A IA reconhece e adiciona ao histórico" }
        return detecting ? "Buscando os itens…" : "Salvamos automaticamente ao detectar"
    }

    var body: some View {
        ZStack {
            #if canImport(UIKit)
            if store.cameraAvailable && store.cameraAuthorized {
                LiveScannerView(
                    isActive: isActive,
                    idle: store.phase == .idle && store.scanMode == .receipt,
                    flashOn: store.flashOn,
                    onCode: { store.send(.codeScanned($0)) }
                )
                .ignoresSafeArea()
            } else {
                ScanBackground()
                    .ignoresSafeArea()
            }
            #else
            ScanBackground()
                .ignoresSafeArea()
            #endif

            ScanReticle(detecting: detecting, showsScanline: !photoMode)
                .frame(width: 236, height: 236)

            VStack(spacing: 0) {
                HStack {
                    glassButton(systemImage: "gearshape") { store.send(.settingsTapped) }
                    Spacer()
                    glassButton(
                        systemImage: store.flashOn ? "bolt.fill" : "bolt.slash.fill",
                        highlighted: store.flashOn
                    ) { store.send(.flashTapped) }
                }

                Spacer()

                VStack(spacing: 10) {
                    Text(hintTitle)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 11)
                        .background {
                            Capsule().fill(
                                detecting ? AnyShapeStyle(Color(hex: 0x28A745)) : AnyShapeStyle(.ultraThinMaterial)
                            )
                        }
                    Text(hintSubtitle)
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.white.opacity(0.6))
                }

                modeToggle
                    .padding(.top, 24)

                Group {
                    if photoMode {
                        captureRow
                    } else {
                        Button { store.send(.choosePhotoTapped) } label: {
                            Label("Escolher foto", systemImage: "photo.on.rectangle")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 18)
                                .padding(.vertical, 11)
                                .background(.ultraThinMaterial, in: Capsule())
                        }
                    }
                }
                .padding(.top, 20)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
            .animation(.easeInOut(duration: 0.2), value: photoMode)

            if !store.cameraAvailable {
                CameraUnavailableView()
                    .transition(.opacity)
            } else if !store.cameraAuthorized {
                PermissionDeniedView { store.send(.openSystemSettings) }
                    .transition(.opacity)
            }
        }
        .task { store.send(.onAppear) }
        .animation(.easeInOut(duration: 0.3), value: store.cameraAuthorized)
        .animation(.easeInOut(duration: 0.3), value: store.cameraAvailable)
        .animation(.easeInOut(duration: 0.25), value: detecting)
        .sheet(
            isPresented: Binding(
                get: { store.isSheetPresented },
                set: { if !$0 { store.send(.sheetDismissed) } }
            )
        ) {
            ScanResultView(store: store)
                .presentationDetents([.large])
                .presentationDragIndicator(.visible)
        }
    }

    private var modeToggle: some View {
        HStack(spacing: 3) {
            modePill("Nota fiscal", mode: .receipt)
            modePill("Foto", mode: .photo)
        }
        .padding(4)
        .background(.black.opacity(0.34), in: Capsule())
        .background(.ultraThinMaterial, in: Capsule())
    }

    private func modePill(_ title: String, mode: ScanMode) -> some View {
        Button { store.send(.modeChanged(mode)) } label: {
            Text(title)
                .font(.footnote.weight(.bold))
                .foregroundStyle(store.scanMode == mode ? Color.black : .white.opacity(0.72))
                .padding(.horizontal, 15)
                .padding(.vertical, 8)
                .background {
                    if store.scanMode == mode {
                        Capsule().fill(.white).shadow(color: .black.opacity(0.22), radius: 4, y: 2)
                    }
                }
        }
        .buttonStyle(.plain)
    }

    private var captureRow: some View {
        ZStack {
            Button { store.send(.shutterTapped) } label: {
                Circle()
                    .fill(.white)
                    .frame(width: 58, height: 58)
                    .overlay(Circle().strokeBorder(.black.opacity(0.06)))
                    .padding(4)
                    .overlay(Circle().strokeBorder(.white.opacity(0.95), lineWidth: 4))
                    .shadow(color: .black.opacity(0.32), radius: 10, y: 3)
            }
            .buttonStyle(.plain)

            HStack {
                Button { store.send(.choosePhotoTapped) } label: {
                    VStack(spacing: 5) {
                        Image(systemName: "photo.on.rectangle")
                            .font(.system(size: 17, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 46, height: 46)
                            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .strokeBorder(.white.opacity(0.28))
                            )
                        Text("Galeria")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                }
                .buttonStyle(.plain)
                .padding(.leading, 18)
                Spacer()
            }
        }
    }

    private func glassButton(systemImage: String, highlighted: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(highlighted ? Color.black : .white)
                .frame(width: 46, height: 46)
                .background {
                    if highlighted {
                        Circle().fill(Color.yellow)
                    } else {
                        Circle().fill(.ultraThinMaterial)
                    }
                }
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    ScanView(store: Store(initialState: ScanFeature.State()) { ScanFeature() })
}

private struct ScanBackground: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color(hex: 0x0B0F12), Color(hex: 0x070A0C), Color(hex: 0x05070A)],
                startPoint: .top, endPoint: .bottom
            )
            RadialGradient(
                colors: [Color(hex: 0xE0A33E).opacity(0.10), .clear],
                center: UnitPoint(x: 0.5, y: 0.16), startRadius: 0, endRadius: 320
            )
            RadialGradient(
                colors: [Color.appAccent.opacity(0.16), .clear],
                center: UnitPoint(x: 0.72, y: 0.9), startRadius: 0, endRadius: 320
            )
            VStack {
                Text("[ visão da câmera ao vivo ]")
                    .font(.system(.caption2, design: .monospaced))
                    .tracking(1)
                    .foregroundStyle(.white.opacity(0.26))
                    .padding(.top, 120)
                Spacer()
            }
        }
    }
}

private struct ScanReticle: View {
    let detecting: Bool
    var showsScanline = true

    @State private var scanLineOffset: CGFloat = -100
    @State private var rippleExpanded = false

    private let green = Color(hex: 0x34C759)

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(green.opacity(detecting ? 0.13 : 0))
                .padding(5)

            CornerBrackets()
                .stroke(detecting ? green : .white, style: StrokeStyle(lineWidth: 4, lineCap: .round))

            Rectangle()
                .fill(LinearGradient(colors: [.clear, Color.appAccent, .clear], startPoint: .leading, endPoint: .trailing))
                .frame(height: 3)
                .shadow(color: Color.appAccent, radius: 8)
                .padding(.horizontal, 12)
                .offset(y: scanLineOffset)
                .opacity(detecting || !showsScanline ? 0 : 1)

            RoundedRectangle(cornerRadius: 36, style: .continuous)
                .stroke(green, lineWidth: 2)
                .padding(-10)
                .scaleEffect(rippleExpanded ? 1.4 : 0.8)
                .opacity(detecting ? (rippleExpanded ? 0 : 0.55) : 0)

            if detecting {
                Image(systemName: "checkmark")
                    .font(.system(size: 34, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 78, height: 78)
                    .background(Circle().fill(green))
                    .shadow(color: green.opacity(0.5), radius: 14, y: 8)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                scanLineOffset = 100
            }
            withAnimation(.easeOut(duration: 1).repeatForever(autoreverses: false)) {
                rippleExpanded = true
            }
        }
    }
}

private struct CornerBrackets: Shape {
    var length: CGFloat = 42
    var radius: CGFloat = 16

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + length))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY + radius))
        path.addQuadCurve(to: CGPoint(x: rect.minX + radius, y: rect.minY), control: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX + length, y: rect.minY))
        path.move(to: CGPoint(x: rect.maxX - length, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY + radius), control: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY + length))
        path.move(to: CGPoint(x: rect.maxX, y: rect.maxY - length))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - radius))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - radius, y: rect.maxY), control: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - length, y: rect.maxY))
        path.move(to: CGPoint(x: rect.minX + length, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + radius, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - radius), control: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - length))
        return path
    }
}

private struct PermissionDeniedView: View {
    let openSettings: () -> Void

    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0x0E1114), Color(hex: 0x08090B)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Image(systemName: "video.slash.fill")
                    .font(.system(size: 34))
                    .foregroundStyle(.white.opacity(0.55))
                    .frame(width: 84, height: 84)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 23, style: .continuous))
                    .padding(.bottom, 22)

                Text("A câmera está bloqueada")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                Text("A Caderneta precisa da câmera para ler o QR code das notas. Libere o acesso para escanear.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.62))
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)
                    .frame(maxWidth: 300)

                Button(action: openSettings) {
                    Text("Abrir Ajustes do app")
                        .font(.headline)
                        .foregroundStyle(Color(hex: 0x0A0C0E))
                        .padding(.horizontal, 24)
                        .frame(height: 50)
                        .background(.white, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .padding(.top, 26)

                Text("Escolher uma foto")
                    .font(.callout)
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(.top, 16)
            }
            .padding(.horizontal, 40)
        }
    }
}

private struct CameraUnavailableView: View {
    var body: some View {
        ZStack {
            LinearGradient(colors: [Color(hex: 0x0E1114), Color(hex: 0x08090B)], startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                Image(systemName: "camera.metering.none")
                    .font(.system(size: 34))
                    .foregroundStyle(.white.opacity(0.55))
                    .frame(width: 84, height: 84)
                    .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 23, style: .continuous))
                    .padding(.bottom, 22)

                Text("Câmera indisponível")
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)

                Text("Não encontramos uma câmera neste dispositivo. Abra a Caderneta no seu iPhone para escanear as notas.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.62))
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)
                    .frame(maxWidth: 300)
            }
            .padding(.horizontal, 40)
        }
    }
}

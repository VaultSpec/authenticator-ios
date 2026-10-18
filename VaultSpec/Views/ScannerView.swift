import SwiftUI
import VisionKit

/// Live QR scanner. Frames are processed on device by VisionKit and never stored.
struct ScannerView: View {
    let onScan: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    /// Whether this device can scan at all (false on the Mac and on devices without a camera).
    static var isSupported: Bool { QRScanner.isSupported }

    var body: some View {
        ZStack(alignment: .top) {
            if QRScanner.isAvailable {
                QRScanner(onScan: onScan).ignoresSafeArea()

                RoundedRectangle(cornerRadius: 36, style: .continuous)
                    .strokeBorder(.white.opacity(0.9), lineWidth: 3)
                    .frame(width: 260, height: 260)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .allowsHitTesting(false)
            } else {
                ContentUnavailableView(
                    "Camera Unavailable",
                    systemImage: "camera.badge.ellipsis",
                    description: Text("Scanning needs a camera and camera access. You can paste the setup link or enter the key instead.")
                )
            }

            HStack {
                Text("Point at the QR code")
                    .font(.subheadline.weight(.semibold))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .glassEffect(.regular, in: .capsule)
                Spacer()
                Button("Close", systemImage: "xmark") { dismiss() }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.glass)
            }
            .padding(20)
        }
    }
}

#if targetEnvironment(macCatalyst)
/// VisionKit's live scanner is not available on the Mac.
private struct QRScanner: View {
    static let isAvailable = false
    static let isSupported = false
    let onScan: (String) -> Void
    var body: some View { EmptyView() }
}
#else
private struct QRScanner: UIViewControllerRepresentable {
    static var isAvailable: Bool { DataScannerViewController.isSupported && DataScannerViewController.isAvailable }
    static var isSupported: Bool { DataScannerViewController.isSupported }
    let onScan: (String) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: [.barcode(symbologies: [.qr])],
            qualityLevel: .balanced,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        try? scanner.startScanning()
        return scanner
    }

    func updateUIViewController(_ controller: DataScannerViewController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onScan: onScan) }

    final class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onScan: (String) -> Void
        private var handled = false

        init(onScan: @escaping (String) -> Void) { self.onScan = onScan }

        func dataScanner(_ scanner: DataScannerViewController, didAdd items: [RecognizedItem], allItems: [RecognizedItem]) {
            for case .barcode(let barcode) in items {
                guard !handled, let value = barcode.payloadStringValue, value.lowercased().hasPrefix("otpauth://") else { continue }
                handled = true
                scanner.stopScanning()
                onScan(value)
            }
        }
    }
}
#endif

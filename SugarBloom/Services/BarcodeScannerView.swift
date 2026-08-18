//
//  BarcodeScannerView.swift
//  Ocean Cast
//
//  Camera barcode capture. When there is no camera (Simulator, denied access)
//  the view reports the reason instead of pretending to scan.
//

import SwiftUI

#if os(iOS)
import AVFoundation
import UIKit

struct BarcodeScannerView: UIViewControllerRepresentable {
    var onCode: (String) -> Void
    var onFailure: (String) -> Void

    func makeUIViewController(context: Context) -> ScannerViewController {
        let controller = ScannerViewController()
        controller.onCode = onCode
        controller.onFailure = onFailure
        return controller
    }

    func updateUIViewController(_ uiViewController: ScannerViewController, context: Context) {}

    final class ScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
        var onCode: ((String) -> Void)?
        var onFailure: ((String) -> Void)?

        private let session = AVCaptureSession()
        private var preview: AVCaptureVideoPreviewLayer?
        private var hasReported = false

        override func viewDidLoad() {
            super.viewDidLoad()
            view.backgroundColor = .black
            configure()
        }

        override func viewDidLayoutSubviews() {
            super.viewDidLayoutSubviews()
            preview?.frame = view.bounds
        }

        override func viewWillDisappear(_ animated: Bool) {
            super.viewWillDisappear(animated)
            if session.isRunning {
                DispatchQueue.global(qos: .userInitiated).async { [session] in session.stopRunning() }
            }
        }

        private func configure() {
            switch AVCaptureDevice.authorizationStatus(for: .video) {
            case .authorized:
                start()
            case .notDetermined:
                AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                    DispatchQueue.main.async {
                        if granted { self?.start() }
                        else { self?.onFailure?("Camera access was not granted. You can still add the item by hand.") }
                    }
                }
            case .denied, .restricted:
                onFailure?("Camera access is off for Ocean Cast. Turn it on in Settings, or add the item by hand.")
            @unknown default:
                onFailure?("Camera access is unavailable. You can still add the item by hand.")
            }
        }

        private func start() {
            guard let device = AVCaptureDevice.default(for: .video),
                  let input = try? AVCaptureDeviceInput(device: device),
                  session.canAddInput(input) else {
                onFailure?("No camera is available on this device. You can still add the item by hand.")
                return
            }
            session.addInput(input)

            let output = AVCaptureMetadataOutput()
            guard session.canAddOutput(output) else {
                onFailure?("This device cannot read barcodes. You can still add the item by hand.")
                return
            }
            session.addOutput(output)
            output.setMetadataObjectsDelegate(self, queue: .main)
            output.metadataObjectTypes = [.ean8, .ean13, .upce, .code128, .code39, .itf14, .qr]

            let layer = AVCaptureVideoPreviewLayer(session: session)
            layer.videoGravity = .resizeAspectFill
            layer.frame = view.bounds
            view.layer.addSublayer(layer)
            preview = layer

            DispatchQueue.global(qos: .userInitiated).async { [session] in session.startRunning() }
        }

        func metadataOutput(_ output: AVCaptureMetadataOutput,
                            didOutput metadataObjects: [AVMetadataObject],
                            from connection: AVCaptureConnection) {
            guard !hasReported,
                  let object = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
                  let value = object.stringValue else { return }
            hasReported = true
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            onCode?(value)
            DispatchQueue.global(qos: .userInitiated).async { [session] in session.stopRunning() }
        }
    }
}
#else
struct BarcodeScannerView: View {
    var onCode: (String) -> Void
    var onFailure: (String) -> Void

    var body: some View {
        Color.black.onAppear {
            onFailure("Barcode scanning is available on iPhone and iPad. You can still add the item by hand.")
        }
    }
}
#endif

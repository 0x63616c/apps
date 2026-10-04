import Foundation
import CoreML
import Vision

struct RecognizedContent: Sendable {
    var text: String
    var visualLabels: [String]
}

/// Vision work runs on this actor, away from the UI. Each call owns its requests.
actor ImageAnalyzer {
    func analyze(imageData: Data) throws -> RecognizedContent {
        try Task.checkCancellation()
        let handler = VNImageRequestHandler(data: imageData, options: [:])
        let textRequest = VNRecognizeTextRequest()
        textRequest.recognitionLevel = .accurate
        textRequest.usesLanguageCorrection = true
        textRequest.automaticallyDetectsLanguage = true
        try configureCPUOnly(textRequest)
        try handler.perform([textRequest])
        try Task.checkCancellation()
        let text = (textRequest.results ?? [])
            .compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")

        // Classification is supplementary: failure must not discard successful OCR.
        let classifier = VNClassifyImageRequest()
        let labels: [String]
        do {
            try configureCPUOnly(classifier)
            try handler.perform([classifier])
            labels = (classifier.results ?? []).filter { $0.confidence >= 0.15 }
                .sorted { $0.confidence > $1.confidence }
                .prefix(8).map { $0.identifier.replacingOccurrences(of: "_", with: " ") }
        } catch {
            labels = []
        }
        try Task.checkCancellation()
        return RecognizedContent(text: text, visualLabels: labels)
    }

    /// A foreground Vision request can outlive a scene transition. Pin every
    /// supported stage to CPU even in the foreground, so an in-flight request
    /// never crosses into background GPU/Neural Engine work without entitlement.
    private func configureCPUOnly(_ request: VNRequest) throws {
        let stages = try request.supportedComputeStageDevices
        guard !stages.isEmpty else { throw CPUAnalysisError() }
        for (stage, devices) in stages {
            guard let cpu = devices.first(where: { if case .cpu = $0 { return true }; return false }) else {
                throw CPUAnalysisError()
            }
            request.setComputeDevice(cpu, for: stage)
        }
    }

    private struct CPUAnalysisError: LocalizedError {
        var errorDescription: String? { "CPU-only image analysis is unavailable on this device. Try scanning again." }
    }
}

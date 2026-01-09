import Foundation

/// Computes and refreshes the system access report based on current settings.
struct SystemAccessCoordinator: Sendable {
    private let probe: any SystemAccessProbing

    init(probe: any SystemAccessProbing) {
        self.probe = probe
    }

    func probe(settings: AppSettings) -> SystemAccessReport {
        probe.probe(settings: settings)
    }
}


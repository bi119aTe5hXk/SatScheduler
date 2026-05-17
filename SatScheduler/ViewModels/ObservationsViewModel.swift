//
//  ObservationsViewModel.swift
//  SatScheduler
//
//  Created by bi119aTe5hXk on 2026/05/17.
//
import Foundation
import Combine
@MainActor
final class ObservationsViewModel: ObservableObject {
	@Published var observations: [Observation] = []
	@Published var isLoading = false
	@Published var errorMessage: String?

	private let networkService = SatNOGSNetworkService()

	func loadUnknownObservations(observerID: Int) async {
		guard !isLoading else {
			return
		}

		isLoading = true
		defer {
			isLoading = false
		}

		do {
			observations = try await networkService.fetchUnknownObservations(observerID: observerID)
			errorMessage = nil
		} catch {
			errorMessage = "Failed to load observations: \(error.localizedDescription)"
		}
	}
}

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
	@Published var isLoadingNextPage = false
	@Published var errorMessage: String?

	private var nextCursor: String?
	private var canLoadMore = true
	private var currentObserverID: Int?

	private let networkService = SatNOGSNetworkService()
	private let observationsStore = ObservationsStore.shared

	init() {
		if let observerID = ObserverIDStore.shared.observerID {
			currentObserverID = observerID
			observations = observationsStore.loadUnknownObservations(observerID: observerID)
		}
	}

	func loadUnknownObservations(observerID: Int) async {
		await refreshUnknownObservations(observerID: observerID)
	}

	func refreshUnknownObservations(observerID: Int) async {
		guard !isLoading else {
			return
		}

		currentObserverID = observerID
		isLoading = true
		isLoadingNextPage = false
		defer {
			isLoading = false
		}

		do {
			let page = try await networkService.fetchUnknownObservationsPage(
				observerID: observerID,
				cursor: nil
			)

			observations = page.results
			nextCursor = page.nextCursor
			canLoadMore = nextCursor != nil
			observationsStore.saveUnknownObservations(observations, observerID: observerID)
			errorMessage = nil
		} catch {
			errorMessage = "Failed to load observations: \(error.localizedDescription)"
		}
	}

	func loadMoreUnknownObservationsIfNeeded(
		currentObservation: Observation?,
		observerID: Int? = nil
	) async {
		guard shouldLoadMore(currentObservation: currentObservation) else {
			return
		}

		let resolvedObserverID = observerID ?? currentObserverID
		guard let resolvedObserverID else {
			return
		}

		await loadNextPage(observerID: resolvedObserverID)
	}

	func loadNextPage(observerID: Int) async {
		guard !isLoading,
			  !isLoadingNextPage,
			  canLoadMore,
			  let nextCursor else {
			return
		}

		currentObserverID = observerID
		isLoadingNextPage = true
		defer {
			isLoadingNextPage = false
		}

		do {
			let page = try await networkService.fetchUnknownObservationsPage(
				observerID: observerID,
				cursor: nextCursor
			)

			appendUniqueObservations(page.results)
			self.nextCursor = page.nextCursor
			canLoadMore = page.nextCursor != nil
			observationsStore.saveUnknownObservations(observations, observerID: observerID)
			errorMessage = nil
		} catch {
			errorMessage = "Failed to load more observations: \(error.localizedDescription)"
		}
	}

	private func shouldLoadMore(currentObservation: Observation?) -> Bool {
		guard canLoadMore,
			  !isLoading,
			  !isLoadingNextPage,
			  !observations.isEmpty else {
			return false
		}

		guard let currentObservation else {
			return true
		}

		let thresholdIndex = observations.index(
			observations.endIndex,
			offsetBy: -min(5, observations.count)
		)
		let thresholdObservation = observations[thresholdIndex]
		return currentObservation.id == thresholdObservation.id || currentObservation.id == observations.last?.id
	}

	private func appendUniqueObservations(_ newObservations: [Observation]) {
		let existingIDs = Set(observations.map(\.id))
		let uniqueNewObservations = newObservations.filter { observation in
			!existingIDs.contains(observation.id)
		}

		observations.append(contentsOf: uniqueNewObservations)
	}
}

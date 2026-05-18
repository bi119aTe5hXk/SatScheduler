//
//  WatchTarget.swift
//  SatScheduler
//
//  Created by bi119aTe5hXk on 2026/05/16.
//

import Foundation

struct WatchTarget: Codable, Identifiable, Hashable {
	var id: UUID = UUID()

	var name: String

	var satelliteID: String
	var satelliteName: String?

	var transmitterID: String
	var transmitterDescription: String?
	var centerFrequency: Int? = nil
	
	var requireStationDaylight: Bool? = nil

	var requiresStationDaylight: Bool {
		requireStationDaylight == true
	}

	var stationIDs: [Int]
	var stationNames: [Int: String]? = nil
	var stationSnapshots: [Int: WatchStationSnapshot]? = nil

	var minElevation: Double?
	var enabled: Bool = true
	
	var minPeakElevation: Double? = nil
	var maxPeakElevation: Double? = nil
}

struct WatchStationSnapshot: Codable, Hashable {
	let id: Int
	let name: String
	let latitude: Double?
	let longitude: Double?
	let altitude: Double?
	let minHorizon: Double?
}

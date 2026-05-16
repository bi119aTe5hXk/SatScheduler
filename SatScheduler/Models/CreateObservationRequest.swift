//
//  CreateObservationRequest.swift
//  SatScheduler
//
//  Created by bi119aTe5hXk on 2026/05/16.
//

import Foundation

struct CreateObservationRequest: Codable {
	let ground_station: Int
	let transmitter: String
	let start: String
	let end: String
}

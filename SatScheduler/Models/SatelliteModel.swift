//
//  SatelliteModel.swift
//  SatScheduler
//
//  Created by bi119aTe5hXk on 2026/05/16.
//

import Foundation

struct SatelliteModel: Codable, Identifiable, Hashable {
	let sat_id: String
	let name: String?
	let names: String?
	let norad_cat_id: Int?
	let status: String?
	let image: String?
	let launched: String?
	let operatorName: String?
	let countries: String?
	let is_frequency_violator: Bool?

	var id: String {
		sat_id
	}

	enum CodingKeys: String, CodingKey {
		case sat_id
		case name
		case names
		case norad_cat_id
		case status
		case image
		case launched
		case operatorName = "operator"
		case countries
		case is_frequency_violator
	}

	init(
		sat_id: String,
		name: String?,
		names: String?,
		norad_cat_id: Int?,
		status: String?,
		image: String? = nil,
		launched: String? = nil,
		operatorName: String? = nil,
		countries: String? = nil,
		is_frequency_violator: Bool? = nil
	) {
		self.sat_id = sat_id
		self.name = name
		self.names = names
		self.norad_cat_id = norad_cat_id
		self.status = status
		self.image = image
		self.launched = launched
		self.operatorName = operatorName
		self.countries = countries
		self.is_frequency_violator = is_frequency_violator
	}

	init(from decoder: Decoder) throws {
		let container = try decoder.container(keyedBy: CodingKeys.self)

		self.sat_id = try container.decode(String.self, forKey: .sat_id)
		self.name = try container.decodeIfPresent(String.self, forKey: .name)
		self.norad_cat_id = try container.decodeIfPresent(Int.self, forKey: .norad_cat_id)
		self.status = try container.decodeIfPresent(String.self, forKey: .status)
		self.image = try container.decodeIfPresent(String.self, forKey: .image)
		self.launched = try container.decodeIfPresent(String.self, forKey: .launched)
		self.operatorName = try container.decodeIfPresent(String.self, forKey: .operatorName)
		self.countries = try container.decodeIfPresent(String.self, forKey: .countries)
		self.is_frequency_violator = try container.decodeIfPresent(Bool.self, forKey: .is_frequency_violator)

		if let namesString = try? container.decodeIfPresent(String.self, forKey: .names) {
			self.names = namesString
		} else if let namesArray = try? container.decodeIfPresent([String].self, forKey: .names) {
			self.names = namesArray.joined(separator: ", ")
		} else {
			self.names = nil
		}
	}
}

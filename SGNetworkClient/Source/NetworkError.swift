//
//  NetworkError.swift
//  NetworkClient
//
//  Created by Scott Gruby on 4/24/21.
//

import Foundation

public enum NetworkError: Error, Equatable {
    case invalidURL
    case cancelled
    case failedResponse(statusCode: Int, response: URLResponse?, body: Data?)
    case decodingFailure(data: Data?)
    case unauthorized(response: URLResponse, body: Data?)
}

extension NetworkError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case let .failedResponse(statusCode, _, _):
            return HTTPURLResponse.localizedString(forStatusCode: statusCode)
        case .unauthorized:
            return HTTPURLResponse.localizedString(forStatusCode: 401)
        default:
            return ""
        }
    }
}

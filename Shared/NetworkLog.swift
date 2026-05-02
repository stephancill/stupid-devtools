//
//  NetworkLog.swift
//  devtools
//

import SwiftData
import Foundation

@Model
class NetworkLog {
    @Attribute(.unique) var id: String
    var tabId: Int
    var tabURL: String
    var method: String
    var url: String
    var status: Int?
    var statusText: String?
    var requestHeaders: [String: String]?
    var requestBody: String?
    var requestCookies: [String: String]?
    var responseHeaders: [String: String]?
    var responseBody: String?
    var responseCookies: [String: String]?
    var error: String?
    var startTime: Date
    var endTime: Date?
    
    init(
        id: String,
        tabId: Int,
        tabURL: String,
        method: String,
        url: String,
        status: Int? = nil,
        statusText: String? = nil,
        requestHeaders: [String: String]? = nil,
        requestBody: String? = nil,
        requestCookies: [String: String]? = nil,
        responseHeaders: [String: String]? = nil,
        responseBody: String? = nil,
        responseCookies: [String: String]? = nil,
        error: String? = nil,
        startTime: Date,
        endTime: Date? = nil
    ) {
        self.id = id
        self.tabId = tabId
        self.tabURL = tabURL
        self.method = method
        self.url = url
        self.status = status
        self.statusText = statusText
        self.requestHeaders = requestHeaders
        self.requestBody = requestBody
        self.requestCookies = requestCookies
        self.responseHeaders = responseHeaders
        self.responseBody = responseBody
        self.responseCookies = responseCookies
        self.error = error
        self.startTime = startTime
        self.endTime = endTime
    }
}

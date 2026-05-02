//
//  SafariWebExtensionHandler.swift
//  devtools Extension
//

import SafariServices
import SwiftData
import os.log

class SafariWebExtensionHandler: NSObject, NSExtensionRequestHandling {
    
    private lazy var modelContainer: ModelContainer? = {
        let schema = Schema([DebugLog.self, NetworkLog.self])
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Settings.suiteName) else {
            os_log(.error, "Failed to get App Group container URL")
            return nil
        }
        let config = ModelConfiguration(
            schema: schema,
            url: containerURL.appendingPathComponent("logs.store"),
            cloudKitDatabase: .none
        )
        do {
            return try ModelContainer(for: schema, configurations: config)
        } catch {
            os_log(.error, "Failed to create ModelContainer: %@", error.localizedDescription)
            return nil
        }
    }()
    
    func beginRequest(with context: NSExtensionContext) {
        let request = context.inputItems.first as? NSExtensionItem
        
        let message: [String: Any]?
        if #available(iOS 15.0, macOS 11.0, *) {
            message = request?.userInfo?[SFExtensionMessageKey] as? [String: Any]
        } else {
            message = request?.userInfo?["message"] as? [String: Any]
        }
        
        guard let message = message, let type = message["type"] as? String else {
            completeRequest(context: context, response: ["error": "Invalid message"])
            return
        }
        
        os_log(.default, "Received message type: %@", type)
        
        switch type {
        case "STORE_LOG":
            handleStoreLog(message: message, context: context)
            
        case "STORE_NETWORK":
            handleStoreNetwork(message: message, context: context)
            
        case "TAB_CLOSED":
            if let tabId = message["tabId"] as? Int {
                handleTabClosed(tabId: tabId, context: context)
            } else {
                completeRequest(context: context, response: ["error": "Missing tabId"])
            }
            
        case "SYNC_ACTIVE_TABS":
            if let activeTabIds = message["activeTabIds"] as? [Int] {
                handleSyncActiveTabs(activeTabIds: activeTabIds, context: context)
            } else {
                completeRequest(context: context, response: ["error": "Missing activeTabIds"])
            }
            
        default:
            completeRequest(context: context, response: ["error": "Unknown message type"])
        }
    }
    
    // MARK: - Message Handlers
    
    private func handleStoreLog(message: [String: Any], context: NSExtensionContext) {
        guard let container = modelContainer,
              let logData = message["log"] as? [String: Any],
              let id = logData["id"] as? String,
              let tabId = message["tabId"] as? Int,
              let tabURL = message["tabURL"] as? String,
              let type = logData["type"] as? String,
              let timestamp = logData["timestamp"] as? Double else {
            completeRequest(context: context, response: ["error": "Invalid log data"])
            return
        }
        
        let args: [String]
        if let argsArray = logData["args"] as? [Any] {
            args = argsArray.map { arg in
                if let str = arg as? String {
                    return str
                } else if let dict = arg as? [String: Any] {
                    if let jsonData = try? JSONSerialization.data(withJSONObject: dict),
                       let jsonString = String(data: jsonData, encoding: .utf8) {
                        return jsonString
                    }
                }
                return String(describing: arg)
            }
        } else {
            args = []
        }
        
        let modelContext = ModelContext(container)
        
        // Enforce per-tab limit
        let maxLogs = Settings.maxLogsPerTab
        let predicate = #Predicate<DebugLog> { $0.tabId == tabId }
        let descriptor = FetchDescriptor<DebugLog>(predicate: predicate, sortBy: [SortDescriptor(\.timestamp)])
        
        if let existingLogs = try? modelContext.fetch(descriptor), existingLogs.count >= maxLogs {
            let toDelete = existingLogs.prefix(existingLogs.count - maxLogs + 1)
            for log in toDelete {
                modelContext.delete(log)
            }
        }
        
        let log = DebugLog(
            id: id,
            tabId: tabId,
            tabURL: tabURL,
            type: type,
            args: args,
            timestamp: Date(timeIntervalSince1970: timestamp / 1000)
        )
        
        modelContext.insert(log)
        
        do {
            try modelContext.save()
            completeRequest(context: context, response: ["success": true])
        } catch {
            os_log(.error, "Failed to save log: %@", error.localizedDescription)
            completeRequest(context: context, response: ["error": error.localizedDescription])
        }
    }
    
    private func handleStoreNetwork(message: [String: Any], context: NSExtensionContext) {
        guard let container = modelContainer,
              let requestData = message["request"] as? [String: Any],
              let id = requestData["id"] as? String,
              let tabId = message["tabId"] as? Int,
              let tabURL = message["tabURL"] as? String,
              let method = requestData["method"] as? String,
              let url = requestData["url"] as? String else {
            completeRequest(context: context, response: ["error": "Invalid request data"])
            return
        }
        
        let modelContext = ModelContext(container)
        
        // Check if this request already exists (update case)
        let predicate = #Predicate<NetworkLog> { $0.id == id }
        let descriptor = FetchDescriptor<NetworkLog>(predicate: predicate)
        
        if let existingRequests = try? modelContext.fetch(descriptor), let existing = existingRequests.first {
            // Update existing request with response data
            if let status = requestData["status"] as? Int {
                existing.status = status
            }
            if let statusText = requestData["statusText"] as? String {
                existing.statusText = statusText
            }
            if let responseHeaders = requestData["responseHeaders"] as? [String: String] {
                existing.responseHeaders = responseHeaders
            }
            if let responseBody = requestData["responseBody"] as? String {
                // Truncate if needed
                let maxSize = Settings.maxResponseBodySize
                existing.responseBody = responseBody.count > maxSize ? String(responseBody.prefix(maxSize)) + "... [truncated]" : responseBody
            }
            if let responseCookies = requestData["responseCookies"] as? [String: String] {
                existing.responseCookies = responseCookies
            }
            if let error = requestData["error"] as? String {
                existing.error = error
            }
            if let endTime = requestData["endTime"] as? Double {
                existing.endTime = Date(timeIntervalSince1970: endTime / 1000)
            }
        } else {
            // Enforce per-tab limit for new requests
            let maxRequests = Settings.maxNetworkRequestsPerTab
            let tabPredicate = #Predicate<NetworkLog> { $0.tabId == tabId }
            let tabDescriptor = FetchDescriptor<NetworkLog>(predicate: tabPredicate, sortBy: [SortDescriptor(\.startTime)])
            
            if let existingRequests = try? modelContext.fetch(tabDescriptor), existingRequests.count >= maxRequests {
                let toDelete = existingRequests.prefix(existingRequests.count - maxRequests + 1)
                for req in toDelete {
                    modelContext.delete(req)
                }
            }
            
            let startTime: Date
            if let startTimeMs = requestData["startTime"] as? Double {
                startTime = Date(timeIntervalSince1970: startTimeMs / 1000)
            } else {
                startTime = Date()
            }
            
            let requestBody: String?
            if let body = requestData["requestBody"] as? String {
                let maxSize = Settings.maxResponseBodySize
                requestBody = body.count > maxSize ? String(body.prefix(maxSize)) + "... [truncated]" : body
            } else {
                requestBody = nil
            }
            
            let networkLog = NetworkLog(
                id: id,
                tabId: tabId,
                tabURL: tabURL,
                method: method,
                url: url,
                status: requestData["status"] as? Int,
                statusText: requestData["statusText"] as? String,
                requestHeaders: requestData["requestHeaders"] as? [String: String],
                requestBody: requestBody,
                requestCookies: requestData["requestCookies"] as? [String: String],
                responseHeaders: requestData["responseHeaders"] as? [String: String],
                responseBody: nil,
                responseCookies: requestData["responseCookies"] as? [String: String],
                error: requestData["error"] as? String,
                startTime: startTime,
                endTime: nil
            )
            
            modelContext.insert(networkLog)
        }
        
        do {
            try modelContext.save()
            completeRequest(context: context, response: ["success": true])
        } catch {
            os_log(.error, "Failed to save network request: %@", error.localizedDescription)
            completeRequest(context: context, response: ["error": error.localizedDescription])
        }
    }
    
    private func handleTabClosed(tabId: Int, context: NSExtensionContext) {
        guard let container = modelContainer else {
            completeRequest(context: context, response: ["error": "No model container"])
            return
        }
        
        let modelContext = ModelContext(container)
        
        // Delete all logs for this tab
        let logPredicate = #Predicate<DebugLog> { $0.tabId == tabId }
        let logDescriptor = FetchDescriptor<DebugLog>(predicate: logPredicate)
        
        if let logs = try? modelContext.fetch(logDescriptor) {
            for log in logs {
                modelContext.delete(log)
            }
        }
        
        // Delete all network requests for this tab
        let networkPredicate = #Predicate<NetworkLog> { $0.tabId == tabId }
        let networkDescriptor = FetchDescriptor<NetworkLog>(predicate: networkPredicate)
        
        if let requests = try? modelContext.fetch(networkDescriptor) {
            for request in requests {
                modelContext.delete(request)
            }
        }
        
        do {
            try modelContext.save()
            os_log(.default, "Cleaned up data for closed tab: %d", tabId)
            completeRequest(context: context, response: ["success": true])
        } catch {
            os_log(.error, "Failed to clean up tab data: %@", error.localizedDescription)
            completeRequest(context: context, response: ["error": error.localizedDescription])
        }
    }
    
    private func handleSyncActiveTabs(activeTabIds: [Int], context: NSExtensionContext) {
        guard let container = modelContainer else {
            completeRequest(context: context, response: ["error": "No model container"])
            return
        }
        
        let modelContext = ModelContext(container)
        
        // Delete logs for tabs not in active list
        let logDescriptor = FetchDescriptor<DebugLog>()
        if let logs = try? modelContext.fetch(logDescriptor) {
            for log in logs where !activeTabIds.contains(log.tabId) {
                modelContext.delete(log)
            }
        }
        
        // Delete network requests for tabs not in active list
        let networkDescriptor = FetchDescriptor<NetworkLog>()
        if let requests = try? modelContext.fetch(networkDescriptor) {
            for request in requests where !activeTabIds.contains(request.tabId) {
                modelContext.delete(request)
            }
        }
        
        // Also clean up expired logs
        deleteExpiredLogs(modelContext: modelContext)
        
        do {
            try modelContext.save()
            os_log(.default, "Synced active tabs, keeping: %@", activeTabIds.map(String.init).joined(separator: ", "))
            completeRequest(context: context, response: ["success": true])
        } catch {
            os_log(.error, "Failed to sync active tabs: %@", error.localizedDescription)
            completeRequest(context: context, response: ["error": error.localizedDescription])
        }
    }
    
    private func deleteExpiredLogs(modelContext: ModelContext) {
        let cutoff = Date().addingTimeInterval(-Double(Settings.logRetentionHours) * 3600)
        
        // Delete expired console logs
        let logPredicate = #Predicate<DebugLog> { $0.timestamp < cutoff }
        let logDescriptor = FetchDescriptor<DebugLog>(predicate: logPredicate)
        
        if let expiredLogs = try? modelContext.fetch(logDescriptor) {
            for log in expiredLogs {
                modelContext.delete(log)
            }
            if !expiredLogs.isEmpty {
                os_log(.default, "Deleted %d expired console logs", expiredLogs.count)
            }
        }
        
        // Delete expired network logs
        let networkPredicate = #Predicate<NetworkLog> { $0.startTime < cutoff }
        let networkDescriptor = FetchDescriptor<NetworkLog>(predicate: networkPredicate)
        
        if let expiredRequests = try? modelContext.fetch(networkDescriptor) {
            for request in expiredRequests {
                modelContext.delete(request)
            }
            if !expiredRequests.isEmpty {
                os_log(.default, "Deleted %d expired network logs", expiredRequests.count)
            }
        }
    }
    
    // MARK: - Helpers
    
    private func completeRequest(context: NSExtensionContext, response: [String: Any]) {
        let responseItem = NSExtensionItem()
        if #available(iOS 15.0, macOS 11.0, *) {
            responseItem.userInfo = [SFExtensionMessageKey: response]
        } else {
            responseItem.userInfo = ["message": response]
        }
        context.completeRequest(returningItems: [responseItem], completionHandler: nil)
    }
}

//
//  NetworkClient+SendRequests.swift
//  NetworkClient
//
//  Copyright (c) 2021 Scott Gruby. All rights reserved.
//  Licensed under the MIT License.

import Foundation

extension NetworkClient {
    // This takes a method and path with no body and returns a Data object in the completion handler
    @discardableResult
    public func perform(method: HTTPMethod = .get, for path: String, completionHandler handler: ((NetworkResponse<Data>?) -> Void)? = nil) -> NetworkTask? {
        let request = NetworkRequest(method: method, path: path, logRequest: logRequests, logResponse: logResponses)
        request.retryCount = retryCount
        return perform(request: request, completionHandler: handler)
    }

    @discardableResult
    public func perform<T: Decodable>(method: HTTPMethod = .get, for path: String, resultType: T.Type, resultKey: String? = nil, completionHandler handler: ((NetworkResponse<T>?) -> Void)? = nil) -> NetworkTask? {
        return perform(method: method, for: path, body: Data(), resultType: resultType, resultKey: resultKey, completionHandler: handler)
    }
    
    // This takes a method and path with a encodable object that is encoded to JSON and returns a JSON parsed object in the completion handler.
    // ResultKey is used if the object you want to get back is not the full JSON response.
    @discardableResult
    public func perform<T: Decodable, Body: Encodable>(method: HTTPMethod = .get, for path: String, body: Body, resultType: T.Type, resultKey: String? = nil, completionHandler handler: ((NetworkResponse<T>?) -> Void)? = nil) -> NetworkTask? {
        let request = NetworkRequest(method: method, path: path, body: body, logRequest: logRequests, logResponse: logResponses)
        request.retryCount = retryCount
        return perform(request: request, resultType: resultType, resultKey: resultKey, completionHandler: handler)
    }
    
    // This takes a request with no body and returns a Data object in the completion handler
    @discardableResult
    public func perform(request: NetworkRequest, completionHandler handler: ((NetworkResponse<Data>?) -> Void)? = nil) -> NetworkTask? {
        return perform(request: request, resultType: Data.self, completionHandler: handler)
    }

    // This takes a request and returns a JSON parsed object in the completion handler.
    // ResultKey is used if the object you want to get back is not the full JSON response.
    @discardableResult
    public func perform<T: Decodable>(request: NetworkRequest, resultType: T.Type, resultKey: String? = nil, completionQueue: DispatchQueue? = nil, completionHandler handler: ((NetworkResponse<T>?) -> Void)? = nil) -> NetworkTask? {
        let completionQueue = completionQueue ?? self.completionQueue
        
        guard let preparedURLRequest = request.prepareURLRequest(with: self, alwaysWriteToFile: handler == nil) else {handler?(NetworkResponse(error: NetworkError.invalidURL, httpResponse: nil, result: nil)); return nil}

        // The individual request can turn off logging
        if request.logRequest == true && logRequests == true {
            log(preparedRequest: preparedURLRequest)
        }

        let taskHandler: (Data?, URLResponse?, Error?) -> Void = {[weak self] (data, urlResponse, error) in
            guard let self = self else {return}
            
            if request.logResponse == true && self.logResponses == true {
                self.log(urlResponse: urlResponse, data: data, error: error)
            }
            
            let response = NetworkClient.handleResponse(resultType: resultType, resultKey: resultKey, data: data, urlResponse: urlResponse, error: error)
            
            if self.shouldRetry(request: request, error: error) == true {
                let newRequest = request
                newRequest.retryCount = request.retryCount - 1
                self.perform(request: request, resultType: resultType, resultKey: resultKey, completionHandler: handler)
            } else {
                completionQueue.async {
                    handler?(response)
                }

                // Remove the request from our list
                if let networkTask = self.networkTask(for: request.uuid) {
                    if let tempFileURL = networkTask.tempFileURL {
                        try? FileManager.default.removeItem(at: tempFileURL)
                    }
                    self.removeTask(networkTask)
                }
            }
        }
        
        var task: URLSessionTask?
        if let uploadData = preparedURLRequest.data {
            task = urlSession.uploadTask(with: preparedURLRequest.request, from: uploadData, completionHandler: taskHandler)
        } else if let uploadFileURL = preparedURLRequest.tempFile {
            var expectedBytesToSend: Int64 = 0
            if let attributes = try? FileManager.default.attributesOfItem(atPath: uploadFileURL.path), let size = attributes[.size] as? NSNumber {
                expectedBytesToSend = size.int64Value
            }
            
            if handler != nil {
                task = urlSession.uploadTask(with: preparedURLRequest.request, fromFile: uploadFileURL, completionHandler: taskHandler)
            } else {
                task = urlSession.uploadTask(with: preparedURLRequest.request, fromFile: uploadFileURL)
            }

            if expectedBytesToSend > 0 {
                task?.countOfBytesClientExpectsToSend = expectedBytesToSend
            }
            
                
        } else {
            task = urlSession.dataTask(with: preparedURLRequest.request, completionHandler: taskHandler)
        }
        
        guard let sessionTask = task else {return nil}
        
        let requestNetworkTask: NetworkTask = networkTask(for: request.uuid) ?? NetworkTask(sessionTask, request: request)
        requestNetworkTask.dataTask = sessionTask
        requestNetworkTask.tempFileURL = preparedURLRequest.tempFile
        
        lockingQueue.async {[weak self] in
            guard let self = self else {return}
            self.networkTasks.insert(requestNetworkTask)
        }

        sessionTask.resume()
        return requestNetworkTask
    }
    }

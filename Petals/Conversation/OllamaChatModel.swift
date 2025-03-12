//
//  OllamaChatModel.swift
//  Petals
//
//  Created by Aadi Shiv Malhotra on 2/15/25.
//

import Foundation
import PetalTools

/// A chat model that interfaces with the Ollama service for handling AI-generated responses.
///
/// This model supports both single-response messaging and streaming responses, leveraging
/// the `OllamaService` to communicate with the locally hosted Ollama model.
class OllamaChatModel: AIChatModel {
    // **MARK: Private Properties**

    /// The service responsible for communicating with the Ollama API.
    private let ollamaService = PetalOllamaService() // OllamaService()

    /// The name of the AI model used for processing messages.
    private let modelName: String

    // **MARK: Initializer**

    /// Initializes the Ollama chat model with an optional model name.
    ///
    /// - **Parameter** modelName: The name of the model to use. Defaults to `"llama3.1"` `petallama3.2` is a WIP custom model.
    init(modelName: String = "llama3.1") {
        self.modelName = modelName
        print("OllamaChatModel initialized with model: \(modelName)")
    }

    // **MARK: Streaming Message Handling**

    /// Sends a user message and returns a streaming response from the AI model.
    ///
    /// - **Parameter** text: The user input message.
    /// - **Returns**: An `AsyncStream<String>` where each chunk represents part of the AI response.
    ///
    /// This function:
    /// - Constructs a message payload.
    /// - Calls `OllamaService.streamConversation` to fetch a streaming response.
    /// - Yields each chunk of the response asynchronously.
    /// - Handles errors and ensures the stream is properly closed.
    func sendMessageStream(_ text: String) -> AsyncStream<String> {
        print("OllamaChatModel: Starting stream with message: \(text.prefix(50))...")
        let messages = [OllamaChatMessage(role: "user", content: text, tool_calls: [])]

        return AsyncStream { continuation in
            Task {
                do {
                    print("OllamaChatModel: Requesting stream from Ollama service")
                    var chunkCount = 0
                    var totalLength = 0
                    var finalOutput = ""
                    
                    for try await chunk in ollamaService.streamConversation(model: modelName, messages: messages) {
                        chunkCount += 1
                        totalLength += chunk.count
                        finalOutput.append(chunk)
                        print("OllamaChatModel: Received chunk #\(chunkCount), size: \(chunk.count) characters")
                        continuation.yield(chunk)
                    }
                    
                    print("OllamaChatModel: Stream completed - \(chunkCount) chunks, \(totalLength) total characters")
                    print("OllamaChatModel: Final Output:\n\(finalOutput)")
                    continuation.finish()
                } catch {
                    print("OllamaChatModel: Streaming error: \(error.localizedDescription)")
                    continuation.finish()
                }
            }
        }
    }

    // **MARK: Single Message Handling**

    /// Sends a user message and returns a single response from the AI model.
    ///
    /// - **Parameter** text: The user input message.
    /// - **Returns**: A `String` containing the AI's response.
    ///
    /// This function:
    /// - Constructs a message payload.
    /// - Calls `OllamaService.sendSingleMessage` for processing.
    /// - **Returns** the AI's response.
    /// - **Throws** an error if the request fails.
    func sendMessage(_ text: String) async throws -> String {
        print("OllamaChatModel: Sending single message: \(text.prefix(50))...")
        let messages = [OllamaChatMessage(role: "user", content: text, tool_calls: [])]
        
        do {
            print("OllamaChatModel: Requesting response from Ollama service")
            let startTime = Date()
            let response = try await ollamaService.sendSingleMessage(model: modelName, messages: messages)
            let duration = Date().timeIntervalSince(startTime)
            
            print("OllamaChatModel: Received response in \(String(format: "%.2f", duration))s, length: \(response.count) characters")
            print("\(response)")
            return response
        } catch {
            print("OllamaChatModel: Error in sendMessage: \(error.localizedDescription)")
            throw error
        }
    }
}

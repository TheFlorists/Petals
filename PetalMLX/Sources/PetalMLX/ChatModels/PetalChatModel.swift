//
//  PetalMLXChatModel.swift
//  PetalMLX
//
//  Created by Aadi Shiv Malhotra on 3/31/25.
//

import Foundation
import MLXLMCommon
import SwiftUI
import PetalCore

/// A concrete chat model that wraps PetalMLXService and conforms to AIChatModel.
@MainActor
public class PetalMLXChatModel: AIChatModel {
    private let service: PetalMLXService
    private let model: ModelConfiguration

    /// Initialize with a model configuration.
    public init(model: ModelConfiguration) {
        self.model = model
        self.service = PetalMLXService()  // Now safe because we're on the MainActor.
    }

    /// Sends a complete message (non-streaming) using PetalMLXService.
    public func sendMessage(_ text: String) async throws -> String {
        // Create a ChatMessage for the user.
        let userMessage = ChatMessage(message: text, participant: .user)
        // Let the service generate a response.
        let response = try await service.sendSingleMessage(model: model, messages: [userMessage])
        return response
    }

    /// Returns an asynchronous stream of output chunks from PetalMLXService.
    public func sendMessageStream(_ text: String) -> AsyncThrowingStream<PetalMessageStreamChunk, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let userMessage = ChatMessage(message: text, participant: .user)
                    let stream = service.streamConversation(model: model, messages: [userMessage])
                    for try await chunk in stream {
                        continuation.yield(chunk)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }
}

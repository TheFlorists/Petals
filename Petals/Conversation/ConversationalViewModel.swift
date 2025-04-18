//
//  ConversationalViewModel.swift
//  Petals
//
//  Created by Aadi Shiv Malhotra on 2/6/25.
//

import Foundation
import GoogleGenerativeAI
import MLXLMCommon
import PetalCore
import PetalMLX
import SwiftUI

/// A view model for managing conversation interactions in the `Petals` app.
///
/// This class handles sending messages, switching between AI models (Gemini and Ollama),
/// managing system instructions, and processing streaming or single-response messages.
@MainActor
class ConversationViewModel: ObservableObject {

    // MARK: Published Properties

    @Published var updateTrigger = UUID()

    /// An array of chat messages in the conversation.
    @Published var messages = [ChatMessage]()

    /// A boolean indicating whether the system is currently processing a request.
    @Published var busy = false
    @Published var isProcessingTool = false

    /// Stores any errors encountered during message processing.
    @Published var error: Error?

    /// A computed property that returns `true` if there is an error.
    var hasError: Bool { error != nil }

    /// The currently selected AI model name.
    /// Changing this value starts a new conversation.
    @Published var selectedModel: String {
        didSet {
            startNewChat()
        }
    }

    /// A boolean indicating whether to use Ollama (local model) instead of Gemini (Google API).
    /// Changing this value switches the active model.
    @Published var useOllama: Bool = false {
        didSet {
            switchModel()
        }
    }

    private let evaluator = ToolTriggerEvaluator()

    // MARK: Private Properties

    /// The active AI chat model being used for conversation.
    private var chatModel: AIChatModel

    private let toolEvaluator = ToolTriggerEvaluator()

    // MARK: Initializer

    /// Initializes the view model with a default AI model and sets up the chat session.
    /// Gemini models are initialized in this particular format, changing this will result in errors.
    /// Ollama models are initialized inside their respective ViewModel.
    init() {
        let initialModel = "gemini-1.5-flash-latest"
        self.selectedModel = initialModel
        self.chatModel = GeminiChatModel(modelName: initialModel)
        startNewChat()
    }

    // MARK: Chat Management

    /// Starts a new chat session by clearing existing messages and adding system instructions.
    ///
    /// This function resets any ongoing conversation and provides the AI with an initial system instruction
    /// to define its behavior, particularly around tool usage.
    func startNewChat() {
        stop()
        error = nil
        messages.removeAll()

//        let systemInstruction = ChatMessage(
//            message: """
//            System: You are a helpful assistant. Only call the function 'fetchCalendarEvents' if the user's request explicitly asks for calendar events (with a date in YYYY-MM-DD format). Otherwise, respond conversationally without invoking any functions.
//            """,
//            participant: .system
//        )
//
//        messages.append(systemInstruction)
        switchModel()
    }

    /// Stops any ongoing tasks and clears any errors.
    func stop() {
        error = nil
    }

    /// Switches the active AI model between Gemini and Ollama.
    ///
    /// When switching, this function updates the chat model instance
    /// and optionally resets the conversation history.
    private func switchModel() {
        if useOllama {
            let modelConfig = ModelConfiguration.defaultModel
            chatModel = PetalMLXChatModel(model: modelConfig)
            print("🔵 Now using PetalML (local model) with \(modelConfig.name)")
        } else {
            chatModel = GeminiChatModel(modelName: selectedModel)
            print("🟢 Now using Gemini (Google API) with model: \(selectedModel)")
        }
    }

    // MARK: Message Handling

    /// Sends a user message to the AI model and appends the response to the conversation.
    ///
    /// - Parameters:
    ///   - text: The message content to be sent to the AI model.
    ///   - streaming: A boolean indicating whether to use streaming responses.
    ///
    /// This function:
    /// - Appends the user message to the conversation history.
    /// - Sends the message to the AI model.
    /// - Processes the response, either as a single reply or a streaming response.
    /// - Updates the conversation history with the AI's reply.
    ///
    /// If an error occurs, it is stored in `error`, and the pending message is removed.
    func sendMessage(_ text: String, streaming: Bool = true) async {
        error = nil
        busy = true

        let needsTool = messageRequiresTool(text)
        isProcessingTool = needsTool

        messages.append(ChatMessage(message: text, participant: .user))
        // For tool calls, start with an empty message but mark it as pending
        let pendingMessage = ChatMessage.pending(participant: .llm)
        messages.append(pendingMessage)

        do {
            if streaming {
                let stream = chatModel.sendMessageStream(text)

                // Process the stream
                for try await chunk in stream {
                    // If this is a tool call, don't update the message content until we have the final result
                    if isProcessingTool {
                        // Only update if we actually get content back (which would be the final processed result)
                        if !chunk.message.isEmpty {
                            messages[messages.count - 1].message = chunk.message
                        }

                        if let toolName = chunk.toolCallName {
                            messages[messages.count - 1].toolCallName = toolName
                        }
                    } else {
                        // For regular messages, append each chunk
                        print(chunk.message)
                        if messages[messages.count - 1].pending == true {
                            messages[messages.count - 1].pending = false
                        }
                        messages[messages.count - 1].message += chunk.message
                    }
                }

                // After stream completes, mark as not pending
                messages[messages.count - 1].pending = false
                print("cvm: msg is: ")
                print(messages[messages.count - 1].message)
            } else {
                let response = try await chatModel.sendMessage(text)
                messages[messages.count - 1].message = response
                messages[messages.count - 1].pending = false
            }
        } catch {
            self.error = error
            messages.removeLast()
        }

        busy = false
        isProcessingTool = false
    }

//    private func messageRequiresTool(_ text: String) -> Bool {
//        // Define criteria for triggering tools (dates, explicit phrases, etc.)
//        let toolPatterns = [
//            "\\d{4}-\\d{2}-\\d{2}", // Date in YYYY-MM-DD format
//            "(calendar|event|schedule|appointment)", // Explicit calendar keywords
//            "(canvas|courses|course|class|classes)",
//            "(grade|grades|performance|assignment)"
//        ]
//
//        return toolPatterns.contains { pattern in
//            text.range(of: pattern, options: .regularExpression) != nil
//        }
//    }

    // MARK: Tool Trigger Evaluation (Using `ToolTriggerEvaluator`)

    private func messageRequiresTool(_ text: String) -> Bool {
        ExemplarProvider.shared.shouldUseTools(for: text)
    }
}

/// Global notification name for streaming updates
extension Notification.Name {
    static let streamingMessageUpdate = Notification.Name("streamingMessageUpdate")
}

//
// extension ConversationViewModel {
//    // Replace your existing sendMessage method with this one
//    func sendMessage(_ text: String, streaming: Bool = true) async {
//        error = nil
//        busy = true
//
//        let needsTool = messageRequiresTool(text)
//        isProcessingTool = needsTool
//
//        // Add user message
//        await MainActor.run {
//            messages.append(ChatMessage(message: text, participant: .user))
//            let pendingMessage = ChatMessage.pending(participant: .llm)
//            messages.append(pendingMessage)
//        }
//
//        // Store index for response message
//        let responseIndex = messages.count - 1
//
//        do {
//            if streaming {
//                let stream = chatModel.sendMessageStream(text)
//
//                // Process the stream
//                for try await chunk in stream {
//                    print("🧩 Got chunk: '\(chunk.message)'")
//                    await MainActor.run {
//                        if isProcessingTool {
//                            // Tool processing - handle as before
//                            if !chunk.message.isEmpty {
//                                messages[responseIndex].message = chunk.message
//                            }
//
//                            if let toolName = chunk.toolCallName {
//                                messages[responseIndex].toolCallName = toolName
//                            }
//                        } else {
//                            // For regular streaming, we need to force SwiftUI updates
//
//                            // 1. First append the chunk
//                            messages[responseIndex].message += chunk.message
//
//                            // 2. Force a UI update by creating a new messages array
//                            let messagesCopy = self.messages
//                            self.messages = messagesCopy
//
//                            DispatchQueue.main.async {
//                                self.objectWillChange.send()
//                            }
//
//                            self.updateTrigger = UUID()
//
//                            // 3. Post a notification for views to react
//                            NotificationCenter.default.post(
//                                name: .streamingMessageUpdate,
//                                object: nil,
//                                userInfo: [
//                                    "index": responseIndex,
//                                    "message": messages[responseIndex].message
//                                ]
//                            )
//
//                        }
//                    }
//
//                    // Small delay to ensure UI can keep up
//                    // Only needed if chunks are coming very rapidly
//                    if !isProcessingTool {
//                        try? await Task.sleep(nanoseconds: 10_000_000) // 10ms delay
//                    }
//                }
//
//                // After stream completes, mark as not pending
//                await MainActor.run {
//                    messages[responseIndex].pending = false
//
//                    // Force final update
//                    let messagesCopy = self.messages
//                    self.messages = messagesCopy
//                }
//            } else {
//                // Non-streaming implementation
//                let response = try await chatModel.sendMessage(text)
//
//                await MainActor.run {
//                    messages[responseIndex].message = response
//                    messages[responseIndex].pending = false
//                }
//            }
//        } catch {
//            await MainActor.run {
//                self.error = error
//                messages.removeLast()
//            }
//        }
//
//        await MainActor.run {
//            busy = false
//            isProcessingTool = false
//        }
//    }
// }

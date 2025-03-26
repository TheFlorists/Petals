//
//  ConversationalViewModel.swift
//  Petals
//
//  Created by Aadi Shiv Malhotra on 2/6/25.
//

import Foundation
import GoogleGenerativeAI
import SwiftUI
import PetalMLX

/// A view model for managing conversation interactions in the `Petals` app.
///
/// This class handles sending messages, switching between AI models (Gemini and Ollama),
/// managing system instructions, and processing streaming or single-response messages.
@MainActor
class ConversationViewModel: ObservableObject {

    // MARK: Published Properties

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
            chatModel = PetalMLXService(model: ModelConfiguration.llama_3_2_3b_4bit)
            print("🔵 Now using Ollama (local model)")
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
        messages.append(ChatMessage.pending(participant: .system))

        do {
            if streaming {
                let stream = chatModel.sendMessageStream(text)
                for await chunk in stream {
                    messages[messages.count - 1].message += chunk.message
                    if let toolName = chunk.toolCallName {
                        messages[messages.count - 1].toolCallName = toolName
                    }
                    messages[messages.count - 1].pending = false
                }
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
        let toolExemplars: [String: [String]] = [
            "petalCalendarFetchEventsTool": [
                "Fetch calendar events for me",
                "Show calendar events",
                "List my events",
                "Get events from my calendar",
                "Retrieve calendar events"
            ],
            "petalCalendarCreateEventTool": [
                "Create a calendar event on [date]",
                "Schedule a new calendar event",
                "Add a calendar event to my schedule",
                "Book an event on my calendar",
                "Set up a calendar event"
            ],
            "petalFetchRemindersTool": [
                "Show me my reminders",
                "List my tasks for today",
                "Fetch completed reminders",
                "Get all my pending reminders",
                "Find reminders containing 'doctor'"
            ],
            "petalFetchCanvasAssignmentsTool": [
                "Fetch assignments for my course",
                "Show my Canvas assignments",
                "Get assignments for my class",
                "Retrieve course assignments from Canvas",
                "List assignments for my course"
            ],
            "petalFetchCanvasGradesTool": [
                "Show me my grades",
                "Get my Canvas grades",
                "Fetch my course grades",
                "Display grades for my class",
                "Retrieve my grades from Canvas"
            ]
        ]

        for (_, exemplars) in toolExemplars {
            if let prototype = toolEvaluator.prototype(for: exemplars) {
                if toolEvaluator.shouldTriggerTool(for: text, exemplarPrototype: prototype) {
                    return true
                }
            }
        }
        return false
    }
}

//
//  ConcreteCoreModelContainer.swift
//  PetalMLX
//
//  Created by Aadi Shiv Malhotra on 3/26/25.
//

import Foundation
import MLX
import MLXLLM
import MLXLMCommon
import MLXRandom
import SwiftUI

/// A class that serves as a concrete implementation of a core model container.
/// It conforms to the CoreModelContainerProtocol, provides thread-safe model access,
/// and is observable for object changes.
public final class ConcreteCoreModelContainer: CoreModelContainerProtocol, @unchecked Sendable, ObservableObject {

    /// A lock used to ensure thread-safe access to the container's resources.
    private var lock = NSLock()

    /// A string property to hold progress updates, publicly readable but only privately settable.
    public private(set) var onProgress: String = ""

    /// Configuration for the model used in the container.
    private let modelConfiguration: ModelConfiguration

    /// Parameters for generating model outputs.
    private let generateParameters: GenerateParameters

    /// Initializes the model container with specified configurations and parameters.
    /// - Parameters:
    ///   - modelConfiguration: The configuration settings for the model.
    ///   - generateParamaters: The parameters for generating processes.
    init(
        modelConfiguration: ModelConfiguration,
        generateParameters: GenerateParameters
    ) {
        self.modelConfiguration = modelConfiguration
        self.generateParameters = generateParameters
    }

    /// Loads and returns a model container asynchronously.
    /// It sets a memory limit for the GPU buffer cache and loads the container using the LLMModelFactory.
    /// - Throws: An error if the loading process fails.
    /// - Returns: A `ModelContainer` object containing the loaded model.
    func load() async throws -> ModelContainer {
        // Set a memory limit for the GPU buffer cache to manage resource usage.
        MLX.GPU.set(memoryLimit: 20 * 1024 * 1024)

        // Load the model container using the provided configuration, updating the progress as needed.
        let modelContainer = try await LLMModelFactory.shared.loadContainer(
            configuration: modelConfiguration
        ) { progress in
            Task { @MainActor in
                print("Download \(self.modelConfiguration.name): \(Int(progress.fractionCompleted * 100))%")
            }
        }

        // Retrieve the number of parameters from the model context and print the loading status.
        let totalParameterCount: Int = await modelContainer.perform { context in
            let parameters = context.model.parameters() // Access non-sendable type INSIDE actor

            // Calculate the sum of sizes INSIDE the actor
            let count = parameters.reduce(0) { result, dictElement in
                // dictElement is likely (key: String, value: MLXArray)
                result + dictElement.count // .size is an Int, which is Sendable
            }
            return count // Return the Sendable Int count
        }

        // Format based on size
        let formattedParamCount: String
        if totalParameterCount >= 1_000_000_000 {
            let billions = Double(totalParameterCount) / 1_000_000_000.0
            formattedParamCount = String(format: "%.2fB", billions)
        } else {
            let millions = Double(totalParameterCount) / 1_000_000.0
            formattedParamCount = String(format: "%.2fM", millions)
        }

        print("Loaded \(modelConfiguration.id). Weights: \(formattedParamCount)")

        return modelContainer
    }

    // *old*
//    public func generate(
//        messages: [[String: String]],
//        tools: [Tool]?,
//        onProgress: @escaping OnProgress
//    ) async throws -> GenerateResult {
//        // Load the model container, catching any errors during the process.
//        let modelContainer = try await load()
//
//        // Seed the random number generator for consistent results.
//        MLXRandom.seed(UInt64(Date.timeIntervalBetween1970AndReferenceDate * 100))
//
//        // Perform the generation process using the model container's context.
//        return try await modelContainer.perform { context in
//            // Prepare the input data for the model processor.
//            let input = try await context.processor.prepare(
//                input:
//                .init(messages: messages, tools: tools)
//            )
//
//            // Generate output using the MLXLMCommon library and provide progress updates.
//            return try MLXLMCommon.generate(
//                input: input,
//                parameters: generateParameters,
//                context: context
//            ) { tokens in
//                if tokens.count % 1 == 0 {
//                    self.lock.lock()
//                    defer { self.lock.unlock() }
//
    // THIS IS THE KEY LINE:
    // You are decoding ALL tokens generated up to this point on *every callback*.
//                    let text = context.tokenizer.decode(tokens: tokens)
//                    Task { @MainActor in
//                        onProgress(text)
//                    }
//                }
//                return .more
//            }
//        }
//    }

    /// Generates a result from the model based on given messages and tools, and provides progress updates.
    /// - Parameters:
    ///   - messages: A collection of message dictionaries to be processed.
    ///   - tools: An optional array of tools used in the generation process.
    ///   - onProgress: A closure that is called with progress updates.
    /// - Throws: An error if the generation process fails.
    /// - Returns: A `GenerateResult` object containing the generated output.
    public func generate(
        messages: [[String: String]],
        tools: [Tool]?,
        onProgress: @escaping OnProgress
    ) async throws -> GenerateResult {
        let modelContainer = try await load()
        MLXRandom.seed(UInt64(Date.timeIntervalBetween1970AndReferenceDate * 100))

        return try await modelContainer.perform { context in
            let input = try await context.processor.prepare(
                input: .init(messages: messages, tools: tools)
            )

            // Keep track of previously decoded text or token count
            var previousTokenCount = 0 // Or var previouslyDecodedText = ""

            return try MLXLMCommon.generate(
                input: input,
                parameters: generateParameters,
                context: context
            ) { tokens in
                self.lock
                    .lock() // Still need lock if accessing shared state, though maybe not needed just for calculation
                defer { self.lock.unlock() }

                // --- CHANGE START ---
                // Get only the *new* tokens generated in this step
                let newTokens = tokens.suffix(from: previousTokenCount)

                if !newTokens.isEmpty {
                    // Decode only the new tokens
                    let newText = context.tokenizer.decode(tokens: Array(newTokens))

                    // Update the count for the next iteration *before* the async task
                    previousTokenCount = tokens.count

                    Task { @MainActor in
                        // Send only the *newly* decoded text chunk
                        onProgress(newText)
                    }
                }
                // --- CHANGE END ---

                return .more
            }
        }
    }
}

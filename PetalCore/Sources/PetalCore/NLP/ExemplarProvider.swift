//
//  ExemplarProvider.swift
//  PetalCore
//
//  Created by Aadi Shiv Malhotra on 4/2/25.
//

import Foundation

/// Provides and caches tool exemplars and their prototype vectors
public class ExemplarProvider {
    /// Singleton instance
    @MainActor public static let shared = ExemplarProvider()
    
    private let evaluator = ToolTriggerEvaluator()
    
    /// Dictionary mapping tool IDs to their exemplar phrases
    public let toolExemplars: [String: [String]] = [
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
        "petalGenericCanvasCoursesTool": [
            "Show me my Canvas courses",
            "List my classes on Canvas",
            "Display my Canvas courses",
            "What courses am I enrolled in?",
            "Fetch my Canvas classes"
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
        ],
        "petalNotesTool": [
            "Find my notes about [topic]",
            "Create a new note with [content]",
            "Show all my notes",
            "Make a note about [topic]",
            "Search my notes for [query]",
            "Create a new note titled Meeting with Sam with content # Discussion Points -Project timeline -Budget concerns -Next steps"
        ]
    ]
    
    /// Cache for prototype vectors to avoid recomputing
    private var prototypeCache: [String: [Double]] = [:]
    
    private init() {
        // Private initializer to enforce singleton pattern
        // Pre-compute all prototypes during initialization
        cacheAllPrototypes()
    }
    
    /// Pre-computes and caches all prototype vectors
    private func cacheAllPrototypes() {
        for (toolID, exemplars) in toolExemplars {
            if let prototype = evaluator.prototype(for: exemplars) {
                prototypeCache[toolID] = prototype
            }
        }
    }
    
    /// Returns the prototype vector for a specific tool ID
    /// - Parameter toolID: The tool identifier
    /// - Returns: The cached prototype vector or nil if not available
    public func getPrototype(for toolID: String) -> [Double]? {
        // Return from cache if available
        if let cachedPrototype = prototypeCache[toolID] {
            return cachedPrototype
        }
        
        // Compute and cache if not already cached
        if let exemplars = toolExemplars[toolID], 
           let prototype = evaluator.prototype(for: exemplars) {
            prototypeCache[toolID] = prototype
            return prototype
        }
        
        return nil
    }
    
    /// Determines if a message should trigger any tool
    /// - Parameter message: The user message to evaluate
    /// - Returns: True if any tool should be triggered
    public func shouldUseTools(for message: String) -> Bool {
        for (toolID, _) in toolExemplars {
            if let prototype = getPrototype(for: toolID),
               evaluator.shouldTriggerTool(for: message, exemplarPrototype: prototype) {
                return true
            }
        }
        return false
    }
    
    /// Determines if a message should trigger a specific tool
    /// - Parameters:
    ///   - message: The user message to evaluate
    ///   - toolID: The specific tool ID to check
    /// - Returns: True if the specified tool should be triggered
    public func shouldUseTool(for message: String, toolID: String) -> Bool {
        guard let prototype = getPrototype(for: toolID) else {
            return false
        }
        
        return evaluator.shouldTriggerTool(for: message, exemplarPrototype: prototype)
    }
} 

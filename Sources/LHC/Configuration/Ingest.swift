//
//  Validate.swift
//  
//
//  Created by John Biggs on 18.11.23.
//

import Foundation

extension Configuration {
    public struct IngestedConfig: Codable {
        typealias PropertiesTree = [Property: [Set<Condition>: Element]]
        typealias ConditionWeights = [Condition: Int]

        /// The set of properties mapping to conditions, matching to the corresponding assignment for the element.
        /// The set can be empty, in which case there is no condition.
        /// `$(inherited)` references have been traversed and replaced by the `ingest` function so that it can check
        /// for cycles.
        let properties: PropertiesTree

        /// Each condition may appear a number of times in the document. `weights` maps each condition to the number of
        /// times that condition appears.
        let weights: ConditionWeights

        /// These properties are not depended on by any other property.
        let roots: [Property]
    }

    /// Unwind the inherited values for a given property.
    /// - Parameter element: Should contain at least one reference to `$(inherited)`
    /// - Parameter inheritedValues: all of the parent values of `value`.
    func unwindInheritedValues(for element: Element, inheritedValues: [Value]) throws -> Element {
        var value = element.value
        var inheritedValues = inheritedValues
        while value.references.contains(.inherited) {
            guard !element.conditions.isEmpty else {
                // If we're at the top-level, include the `$(inherited)` reference. A top-level `$(inherited)` value
                // means the user is expected to define a value on the command line.
                return element
            }

            guard !inheritedValues.isEmpty else {
                throw Error.noInheritedValue(ofElement: element)
            }

            let inherited = inheritedValues.removeFirst()
            value = Value(interpolatedItems: value.interpolatedItems.reduce(into: [], {
                // If we encounter `$(inherited)` in a variable's references, then replace it with all of the
                // interpolated items of the parent variable. Otherwise just append it as normal.
                // Note that we append the parent's references without evaluating them - this is important for the
                // cycle-checking step.
                if $1 == .right(.inherited) {
                    $0.append(contentsOf: inherited.interpolatedItems)
                } else {
                    $0.append($1)
                }
            }))
        }

        return Element(property: element.property, conditions: element.conditions, value: value)
    }

    /// Ingest a parsed graph and form inital state necessary for evaluating the config, while linting the file.
    public func ingest() throws -> IngestedConfig {
        typealias Tree = IngestedConfig.PropertiesTree
        typealias Weights = IngestedConfig.ConditionWeights
        typealias Graph = [Property: Set<Property>]
        // First, sort the list by how many conditions each entry has. This helps us evaluate inheritance.
        let configItems = configItems.sorted {
            $0.conditions.count < $1.conditions.count
        }

        var tree: Tree = [:]
        var weights: Weights = [:]

        // For each conditional setting for each property in the configuration file, the set of the properties used in the conditions.
        var conditionProperties: [Property: [Set<Property>]] = [:]

        // For each property setting, the total set of values depended on by the property - including variables referenced.
        var dependencyGraph: Graph = [:]

        // Build the graph of property references as we traverse all of the settings.
        // Do quick sanity checks as we go to make sure the graph is more likely to be consistent.
        for var configItem in configItems {
            let property = configItem.property

            // Unwind any inherited values now so the dependency graph is accurate for the next steps.
            if configItem.value.references.contains(.inherited) {
                let inheritedValues = tree[property]?.filter {
                    $0.key.isSubset(of: configItem.conditions)
                }.values.sorted {
                    $0.conditions.count > $1.conditions.count
                }.map(\.value) ?? []

                configItem = try unwindInheritedValues(for: configItem, inheritedValues: inheritedValues)
            }

            let references = configItem.value.references
            guard !references.contains(property) else {
                throw Error.cycle([property])
            }

            let conditionPropertySet = Set(configItem.conditions.map(\.property))
            guard !conditionPropertySet.contains(property) else {
                throw Error.cycle([property])
            }

            if conditionProperties[property] == nil {
                conditionProperties[property] = []
            }

            if dependencyGraph[property] == nil {
                dependencyGraph[property] = []
            }

            if tree[property] == nil {
                tree[property] = [:]
            }

            if let conflict = conditionProperties[property]?.first(where: { !$0.isSubset(of: conditionPropertySet) }) {
                throw Error.conditionalAssignment(
                    ofProperty: property,
                    conditions: Array(configItem.conditions),
                    couldConflictWith: Array(conflict))
            }

            for condition in configItem.conditions {
                if weights[condition] == nil {
                    weights[condition] = 1
                } else {
                    weights[condition]! += 1
                }
            }

            conditionProperties[property]?
                .insert(conditionPropertySet, at: 0)
            dependencyGraph[property]?
                .formUnion(conditionPropertySet.union(references))
            tree[property]?[configItem.conditions] = configItem
        }

        var seen: Set<Property> = []
        if let cycle = Self.findCycle(dependencyGraph, seen: &seen) {
            throw Error.cycle(.init(cycle))
        }

        let roots = dependencyGraph.values.reduce(into: Set(tree.keys)) { $0.subtract($1) }
        return .init(
            properties: tree,
            weights: weights,
            roots: Array(roots)
        )
    }

    /// Traverse a graph and make sure no properties depend on one another.
    static func findCycle(
        _ dependencyGraph: [Property: Set<Property>],
        seen: inout Set<Property>,
        stack: Set<Property> = []
    ) -> Set<Property>? {
        for (property, references) in dependencyGraph {
            guard !seen.contains(property) else { continue }
            guard !stack.contains(property) else { return stack }
            var stack = stack
            stack.insert(property)

            if let stack = findCycle(
                dependencyGraph.filter { references.contains($0.key) },
                seen: &seen,
                stack: stack
            ) { return stack }

            seen.insert(property)
        }

        return nil
    }
}

extension Configuration.IngestedConfig.ConditionWeights {
    func totalWeight(of element: Configuration.Element) -> Int {
        element.conditions.map { self[$0] ?? 0 }.reduce(0, +)
    }
}

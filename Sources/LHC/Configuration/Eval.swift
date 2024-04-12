//
//  Eval.swift
//  
//
//  Created by John Biggs on 17.11.23.
//

import Foundation

extension Configuration.IngestedConfig {
    public typealias Defines = Configuration.Defines

    public typealias Property = Configuration.Property
    public typealias Condition = Configuration.Condition
    public typealias Value = Configuration.Value

    @discardableResult
    func eval(
        property: Property,
        graph: inout PropertiesTree,
        conditions: inout Set<Condition>,
        weights: ConditionWeights,
        defines: inout Defines
    ) throws -> String? {
        guard let elements = graph[property]?.values, !elements.isEmpty else {
            defines[property] = nil
            conditions.insert(.falsey(property))
            return nil
        }

        // Sorting by the biggest number of conditions first means that, when we iterate through the conditions, we
        // know that we should go ahead with assignment if we match all of them.
        let assignments = elements.sorted {
            // First, sort descending by number of conditions.
            let (lhsCount, rhsCount) = ($0.conditions.count, $1.conditions.count)
            guard lhsCount == rhsCount else {
                return lhsCount > rhsCount
            }

            // Then sort by condition weight.
            let (lhsWeight, rhsWeight) = (weights.totalWeight(of: $0), weights.totalWeight(of: $1))
            guard lhsWeight == rhsWeight else {
                return lhsWeight > rhsWeight
            }

            // Hey, as long as it's deterministic, right?
            return $0.conditions.hashValue < $1.conditions.hashValue
        }

        var value: Value?
        // Iterate over all of the conditional assignments for a property. Assignments looks like:
        // foo[bar][baz=Debug] = Fizz
        // foo[bar] = Buzz
        // foo = FizzBuzz
        assign: for assignment in assignments {
            // The assignments are already sorted, but we need to traverse the clauses deterministically as well,
            // because we break out of the loop as soon as we encounter a condition that is false. Since it only
            // matters that we traverse deterministically and not lexicographically, we will sort first by hit count
            // as a heuristic to avoid too many loops/recursive calls.
            let assignmentConditions = assignment.conditions.sorted {
                let (lhsWeight, rhsWeight) = (weights[$0] ?? 0, weights[$1] ?? 0)
                guard lhsWeight == rhsWeight else {
                    return lhsWeight > rhsWeight
                }

                let (lhsName, rhsName) = ($0.property.rawValue, $1.property.rawValue)
                guard lhsName == rhsName else {
                    return lhsName < rhsName
                }

                return $0.hashValue < $1.hashValue
            }

            // For each condition, make sure it matches either a value we've evaluated previously, or evaluate the
            // value in a recursive call and make sure it matches. If it doesn't, move on to the next possible
            // conditional assignment.
            for condition in assignmentConditions {
                // If we haven't evaluated the value first, recurse.
                if !defines.includes(condition.property) {
                    try eval(
                        property: condition.property,
                        graph: &graph,
                        conditions: &conditions,
                        weights: weights,
                        defines: &defines
                    )
                }

                guard conditions.contains(condition) else {
                    continue assign
                }
            }

            // We've traversed all of the conditions for this element and they turn out to be true. Finish the
            // assignment loop with the value that we've determined for the property.
            value = assignment.value
            break
        }

        // Now we get to evaluate it - make a recursive call for each referenced value.
        var evaluatedValue: String?
        if let value {
            evaluatedValue = ""
            for item in value.interpolatedItems {
                switch item {
                case .left(let literal):
                    evaluatedValue! += literal
                case .right(let reference):
                    // If an `$(inherited)` value has been left behind, then that means that we're at the top level and
                    // no define has been provided for `property`, in which case we shouldn't continue, because the
                    // config author expected the user to define a default value for it.
                    guard reference != .inherited else {
                        throw Configuration.Error.noDefaultValueProvided(forProperty: property)
                    }

                    if let definedValue = defines[reference] {
                        evaluatedValue! += definedValue ?? ""
                    } else {
                        evaluatedValue! += try eval(
                            property: reference,
                            graph: &graph,
                            conditions: &conditions,
                            weights: weights,
                            defines: &defines
                        ) ?? ""
                    }
                }
            }
        }

        defines[property] = evaluatedValue
        conditions.formUnion(Condition.set(property, value: evaluatedValue))
        return evaluatedValue
    }
    
    /// Evaluate an ingested configuration given a set of initial values.
    public func eval(initialValues: Defines) throws -> Defines {
        var defines: Defines = initialValues
        var graph = properties

        var conditions: Set<Condition> = defines.reduce(into: []) { partialResult, keypair in
            let (property, value) = keypair
            partialResult.formUnion(Condition.set(property, value: value))
        }

        for root in roots {
            _ = try eval(
                property: root,
                graph: &graph,
                conditions: &conditions,
                weights: weights,
                defines: &defines
            )
        }

        return defines
    }
}

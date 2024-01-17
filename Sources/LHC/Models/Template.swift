//
//  Stencil.swift
//
//  Created by John Biggs on 04.01.24.
//

import Foundation
import Yams // For decoding a yaml header, if it exists
import System
import Stencil
import SwiftGit2
import LHCInternal

/// Load a template from the repository.
///
/// If a template ends with an extension like `.base.md`, `.base.html`, etc., then this loader will first look in the
/// project's embedded resources for the given base template file before trying to load it from the repository.
public class TemplateLoader: Loader, CustomStringConvertible {
    public let urls: [URL]

    public init(urls: [URL]) {
        self.urls = urls
    }

    public var description: String {
        "TemplateLoader(\(urls.map { $0.absoluteString }))"
    }

    public func loadTemplate(name: String, environment: Environment) throws -> Template {
        let value = try loadTemplates(nameOrRoot: name, environment: environment).first!
        return value.value!.0
    }

    private func recursivelyLoadContents(_ url: URL, subpath: String?, into contents: inout [String: String?]) throws {
        let fullURL = subpath == nil ? url : url.appending(path: subpath!)
        let directoryContents = try Internal.fileManager.contentsOfDirectory(
            at: fullURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: .producesRelativePathURLs
        )

        for subsubURL in directoryContents {
            let subsubPath = subsubURL.path()
            if (try? subsubURL.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
                try recursivelyLoadContents(url, subpath: subsubPath, into: &contents)
            } else if subsubURL.deletingPathExtension().pathExtension == "template",
                      let templateContents = Internal.fileManager.contents(atPath: subsubPath) {
                let string = String(data: templateContents, encoding: .utf8)
                contents[subsubPath] = string
            } else {
                contents[subsubPath] = nil
            }
        }
    }

    public func loadTemplates(
        nameOrRoot: String,
        environment: Environment
    ) throws -> [String: (Template, headers: [String: Any]?)?] {
        let fileURL = URL(filePath: nameOrRoot)
        let withoutExtension = fileURL.deletingPathExtension().path()

        var url: URL?
        if withoutExtension.hasSuffix(".base") {
            // This implementation is a bit weird because we can't rely on Bundle.module (it only gets generated if we're
            // built with SPM) and we have to use the real, non-stubbed FileManager so we can get the resource's contents
            // without conflicting with any test runs.
            let bundle = Bundle(for: MyBundle.self)
            let paths = bundle.paths(forResourcesOfType: nil, inDirectory: nil)

            for path in paths {
                guard let resourceBundle = Bundle(path: path),
                      let resourcePath = resourceBundle.path(
                          forResource: withoutExtension,
                          ofType: fileURL.pathExtension
                      ) else {
                    continue
                }

                url = URL(filePath: resourcePath)
                break
            }
        }

        var isDirectory: Bool? = false
        if url == nil {
            for templateDirectoryURL in self.urls {
                let templateURL = templateDirectoryURL.appending(path: nameOrRoot)
                if Internal.fileManager.fileExists(atPath: templateURL.path(), isDirectory: &isDirectory) {
                    url = templateURL
                    break
                }
            }
        }

        guard let url else {
            throw TemplateDoesNotExist(templateNames: [nameOrRoot], loader: self)
        }

        var templateContents: [String: String?] = [:]
        if isDirectory == true {
            try recursivelyLoadContents(url, subpath: nil, into: &templateContents)
        } else {
            guard let data = Internal.fileManager.contents(atPath: url.path()),
                  let contents = String(data: data, encoding: .utf8) else {
                throw TemplateDoesNotExist(templateNames: [nameOrRoot], loader: self)
            }

            templateContents[nameOrRoot] = contents
        }

        return templateContents.reduce(into: [:]) {
            let (key, contents) = $1
            guard let contents else {
                // Still tell the caller where non-template files are, so it knows to copy them over.
                $0[key] = nil
                return
            }

            let delimiter = "---\n"
            let body: String
            let headers: CodingDictionary?

            // Find the boundaries of the YAML header, if one exists
            if contents.starts(with: delimiter),
               let match = contents[delimiter.endIndex...].range(of: delimiter) {
                let decoder = YAMLDecoder()
                body = String(contents[match.upperBound...])
                let headersString = contents[match]
                headers = try? decoder.decode(CodingDictionary.self, from: headersString.data(using: .utf8)!)
            } else {
                body = contents
                headers = nil
            }

            let template = environment.templateClass.init(
                templateString: body,
                environment: environment,
                name: String(key.split(separator: "/").last!)
            )

            $0[key] = (template, headers?.rawValue)
        }
    }
}

public class TemplateExtension: Stencil.Extension {
    func `get`(_ value: Any?, _ arguments: [Any]) throws -> Any? {
        guard arguments.count == 1, let key = arguments.first else {
            throw TemplateSyntaxError("""
                'lookup' requires one argument, which must be a key in a dictionary.
                """
            )
        }

        guard let value else { return nil }

        switch (key, value) {
        case let (key, value) as (String, [String: Any]):
            return value[key]
        case let (key, value) as (String, CustomStencilSubscriptable):
            return value[key]
        case let (key, value) as (String, [CustomStencilSubscriptable]):
            for item in value where item[key] != nil {
                return item // Yes, the item, not the value itself.
            }
            return nil
        default:
            throw TemplateSyntaxError("""
                Don't know how to index into a \(type(of: value)) with a \(type(of: key)).
                """
            )
        }
    }

    func contains(_ value: Any?, _ arguments: [Any]) throws -> Any? {
        guard arguments.count == 1, let key = arguments.first else {
            throw TemplateSyntaxError("""
                'contains' requires one argument, which must be either a key in a dictionary or \
                an element in an array.
                """
            )
        }

        guard let value else { return false }

        switch (key, value) {
        case let (key, value) as (String, [String]):
            return value.contains(key)
        case let (key, value) as (String, [String: Any]):
            return value[key] != nil
        case let (key, value) as (String, CustomStencilSubscriptable):
            return value[key] != nil
        case let (key, value) as (String, [CustomStencilSubscriptable]):
            return value.contains { $0[key] != nil }
        default:
            throw TemplateSyntaxError("""
                Don't know how to index into a \(type(of: value)) with a \(type(of: key)).
                """
            )
        }
    }

    func attrs(_ value: Any?, _ arguments: [Any]) throws -> Any? {
        guard let attrsRef = options?.attrsRef else { return nil }

        let note: Note?
        switch value {
        case let tag as TagReferenceish:
            guard let oid = tag.tagOid else { return nil }
            note = try? repository.note(for: oid, notesRef: attrsRef)
        case let tag as Tagish:
            note = try? repository.note(for: tag.oid, notesRef: attrsRef)
        case let commit as Commitish:
            note = try? repository.note(for: commit.oid, notesRef: attrsRef)
        default:
            return nil
        }

        guard let note else { return nil }
        guard arguments.count > 0 else { return note }

        guard arguments.count == 1, let key = arguments.first as? String else {
            throw TemplateSyntaxError("""
            'attrs' allows one argument, which must be a string.
            """)
        }

        let trailers = try [Commit.Trailer](message: note.message)
        guard let value = trailers.first(where: { $0.key == key }) else {
            return nil
        }

        return value
    }

    func olderThan(_ value: Any?, _ arguments: [Any]) throws -> Any? {
        guard arguments.count == 1,
              let string = arguments.first as? String,
              let timeInterval = TimeInterval(string: string) else {
            throw TemplateSyntaxError("""
                'olderThan' requires one argument, which must be a string representing a time interval in a string \
                format such as "9d", "9d3h", "9d3m", "7w2d30", etc.
                """
            )
        }

        let date: Date
        switch value {
        case let tag as Tagish:
            date = tag.tagger.time
        case let commit as Commitish:
            date = commit.date
        case let note as Note:
            date = note.committer.time
        case nil:
            return false
        default:
            return nil
        }

        return (-date.timeIntervalSinceNow) > timeInterval
    }

    func revParse(_ value: Any?, _ arguments: [Any]) throws -> Any? {
        guard arguments.count == 0 else {
            throw TemplateSyntaxError("""
                'rev_parse' does not take any arguments.
                """)
        }

        guard let value = value as? String else {
            throw TemplateSyntaxError("""
                'rev_parse' requires a string value.
                """)
        }

        return try? repository.object(parsing: value)
    }

    func objectType(_ value: Any?, _ arguments: [Any]) throws -> Any? {
        guard arguments.count == 0 else {
            throw TemplateSyntaxError("""
                'object_type' does not take any arguments.
                """)
        }

        let oid: ObjectID
        switch value {
        case let value as String:
            guard let value = ObjectID(string: value) else {
                throw TemplateSyntaxError("'\(value)' is not a valid object ID.")
            }

            oid = value
        case let value as ObjectID:
            oid = value
        default:
            throw TemplateSyntaxError("""
                'object_type' requires a value, which must be either a string or an object ID.
                """)
        }

        guard let object = try? repository.object(oid) else {
            return nil
        }

        return String(describing: type(of: object).type)
    }

    func commits(_ value: Any?, _ arguments: [Any]) throws -> Any? {
        guard arguments.count == 0 else {
            throw TemplateSyntaxError("""
                'commits' does not take any arguments.
                """
            )
        }

        guard let value = value as? (any ObjectType) else {
            throw TemplateSyntaxError("""
                'commits' requires a value, which must be a Git object type.
                """)
        }

        switch value {
        case let value as Tagish:
            return try? repository.commits(from: value.target.oid, since: nil)
        case let value as Commitish:
            return try? repository.commits(from: value.oid, since: nil)
        default:
            throw TemplateSyntaxError("""
                'commits' doesn't know how to get commits from a '\(type(of: value))'.
                """)
        }
    }

    func alias(_ value: Any?, _ arguments: [Any]) throws -> Any? {
        guard let contact = value as? String,
              case var components = contact.split(separator: " <"),
              components.count == 2,
              components.last?.last == ">" else {
            throw TemplateSyntaxError("""
                'alias' requires one value, which must be a name and email in the format 'Jane Doe <jdoe@example.org>'.
                """)
        }

        let name = components[0].trimmingCharacters(in: .whitespaces)
        components[1].removeLast() // Remove trailing '>'
        let email = String(components[1])

        if let argument = arguments.first {
            guard arguments.count == 0, let platform = argument as? String else {
                throw TemplateSyntaxError("""
                    'alias' allows one argument, which must be a platform like 'gitlab' or 'slack'.
                    """)
            }

            return try? aliasMap?.alias(name: name, email: email, platform: platform)
        }

        return try? aliasMap?.resolve(name: name, email: email)
    }

    func random(_ value: Any?, arguments: [Any]) throws -> Any? {
        guard arguments.count == 0 else {
            throw TemplateSyntaxError("""
                'random' does not take any arguments.
                """
            )
        }

        guard let value = value as? AnyCollection<Any> else {
            throw TemplateSyntaxError("""
                'random' takes one value, which must be a collection.
                """
            )
        }

        return value.randomElement()
    }

    public let repository: Repositoryish
    public let options: Configuration.Options?

    private lazy var aliasMap: AliasMap? = try? repository.aliasMap()

    public init(_ repository: Repositoryish, options: Configuration.Options?) {
        self.repository = repository
        self.options = options

        super.init()

        registerFilter("get", filter: `get`)
        registerFilter("contains", filter: contains)
        registerFilter("attrs", filter: attrs)
        registerFilter("older_than", filter: olderThan)
        registerFilter("rev_parse", filter: revParse)
        registerFilter("object_type", filter: objectType)
        registerFilter("commits", filter: commits)
        registerFilter("alias", filter: alias)
        registerFilter("random", filter: random)
    }
}

extension Stencil.Environment {
    static let yamlHeadersKey = "headers"

    /// This is so we can get at the repository and options that we were initialized with.
    var templateExtension: TemplateExtension {
        extensions.first(where: { $0 is TemplateExtension }) as! TemplateExtension
    }

    var repository: Repositoryish {
        templateExtension.repository
    }

    var options: Configuration.Options? {
        templateExtension.options
    }

    public init(
        repository: Repositoryish,
        options: Configuration.Options?,
        urls: [URL]
    ) {
        self = Stencil.Environment(
           loader: TemplateLoader(urls: urls),
           extensions: [
               TemplateExtension(
                   repository,
                   options: options
               )
           ]
       )
    }

    /// - Note: assumes that the environment is using a `TemplateLoader`.
    public func renderTemplates(
        nameOrRoot: String,
        additionalContext: [String: Any]
    ) throws -> [String: String?] {
        let loader = self.loader as! TemplateLoader
        let templates = try loader.loadTemplates(nameOrRoot: nameOrRoot, environment: self)

        var result: [String: String?] = [:]
        for (subpath, contents) in templates {
            guard let (template, headers) = contents else {
                result[subpath] = nil
                continue
            }

            var context = additionalContext
            if let headers, context[Self.yamlHeadersKey] == nil {
                context[Self.yamlHeadersKey] = headers
            }

            result[subpath] = try template.render(context)
        }

        return result
    }
}

public enum TemplateError: String, Error, CustomStringConvertible {
    case notFound = "Template not found."

    public var description: String {
        rawValue
    }
}

public protocol CustomStencilSubscriptable {
    subscript(_ key: String) -> String? { get }
}

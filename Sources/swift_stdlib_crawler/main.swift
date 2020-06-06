// swift_stdlib_crawler --- crawler for Swift stdlib and Foundation.
// Copyright (C) 2018-2020  taku0 https://github.com/taku0

// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.

// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <https://www.gnu.org/licenses/>.

import Foundation
import Dispatch

import SwiftSoup

let baseURL = URL(string: "https://developer.apple.com")!

let classLikeKinds: Set = ["cl", "struct", "intf", "enum"]

let typeKinds: Set = [
  "cl",
  "struct",
  "intf",
  "enum",
  "tdef",
  "cltdef",
  "structtdef",
  "intftdef",
  "enumtdef",
]

let methodKinds: Set = [
  "instm",
  "clm",
  "structm",
  "structcm",
  "intfm",
  "intfcm",
  "enumm",
  "enumcm",
]

let propertyKinds: Set = [
  "instp",
  "cldata",
  "structp",
  "structdata",
  "intfp",
  "intfdata",
  "enump",
  "enumdata",
]

let functionKinds: Set = [
  "func",
]

let constantKinds: Set = [
  "data",
]

let rootURLs = [
  "https://developer.apple.com/documentation/foundation",
  "https://developer.apple.com/documentation/swift/swift_standard_library",
].compactMap { urlString -> URL? in
    if let url = URL(string: urlString) {
        return url
    } else {
        printToStandardError("invalid url: \(urlString)")

        return nil
    }
}

struct DocumentationData {
    struct Root: Codable {
        var title: Title
        var tasks: [Task]?
        var containingGroup: [Task]?
    }

    struct Title: Codable {
        var content: String
    }

    struct Task: Codable {
        var title: Title
        var role: String
        var symbols: [Symbol]
    }

    struct Symbol: Codable {
        var title: Title
        var role: String
        var paths: [String]
        var name: String?
        var kind: String?
        var usr: String?
        var domain: String?
    }
}

struct SymbolSets {
    var types = Set<String>()
    var enumCases = Set<String>()
    var methods = Set<String>()
    var properties = Set<String>()
    var functions = Set<String>()
    var constants = Set<String>()
}

let jsonDecoder = JSONDecoder()

func fetchDocumentationDataSync(url: URL) throws -> DocumentationData.Root? {
    guard let data = try fetchDocumentationDataSourceSync(url: url) else {
        return nil
    }

    return try jsonDecoder.decode(
      DocumentationData.Root.self,
      from: data
    )
}

func fetchDocumentationDataSourceSync(url: URL) throws -> Data? {
    let cacheBasePath = "cache_json"
    let fileManager = FileManager.`default`
    let cachePath = cacheBasePath + "/" + cacheNameOf(url: url)

    if let cached = fileManager.contents(atPath: cachePath) {
        return cached
    }

    let document = try fetchHTMLSync(url: url)

    guard
      let jsonString = try document.select("#bootstrap-data").first()?.data()
    else {
        return nil
    }

    let data = jsonString.data(using: .utf8)

    try ensureDirectory(atPath: cacheBasePath)

    if !fileManager.createFile(atPath: cachePath, contents: data) {
        printToStandardError("cannot create cache file at \(cachePath)")
    }

    return data
}

func simpleNameOf(symbol: DocumentationData.Symbol) -> String {
    let name = symbol.title.content
    let simpleName = name
      .prefix(while: { $0 != "(" })
      .split(separator: ".")
      .last!

    return String(simpleName)
}

func process(url: URL,
             symbol: DocumentationData.Symbol,
             path: String,
             urls: inout [URL],
             seenKinds: inout Set<String>,
             allSymbols: inout [String: SymbolSets]) {
    guard
      let nextURL = URL(string: path, relativeTo: baseURL)
    else {
        return
    }

    if let kind = symbol.kind,
       seenKinds.update(with: kind) == nil {
        // print("new kind: \(kind)")

        // print("\(symbol.role) \(symbol.kind ?? "") \(symbol.title.content)")
    }

    if symbol.role == "collectionGroup" ||
         classLikeKinds.contains(symbol.kind ?? "") {
        urls.append(nextURL)
    }

    if (symbol.domain ?? "") == "entitlements" {
        return
    }

    if symbol.role == "pseudoSymbol" {
        return
    }

    for key in allSymbols.keys {
        if !(url.absoluteString.starts(with: key)) {
            continue
        }

        if typeKinds.contains(symbol.kind ?? "") {
            allSymbols[key]?.types.update(
              with: simpleNameOf(symbol: symbol)
            )
        }

        if symbol.kind == "enumelt" {
            allSymbols[key]?.enumCases.update(
              with: simpleNameOf(symbol: symbol)
            )
        }

        if methodKinds.contains(symbol.kind ?? "") {
            allSymbols[key]?.methods.update(
              with: simpleNameOf(symbol: symbol)
            )
        }

        if propertyKinds.contains(symbol.kind ?? "") {
            allSymbols[key]?.properties.update(
              with: simpleNameOf(symbol: symbol)
            )
        }

        if functionKinds.contains(symbol.kind ?? "") {
            allSymbols[key]?.functions.update(
              with: simpleNameOf(symbol: symbol)
            )
        }

        if constantKinds.contains(symbol.kind ?? "") {
            allSymbols[key]?.constants.update(
              with: simpleNameOf(symbol: symbol)
            )
        }
    }
}

func process(rootURLs: [URL]) -> [String: SymbolSets] {
    var allSymbols = [
      "https://developer.apple.com/documentation/swift/": SymbolSets(),
      "https://developer.apple.com/documentation/foundation/": SymbolSets(),
    ]

    var urls = rootURLs
    var seenURLs = Set<URL>()
    var seenKinds = Set<String>()

    while !urls.isEmpty {
        let url = urls.removeLast()

        if seenURLs.update(with: url) != nil {
            continue
        }

        do {
            guard let root = try fetchDocumentationDataSync(url: url) else {
                continue
            }

            for task in (root.tasks ?? []) + (root.containingGroup ?? []) {
                for symbol in task.symbols {
                    for path in symbol.paths {
                        process(url: url,
                                symbol: symbol,
                                path: path,
                                urls: &urls,
                                seenKinds: &seenKinds,
                                allSymbols: &allSymbols)
                    }
                }
            }
        } catch let e {
            printToStandardError("cannot get data: \(e)")
        }
    }

    printToStandardError("")
    printToStandardError("kinds:")
    printToStandardError(seenKinds.sorted().joined(separator: "\n"))

    return allSymbols
}

let allSymbols = process(rootURLs: rootURLs)

print(";;; swift-mode-standard-types.el --- Major-mode for Apple's Swift programming language, Standard Types. -*- lexical-binding: t -*-")
print("")
print(";; Copyright (C) 2018-2020 taku0")
print("")
print(";; Authors: taku0 (http://github.com/taku0)")
print(";;")
print(";; Version: 8.0.2")
print(";; Package-Requires: ((emacs \"24.4\") (seq \"2.3\"))")
print(";; Keywords: languages swift")
print("")
print(";; This file is not part of GNU Emacs.")
print("")
print(";; This program is free software: you can redistribute it and/or modify")
print(";; it under the terms of the GNU General Public License as published by")
print(";; the Free Software Foundation, either version 3 of the License, or")
print(";; (at your option) any later version.")
print("")
print(";; This program is distributed in the hope that it will be useful,")
print(";; but WITHOUT ANY WARRANTY; without even the implied warranty of")
print(";; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the")
print(";; GNU General Public License for more details.")
print("")
print(";; You should have received a copy of the GNU General Public License")
print(";; along with this program.  If not, see <http://www.gnu.org/licenses/>.")
print("")
print(";;; Commentary:")
print("")
print(";; Types and members of the standard library and Foundation framework.")
print("")
print(";;; Code:")
print("")

let constNamePrefixes = [
  "https://developer.apple.com/documentation/swift/": "standard",
  "https://developer.apple.com/documentation/foundation/": "foundation",
]

let documentPrefixes = [
  "https://developer.apple.com/documentation/swift/": "Built-in",
  "https://developer.apple.com/documentation/foundation/": "Foundation",
]

for (key, symbols) in allSymbols.sorted(by: { (l1, l2) in l1.0 < l2.0 }) {
    guard
      let constNamePrefix = constNamePrefixes[key],
      let documentPrefix = documentPrefixes[key]
    else {
        continue
    }

    print()
    print("(defconst swift-mode:\(constNamePrefix)-types")
    print("  '(\(symbols.types.sorted().map({"\"" + $0 + "\""}).joined(separator: "\n    ")))")
    print("  \"\(documentPrefix) types.\")")

    print()
    print("(defconst swift-mode:\(constNamePrefix)-enum-cases")
    print("  '(\(symbols.enumCases.sorted().map({"\"" + $0 + "\""}).joined(separator: "\n    ")))")
    print("  \"\(documentPrefix) enum cases.\")")

    print()
    print("(defconst swift-mode:\(constNamePrefix)-methods")
    print("  '(\(symbols.methods.sorted().map({"\"" + $0 + "\""}).joined(separator: "\n    ")))")
    print("  \"\(documentPrefix) methods.\")")

    print()
    print("(defconst swift-mode:\(constNamePrefix)-properties")
    print("  '(\(symbols.properties.sorted().map({"\"" + $0 + "\""}).joined(separator: "\n    ")))")
    print("  \"\(documentPrefix) properties.\")")

    print()
    print("(defconst swift-mode:\(constNamePrefix)-functions")
    print("  '(\(symbols.functions.sorted().map({"\"" + $0 + "\""}).joined(separator: "\n    ")))")
    print("  \"\(documentPrefix) functions.\")")

    print()
    print("(defconst swift-mode:\(constNamePrefix)-constants")
    print("  '(\(symbols.constants.sorted().map({"\"" + $0 + "\""}).joined(separator: "\n    ")))")
    print("  \"\(documentPrefix) constants.\")")
}

print("")
print("(provide 'swift-mode-standard-types)")
print("")
print(";;; swift-mode-standard-types.el ends here")

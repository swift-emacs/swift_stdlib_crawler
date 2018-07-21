// swift_stdlib_crawler --- crawler for Swift stdlib and Foundation.
// Copyright (C) 2018  taku0 https://github.com/taku0

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

import SwiftSoup

// Alamofire does not work on Linux yet.
// https://github.com/Alamofire/Alamofire/issues/1935
//
// Using simple functions for now.

enum FetchError: Error {
    case networkError(Error)
    case invalidResponse
}

func fetchDataSync(url: URL) throws -> Data {
    let cacheBasePath = "cache"
    let fileManager = FileManager.`default`
    let cachePath = cacheBasePath + "/" + cacheNameOf(url: url)

    if let cached = fileManager.contents(atPath: cachePath) {
        return cached
    }

    printToStandardError("fetching \(url)")

    let data = try doFetchDataSync(url: url)

    Thread.sleep(forTimeInterval: 5)

    try ensureDirectory(atPath: cacheBasePath)

    if !fileManager.createFile(atPath: cachePath, contents: data) {
        printToStandardError("cannot create cache file at \(cachePath)")
    }

    return data
}

func doFetchDataSync(url: URL) throws -> Data {
    let dispatchGroup = DispatchGroup()
    var request = URLRequest(url: url)

    request.setValue(
      "SwiftStdlibCrawlerForSwiftMode/1.0 (+https://github.com/swift-emacs/swift-mode)",
      forHTTPHeaderField: "User-Agent"
    )

    var result: Data?
    var errorResult: Error?

    let task = URLSession.shared.dataTask(with: request) { data,
                                                           response,
                                                           error
                                                           in
        defer {
            dispatchGroup.leave()
        }

        if let error = error {
            errorResult = FetchError.networkError(error)
            return
        }

        guard
          let httpResponse = response as? HTTPURLResponse,
          (200...299).contains(httpResponse.statusCode),
          let data = data
        else {
            errorResult = FetchError.invalidResponse
            return
        }

        result = data
    }

    dispatchGroup.enter()

    task.resume()

    dispatchGroup.wait()

    if let error = errorResult {
        throw error
    } else if let result = result {
        return result
    } else {
        throw FetchError.invalidResponse
    }
}

func fetchTextSync(url: URL) throws -> String {
    let data = try fetchDataSync(url: url)

    if let text = String(data: data, encoding: .utf8) {
        return text
    } else {
        throw FetchError.invalidResponse
    }
}

func fetchHTMLSync(url: URL) throws -> Document {
    let text = try fetchTextSync(url: url)

    return try SwiftSoup.parse(text)
}

func cacheNameOf(url: URL) -> String {
    return url.absoluteString.addingPercentEncoding(
      withAllowedCharacters: CharacterSet.urlHostAllowed
    )!
}

func ensureDirectory(atPath path: String) throws {
    let fileManager = FileManager.`default`

    do {
        try fileManager.createDirectory(
          atPath: path, withIntermediateDirectories: false
        )
    } catch let error {
        var isDirectory: ObjCBool = false
        let exists = fileManager.fileExists(
          atPath: path, isDirectory: &isDirectory
        )

        if !exists || !isDirectory.boolValue {
            throw error
        }
    }
}

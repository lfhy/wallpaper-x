import Foundation

extension SteamWorkshopService {
    static func parseDetailPage(html: String, fallbackID: String) -> SteamWorkshopDetailParseResult {
        let title = firstCapture(
            pattern: #"<div[^>]*class="workshopItemTitle"[^>]*>\s*(.*?)\s*</div>"#,
            in: html
        )
        ?? metaContent(property: "og:title", in: html)
        ?? "Workshop #\(fallbackID)"

        let author = firstCapture(
            pattern: #"<div[^>]*class="friendBlockContent"[^>]*>\s*(.*?)\s*<br"#,
            in: html
        ) ?? "未知作者"
        let authorProfileURL = normalizeSteamCommunityURL(
            firstCapture(
                pattern: #"<a[^>]*class="friendBlockLinkOverlay"[^>]*href="([^"]+)""#,
                in: html
            )
        )
        let authorWorkshopURL = normalizedAuthorWorkshopURL(
            firstURLMatch(
                pattern: #"https://steamcommunity\.com/(?:profiles/\d+|id/[^/"?]+)/myworkshopfiles/(?:\?[^"'\\<]*)?"#,
                in: html
            )
        )

        let summary = metaContent(property: "og:description", in: html)
            ?? firstCapture(pattern: #"<div[^>]*class="workshopItemDescription"[^>]*>(.*?)</div>"#, in: html)
            ?? ""

        let descriptionText = firstCapture(
            pattern: #"<div[^>]*class="workshopItemDescription"[^>]*>(.*?)</div>"#,
            in: html
        ) ?? summary

        let stats = parseStatsMap(from: html)
        let workshopTags = parseWorkshopTags(from: html)
        let rawTags = workshopTags.flatMap(\.values)
        let tags = Array(NSOrderedSet(array: rawTags.filter { !$0.isEmpty })) as? [String] ?? []
        let detailFields = buildDetailFields(stats: stats, workshopTags: workshopTags)
        let previewImageURL = metaURL(property: "og:image", in: html)
        return SteamWorkshopDetailParseResult(
            title: normalizeText(title),
            author: normalizeAuthorName(author),
            authorProfileURL: authorProfileURL,
            authorWorkshopURL: authorWorkshopURL,
            summary: normalizeText(summary),
            descriptionText: normalizeText(descriptionText),
            tags: tags.map(normalizeText),
            workshopTypeText: normalizedWorkshopTagValue(forKey: "Type", in: workshopTags)
                ?? normalizedStatValue(forKey: "Type", in: stats),
            ageRatingText: normalizedWorkshopTagValue(forKey: "Age Rating", in: workshopTags),
            genreText: normalizedWorkshopTagValue(forKey: "Genre", in: workshopTags),
            categoryText: normalizedWorkshopTagValue(forKey: "Category", in: workshopTags),
            previewImageURL: previewImageURL,
            previewVideoURL: nil,
            fileSizeText: normalizedStatValue(forKey: "File Size", in: stats)
                ?? normalizedStatValue(forKey: "文件大小", in: stats),
            resolutionText: normalizedWorkshopTagValue(forKey: "Resolution", in: workshopTags)
                ?? normalizedStatValue(forKey: "Resolution", in: stats)
                ?? resolutionFallback(in: html),
            postedText: normalizedStatValue(forKey: "Posted", in: stats)
                ?? normalizedStatValue(forKey: "发表于", in: stats),
            updatedText: normalizedStatValue(forKey: "Updated", in: stats)
                ?? normalizedStatValue(forKey: "Last Updated", in: stats)
                ?? normalizedStatValue(forKey: "更新于", in: stats),
            favoritesText: normalizedStatValue(forKey: "Favorite", in: stats)
                ?? normalizedStatValue(forKey: "Favorited", in: stats),
            subscriptionsText: normalizedStatValue(forKey: "Subscriptions", in: stats),
            scoreText: normalizedStatValue(forKey: "Score", in: stats),
            detailFields: detailFields
        )
    }

    static func parseStatsMap(from html: String) -> [String: String] {
        let labels = firstCaptureMatches(
            pattern: #"<div[^>]*class="detailsStatLeft"[^>]*>\s*(.*?)\s*</div>"#,
            in: html
        )
        let values = firstCaptureMatches(
            pattern: #"<div[^>]*class="detailsStatRight"[^>]*>\s*(.*?)\s*</div>"#,
            in: html
        )
        var map: [String: String] = [:]
        for index in 0..<min(labels.count, values.count) {
            let key = normalizeText(labels[index])
            let value = normalizeText(values[index])
            if !key.isEmpty, !value.isEmpty {
                map[key] = value
            }
        }
        return map
    }

    static func normalizedStatValue(forKey key: String, in stats: [String: String]) -> String? {
        if let direct = stats[key], !direct.isEmpty {
            return direct
        }
        return stats.first { candidate, _ in
            candidate.localizedCaseInsensitiveContains(key)
        }?.value
    }

    static func parseWorkshopTags(from html: String) -> [(key: String, values: [String])] {
        let pattern = #"<div[^>]*class="workshopTags"[^>]*>\s*<span[^>]*class="workshopTagsTitle"[^>]*>(.*?)</span>(.*?)</div>"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return []
        }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        var result: [(key: String, values: [String])] = []

        for match in regex.matches(in: html, options: [], range: range) {
            guard match.numberOfRanges >= 3,
                  let keyRange = Range(match.range(at: 1), in: html),
                  let valuesRange = Range(match.range(at: 2), in: html) else { continue }

            let key = normalizeText(String(html[keyRange]).replacingOccurrences(of: ":", with: ""))
            let valuesHTML = String(html[valuesRange])
            let values = firstCaptureMatches(
                pattern: #"<a[^>]*>\s*(.*?)\s*</a>"#,
                in: valuesHTML
            ).map(normalizeText).filter { !$0.isEmpty }

            if !key.isEmpty, !values.isEmpty {
                result.append((key: key, values: values))
            }
        }

        return result
    }

    static func normalizedWorkshopTagValue(
        forKey key: String,
        in workshopTags: [(key: String, values: [String])]
    ) -> String? {
        if let exact = workshopTags.first(where: { $0.key.compare(key, options: .caseInsensitive) == .orderedSame }) {
            return exact.values.joined(separator: " · ")
        }
        if let fuzzy = workshopTags.first(where: { $0.key.localizedCaseInsensitiveContains(key) }) {
            return fuzzy.values.joined(separator: " · ")
        }
        return nil
    }

    static func buildDetailFields(
        stats: [String: String],
        workshopTags: [(key: String, values: [String])]
    ) -> [SteamWorkshopDetailField] {
        var fields: [SteamWorkshopDetailField] = []
        var seen = Set<String>()

        func appendField(label: String, value: String) {
            let normalizedLabel = normalizeText(label.replacingOccurrences(of: ":", with: ""))
            let normalizedValue = normalizeText(value)
            guard !normalizedLabel.isEmpty, !normalizedValue.isEmpty else { return }
            let key = "\(normalizedLabel)|\(normalizedValue)"
            guard seen.insert(key).inserted else { return }
            fields.append(SteamWorkshopDetailField(label: normalizedLabel, value: normalizedValue))
        }

        let preferredStatOrder = [
            "File Size", "文件大小",
            "Posted", "发表于",
            "Updated", "Last Updated",
            "Subscriptions", "Favorited", "Favorites", "Favorite", "Score"
        ]
        for key in preferredStatOrder {
            if let value = normalizedStatValue(forKey: key, in: stats) {
                appendField(label: key, value: value)
            }
        }

        for tag in workshopTags {
            appendField(label: tag.key, value: tag.values.joined(separator: " · "))
        }

        for (key, value) in stats.sorted(by: { $0.key < $1.key }) {
            appendField(label: key, value: value)
        }

        return fields
    }

    static func resolutionFallback(in html: String) -> String? {
        guard let match = firstCapture(
            pattern: #"(\d{3,5}\s*[xX×]\s*\d{3,5})"#,
            in: html
        ) else {
            return nil
        }
        return normalizeText(match.replacingOccurrences(of: "x", with: "×"))
    }

    static func metaContent(property: String, in html: String) -> String? {
        firstCapture(
            pattern: #"<meta[^>]+property="\#(property)"[^>]+content="([^"]+)""#,
            in: html
        )
    }

    static func metaURL(property: String, in html: String) -> URL? {
        guard let value = metaContent(property: property, in: html) else { return nil }
        return URL(string: htmlDecode(value))
    }

    static func firstURLMatch(pattern: String, in html: String) -> URL? {
        guard let value = firstCapture(pattern: pattern, in: html) else { return nil }
        return URL(string: htmlDecode(value))
    }

    static func normalizeSteamCommunityURL(_ rawValue: String?) -> URL? {
        guard let rawValue else { return nil }
        let decoded = htmlDecode(rawValue)
        if decoded.hasPrefix("//") {
            return URL(string: "https:\(decoded)")
        }
        if decoded.hasPrefix("/") {
            return URL(string: decoded, relativeTo: URL(string: "https://steamcommunity.com"))?.absoluteURL
        }
        return URL(string: decoded)
    }

    static func normalizedAuthorWorkshopURL(_ url: URL?) -> URL? {
        guard let url else { return nil }
        let absoluteURL = url.absoluteURL
        guard absoluteURL.path.contains("/myworkshopfiles") else { return absoluteURL }
        guard var components = URLComponents(url: absoluteURL, resolvingAgainstBaseURL: false) else {
            return absoluteURL
        }

        var queryItems = (components.queryItems ?? []).filter { $0.name != "appid" }
        queryItems.append(URLQueryItem(name: "appid", value: Constants.workshopAppID))
        components.queryItems = queryItems
        return components.url ?? absoluteURL
    }

    static func resolvedAuthorWorkshopURL(for item: SteamWorkshopBrowserItem) -> URL? {
        if let authorWorkshopURL = normalizedAuthorWorkshopURL(item.authorWorkshopURL) {
            return authorWorkshopURL
        }
        guard let authorProfileURL = item.authorProfileURL else { return nil }
        if authorProfileURL.path.contains("/myworkshopfiles") {
            return normalizedAuthorWorkshopURL(authorProfileURL) ?? authorProfileURL
        }
        guard var components = URLComponents(
            url: authorProfileURL.appendingPathComponent("myworkshopfiles"),
            resolvingAgainstBaseURL: false
        ) else {
            return authorProfileURL
        }
        components.queryItems = [URLQueryItem(name: "appid", value: Constants.workshopAppID)]
        return components.url ?? authorProfileURL
    }

    static func browsePageHasMore(html: String, currentPage: Int) -> Bool {
        let nextPage = currentPage + 1
        let pattern = #"href\s*=\s*["'][^"']*[?&]p=\#(nextPage)(?:[&#][^"']*|[^"']*)?["']"#
        return firstCapture(pattern: pattern, in: html) != nil
    }

    static func parseBrowsePage(html: String) -> [SteamWorkshopBrowseStub] {
        var results: [SteamWorkshopBrowseStub] = []
        var seen = Set<String>()
        let browseSummaries = parseBrowseSummaries(from: html)

        let blockPattern = #"<div[^>]*class="workshopItem"[^>]*>(.*?)</script>"#
        guard let regex = try? NSRegularExpression(pattern: blockPattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return results
        }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)

        for match in regex.matches(in: html, options: [], range: range) {
            guard match.numberOfRanges >= 2,
                  let blockRange = Range(match.range(at: 1), in: html) else { continue }

            let block = String(html[blockRange])
            let id = firstCapture(
                pattern: #"data-publishedfileid="(\d+)""#,
                in: block
            ).map(normalizeText) ?? ""
            guard !id.isEmpty, seen.insert(id).inserted else { continue }
            let title = firstCapture(
                pattern: #"<div[^>]*class="workshopItemTitle[^"]*"[^>]*>\s*(.*?)\s*</div>"#,
                in: block
            )

            let author = firstCapture(
                pattern: #"<div[^>]*class="workshopItemAuthorName[^"]*"[^>]*>.*?<a[^>]*>\s*(.*?)\s*</a>"#,
                in: block
            )
            let authorWorkshopURL = normalizedAuthorWorkshopURL(
                firstURLMatch(
                    pattern: #"<a[^>]*class="workshop_author_link"[^>]*href="([^"]+)""#,
                    in: block
                )
            )

            let previewImageURL = firstURLMatch(
                pattern: #"<img[^>]*class="workshopItemPreviewImage[^"]*"[^>]*src="([^"]+)""#,
                in: block
            )

            results.append(
                SteamWorkshopBrowseStub(
                    id: id,
                    title: title.map(normalizeText),
                    author: author.map(normalizeAuthorName),
                    authorProfileURL: nil,
                    authorWorkshopURL: authorWorkshopURL,
                    hasAdultContent: block.localizedCaseInsensitiveContains("has_adult_content"),
                    summary: browseSummaries[id].map(normalizeText),
                    previewImageURL: previewImageURL
                )
            )
        }

        return results
    }

    static func parseBrowseSummaries(from html: String) -> [String: String] {
        let pattern = #"SharedFileBindMouseHover\(\s*"sharedfile_(\d+)"\s*,\s*false\s*,\s*(\{.*?\})\s*\);"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive, .dotMatchesLineSeparators]) else {
            return [:]
        }

        let range = NSRange(html.startIndex..<html.endIndex, in: html)
        var result: [String: String] = [:]
        for match in regex.matches(in: html, options: [], range: range) {
            guard match.numberOfRanges >= 3,
                  let idRange = Range(match.range(at: 1), in: html),
                  let payloadRange = Range(match.range(at: 2), in: html) else { continue }

            let id = String(html[idRange])
            let payload = String(html[payloadRange])
                .replacingOccurrences(of: #"\\/"#, with: "/", options: .regularExpression)
            guard let data = payload.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                continue
            }

            let description = (json["description"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let shortDescription = (json["short_description"] as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let value = description?.isEmpty == false ? description : shortDescription
            if let value, !value.isEmpty {
                result[id] = value
            }
        }
        return result
    }
}

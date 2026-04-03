import Foundation

extension SteamWorkshopService {
    static func makeBrowseURL(
        source: SteamWorkshopSource,
        query: String,
        trendingWindow: SteamWorkshopTrendingWindow,
        themeFilter: SteamWorkshopThemeFilter,
        ageRatingFilter: SteamWorkshopAgeRatingFilter,
        resolutionFilter: SteamWorkshopResolutionFilter,
        categoryFilter: SteamWorkshopCategoryFilter,
        page: Int
    ) -> URL {
        var components = URLComponents(string: Constants.steamCommunityBase)!
        var queryItems = [
            URLQueryItem(name: "appid", value: Constants.workshopAppID),
            URLQueryItem(name: "searchtext", value: query),
            URLQueryItem(name: "browsesort", value: source.browseFilter),
            URLQueryItem(name: "actualsort", value: source.browseFilter),
            URLQueryItem(name: "section", value: "readytouseitems"),
            URLQueryItem(name: "requiredtags[0]", value: "Video"),
            URLQueryItem(name: "numperpage", value: "\(Constants.browserPageSize)"),
            URLQueryItem(name: "p", value: "\(max(1, page))")
        ]
        if let themeTag = themeFilter.tagValue {
            queryItems.append(URLQueryItem(name: "requiredtags[]", value: themeTag))
        }
        if let ageTag = ageRatingFilter.tagValue {
            queryItems.append(URLQueryItem(name: "requiredtags[]", value: ageTag))
        }
        if let resolutionTag = resolutionFilter.tagValue {
            queryItems.append(URLQueryItem(name: "requiredtags[]", value: resolutionTag))
        }
        if let categoryTag = categoryFilter.tagValue {
            queryItems.append(URLQueryItem(name: "requiredtags[]", value: categoryTag))
        }
        if source.supportsTimeRange {
            queryItems.append(URLQueryItem(name: "days", value: trendingWindow.daysValue))
        }
        components.queryItems = queryItems
        return components.url!
    }

    static func makeDetailURL(id: String) -> URL {
        var components = URLComponents(string: Constants.detailBase)!
        components.queryItems = [
            URLQueryItem(name: "id", value: id),
            URLQueryItem(name: "searchtext", value: "")
        ]
        return components.url!
    }

    static func makeAuthorWorkshopURL(baseURL: URL, page: Int) -> URL {
        let normalizedURL = normalizedAuthorWorkshopURL(baseURL) ?? baseURL
        guard var components = URLComponents(url: normalizedURL, resolvingAgainstBaseURL: false) else {
            return normalizedURL
        }
        let existingQueryItems = components.queryItems ?? []
        var queryItems = existingQueryItems.filter {
            let key = $0.name
            return key != "p" && key != "appid" && key != "numperpage"
        }
        queryItems.insert(URLQueryItem(name: "appid", value: Constants.workshopAppID), at: 0)
        queryItems.append(URLQueryItem(name: "p", value: "\(max(1, page))"))
        queryItems.append(URLQueryItem(name: "numperpage", value: "\(Constants.authorWorkshopPageSize)"))
        components.queryItems = queryItems
        return components.url ?? normalizedURL
    }
}

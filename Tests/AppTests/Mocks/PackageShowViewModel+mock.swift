@testable import App

import Foundation


extension PackageShow.Model {
    static var mock: PackageShow.Model {
        .init(title: "Alamofire",
              url: "https://github.com/Alamofire/Alamofire.git",
              license: .mit,
              summary: "Lorem ipsum dolor sit amet, consectetur adipiscing elit. Quisque quis porttitor erat. Vivamus porttitor mi odio, quis imperdiet velit blandit id. Vivamus vehicula urna eget ipsum laoreet, sed porttitor sapien malesuada. Mauris faucibus tellus at augue vehicula, vitae aliquet felis ullamcorper. Praesent vitae leo rhoncus, egestas elit id, porttitor lacus. Cras ac bibendum mauris. Praesent luctus quis nulla sit amet tempus. Ut pharetra non augue sed pellentesque.",
              authors: [
                .init(name: "Christian Noon", url: "https://github.com/cnoon"),
                .init(name: "Mattt", url: "https://github.com/mattt"),
                .init(name: "Jon Shier", url: "https://github.com/jshier"),
                .init(name: "Kevin Harwood", url: "https://github.com/kcharwood"),
                .init(name: "186 other contributors", url: "https://github.com/Alamofire/Alamofire/graphs/contributors"),
            ],
              history: .init(
                since: "over 5 years",
                commits: .init(name: "1,433 commits",
                               url: "https://github.com/Alamofire/Alamofire/commits/master"),
                releases: .init(name: "79 releases",
                                url: "https://github.com/Alamofire/Alamofire/releases")
            ),
              activity: .init(
                openIssues: .init(name: "27 open issues",
                                  url: "https://github.com/Alamofire/Alamofire/issues"),
                pullRequests: .init(name: "5 open pull requests",
                                    url: "https://github.com/Alamofire/Alamofire/pulls"),
                lastPullRequestClosedMerged: "6 days ago"),
              products: .init(libraries: 3, executables: 1),
              releases: .init(stable: .init(date: "12 days ago",
                                            link: .init(name: "5.2.0",
                                                        url: "https://github.com/Alamofire/Alamofire/releases/tag/5.2.0")),
                              beta: .init(date: "4 days ago",
                                          link: .init(name: "5.3.0-beta.1",
                                                      url: "https://github.com/Alamofire/Alamofire/releases/tag/5.3.0-beta.1")),
                              latest: .init(date: "12 minutes ago",
                                            link: .init(name: "master",
                                                        url: "https://github.com/Alamofire/Alamofire"))),
              languagePlatforms: .init(
                stable: .init(
                    link: .init(name: "5.2.0",
                                url: "https://github.com/Alamofire/Alamofire/releases/tag/5.2.0"),
                    swiftVersions: ["5", "5.2"],
                    platforms: [.ios("10.0"), .macos("10.12"), .watchos("3.0"), .tvos("10.0")]),
                beta:.init(
                    link: .init(name: "5.3.1-beta.1",
                                url: "https://github.com/Alamofire/Alamofire/releases/tag/5.3.1-beta1"),
                    swiftVersions: ["5.2"],
                    platforms: [.ios("13.0"), .macos("10.15"), .watchos("6.0"), .tvos("13.0")]),
                latest: .init(
                    link: .init(name: "master",
                                url: "https://github.com/Alamofire/Alamofire"),
                    swiftVersions: ["5.2"],
                    platforms: [.ios("13.0"), .macos("10.15"), .watchos("6.0"), .tvos("13.0")]))
        )
    }
}

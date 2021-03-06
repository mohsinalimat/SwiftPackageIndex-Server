extension API {
    struct PostBuildTriggerDTO: Codable {
        var platform: Build.Platform
        var swiftVersion: SwiftVersion
    }

    struct PostCreateBuildDTO: Codable {
        var buildCommand: String?
        var jobUrl: String?
        var logUrl: String?
        var platform: Build.Platform
        var status: Build.Status
        var swiftVersion: SwiftVersion
    }
}

import Fluent
import SQLKit
import Vapor


struct BuildTriggerCommand: Command {
    let defaultLimit = 1

    struct Signature: CommandSignature {
        @Option(name: "limit", short: "l")
        var limit: Int?
        @Option(name: "id")
        var id: String?
    }

    var help: String { "Trigger package builds" }

    enum Parameter {
        case limit(Int)
        case id(UUID)
    }

    func run(using context: CommandContext, signature: Signature) throws {
        let limit = signature.limit ?? defaultLimit
        let id = signature.id.flatMap(UUID.init(uuidString:))

        let parameter: Parameter
        if let id = id {
            context.console.info("Triggering builds (id: \(id)) ...")
            parameter = .id(id)
        } else {
            context.console.info("Triggering builds (limit: \(limit)) ...")
            parameter = .limit(limit)
        }
        try triggerBuilds(on: context.application.db,
                          client: context.application.client,
                          logger: context.application.logger,
                          parameter: parameter).wait()
    }
}


func triggerBuilds(on database: Database,
                   client: Client,
                   logger: Logger,
                   parameter: BuildTriggerCommand.Parameter) -> EventLoopFuture<Void> {
    guard Current.allowBuildTriggers() else {
        logger.info("Build trigger override switch OFF - no builds are being triggered")
        return database.eventLoop.future()
    }
    guard Current.random(0...1) <= Current.buildTriggerDownscaling() else {
        logger.info("Build trigger downscaling in effect - skipping builds")
        return database.eventLoop.future()
    }
    let ops: EventLoopFuture<Void>
    switch parameter {
        case .limit(let limit):
            ops = fetchBuildCandidates(database, limit: limit)
                .flatMap { triggerBuilds(on: database,
                                         client: client,
                                         logger: logger,
                                         packages: $0) }
        case .id(let id):
            ops = triggerBuilds(on: database,
                                client: client,
                                logger: logger,
                                packages: [id])
    }
    return ops
        .flatMap { trimBuilds(on: database) }
}


func triggerBuilds(on database: Database,
                   client: Client,
                   logger: Logger,
                   packages: [Package.Id]) -> EventLoopFuture<Void> {
    Current.getStatusCount(client, .pending)
        .flatMap { pendingJobs in
            var newJobs = 0
            return packages.map { pkgId in
                // check if we have capacity to schedule more builds before querying for candidates
                guard pendingJobs + newJobs < Current.gitlabPipelineLimit() else {
                    logger.info("too many pending pipelines (\(pendingJobs))")
                    return database.eventLoop.future()
                }
                return findMissingBuilds(database, packageId: pkgId)
                    .flatMap { triggers in
                        guard pendingJobs + newJobs < Current.gitlabPipelineLimit() else {
                            logger.info("too many pending pipelines (\(pendingJobs))")
                            return database.eventLoop.future()
                        }
                        newJobs += triggers.count
                        return triggerBuildsUnchecked(on: database,
                                                      client: client,
                                                      logger: logger,
                                                      triggers: triggers) }
            }
            .flatten(on: database.eventLoop)
    }
}



/// Trigger builds without checking the pipeline limit. This is the low level trigger function.
/// - Parameters:
///   - database: `Database` handle used for database access
///   - client: `Client` used for http request
///   - logger: `Logger` used for logging
///   - triggers: trigger information for builds to trigger
/// - Returns: `EventLoopFuture<Void>` future
func triggerBuildsUnchecked(on database: Database,
                            client: Client,
                            logger: Logger,
                            triggers: [BuildTriggerInfo]) -> EventLoopFuture<Void> {
    triggers.map { trigger -> EventLoopFuture<Void> in
        logger.info("Triggering \(trigger.pairs.count) builds for version id: \(trigger.versionId)")
        return trigger.pairs.map { pair in
            Build.trigger(database: database,
                          client: client,
                          platform: pair.platform,
                          swiftVersion: pair.swiftVersion,
                          versionId: trigger.versionId)
                .flatMap { _ in
                    Build(versionId: trigger.versionId,
                          platform: pair.platform,
                          status: .pending,
                          swiftVersion: pair.swiftVersion)
                        .create(on: database)
                }
                .transform(to: ())
        }
        .flatten(on: database.eventLoop)
    }
    .flatten(on: database.eventLoop)
}


func fetchBuildCandidates(_ database: Database,
                          limit: Int) -> EventLoopFuture<[Package.Id]> {
    guard let db = database as? SQLDatabase else {
        fatalError("Database must be an SQLDatabase ('as? SQLDatabase' must succeed)")
    }

    struct Row: Decodable {
        var packageId: Package.Id

        enum CodingKeys: String, CodingKey {
            case packageId = "package_id"
        }
    }

    let expectedBuildCount = BuildPair.all.count

    return db.raw("""
            SELECT package_id, min(updated_at) FROM (
                SELECT v.package_id, v.latest, MIN(v.updated_at) updated_at
                FROM versions v
                LEFT JOIN builds b ON b.version_id = v.id
                WHERE v.latest IS NOT NULL
                GROUP BY v.package_id, v.latest
                HAVING COUNT(*) < \(bind: expectedBuildCount)
            ) AS t
            GROUP BY package_id
            ORDER BY MIN(updated_at)
            LIMIT \(bind: limit)
            """)
        .all(decoding: Row.self)
        .mapEach(\.packageId)
}


struct BuildPair: Equatable, Hashable {
    var platform: Build.Platform
    var swiftVersion: SwiftVersion

    init(_ platform: Build.Platform, _ swiftVersion: SwiftVersion) {
        self.platform = platform
        self.swiftVersion = swiftVersion
    }

    static let all: [Self] = {
        Build.Platform.allActive.flatMap { platform in
            SwiftVersion.allActive.compactMap { swiftVersion in
                // skip invalid combinations
                // ARM builds require Swift 5.3 or higher
                guard !platform.isArm || swiftVersion >= .init(5, 3, 0) else { return nil }
                return BuildPair(platform, swiftVersion)
            }
        }
    }()
}


struct BuildTriggerInfo: Equatable {
    var versionId: Version.Id
    var pairs: Set<BuildPair>

    init(_ versionId: Version.Id, _ pairs: Set<BuildPair>) {
        self.versionId = versionId
        self.pairs = pairs
    }
}


func findMissingBuilds(_ database: Database,
                       packageId: Package.Id) -> EventLoopFuture<[BuildTriggerInfo]> {
    let versions = Version.query(on: database)
        .with(\.$builds)
        .filter(\.$package.$id == packageId)
        .filter(\.$latest != nil)
        .all()

    return versions.mapEachCompact { v in
        guard let versionId = v.id else { return nil }
        let existing = v.builds.map { BuildPair($0.platform, $0.swiftVersion) }
        let pairs = Set(BuildPair.all).subtracting(Set(existing))
        return BuildTriggerInfo(versionId, pairs)
    }
}


func trimBuilds(on database: Database) -> EventLoopFuture<Void> {
    guard let db = database as? SQLDatabase else {
        fatalError("Database must be an SQLDatabase ('as? SQLDatabase' must succeed)")
    }
    return db.raw("""
        delete
        from builds b
        using versions v
        where b.version_id = v.id
        and (
            v.latest is null
            or
            (b.status = 'pending' and b.created_at < now() - interval '\(bind: Constants.trimBuildsGracePeriod) hours')
        )
        """).run()
}

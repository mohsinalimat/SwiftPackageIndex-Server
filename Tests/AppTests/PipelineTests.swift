@testable import App

import SQLKit
import Vapor
import XCTest


// Tests concerning the full pipeline of operations:
// - candidate selection at each stage
// - processing stage recording
// - error recording
class PipelineTests: AppTestCase {

    func test_fetchCandidates_ingestion_fifo() throws {
        // oldest first
        try  [
            Package(url: "1", status: .ok, processingStage: .reconciliation),
            Package(url: "2", status: .ok, processingStage: .reconciliation),
            ].save(on: app.db).wait()
        // fast forward our clock by the deadtime interval
        Current.date = { Date().addingTimeInterval(Constants.reIngestionDeadtime) }
        let batch = try Package.fetchCandidates(app.db, for: .ingestion, limit: 10).wait()
        XCTAssertEqual(batch.map(\.url), ["1", "2"])
    }

    func test_fetchCandidates_ingestion_limit() throws {
        try  [
            Package(url: "1", status: .ok, processingStage: .reconciliation),
            Package(url: "2", status: .ok, processingStage: .reconciliation),
            ].save(on: app.db).wait()
        // fast forward our clock by the deadtime interval
        Current.date = { Date().addingTimeInterval(Constants.reIngestionDeadtime) }
        let batch = try Package.fetchCandidates(app.db, for: .ingestion, limit: 1).wait()
        XCTAssertEqual(batch.map(\.url), ["1"])
    }

    func test_fetchCandidates_ingestion_correct_stage() throws {
        // only pick up from reconciliation stage
        try  [
            Package(url: "1", status: .ok, processingStage: nil),
            Package(url: "2", status: .ok, processingStage: .reconciliation),
            Package(url: "3", status: .ok, processingStage: .analysis),
            ].save(on: app.db).wait()
        let batch = try Package.fetchCandidates(app.db, for: .ingestion, limit: 10).wait()
        XCTAssertEqual(batch.map(\.url), ["2"])
    }

    func test_fetchCandidates_ingestion_prefer_ok() throws {
        // make sure records with status != .ok go to the end (to avoid blocking good
        // records)
        // (reonciliation does not currently actually report back any status != ok but
        // we'll account for it doing so at no harm potentially in the future.)
        try  [
            Package(url: "1", status: .notFound, processingStage: .reconciliation),
            Package(url: "2", status: .none, processingStage: .reconciliation),
            Package(url: "3", status: .ok, processingStage: .reconciliation),
            ].save(on: app.db).wait()
        // fast forward our clock by the deadtime interval
        Current.date = { Date().addingTimeInterval(Constants.reIngestionDeadtime) }
        let batch = try Package.fetchCandidates(app.db, for: .ingestion, limit: 10).wait()
        XCTAssertEqual(batch.map(\.url), ["3", "1", "2"])
    }

    func test_fetchCandidates_ingestion_eventual_refresh() throws {
        // Make sure packages in .analysis stage get re-ingested after a while to
        // check for upstream package changes
        try  [
            Package(url: "1", status: .ok, processingStage: .analysis),
            Package(url: "2", status: .ok, processingStage: .analysis),
            ].save(on: app.db).wait()
        let p2 = try Package.query(on: app.db).filter(by: "2").first().wait()!
        let sql = "update packages set updated_at = updated_at - interval '61 mins' where id = '\(p2.id!.uuidString)'"
        try (app.db as! SQLDatabase).raw(.init(sql)).run().wait()
        let batch = try Package.fetchCandidates(app.db, for: .ingestion, limit: 10).wait()
        XCTAssertEqual(batch.map(\.url), ["2"])
    }

    func test_fetchCandidates_analysis_correct_stage() throws {
        // only pick up from ingestion stage
        try  [
            Package(url: "1", status: .ok, processingStage: nil),
            Package(url: "2", status: .ok, processingStage: .reconciliation),
            Package(url: "3", status: .ok, processingStage: .ingestion),
            Package(url: "4", status: .ok, processingStage: .analysis),
            ].save(on: app.db).wait()
        let batch = try Package.fetchCandidates(app.db, for: .analysis, limit: 10).wait()
        XCTAssertEqual(batch.map(\.url), ["3"])
    }

    func test_fetchCandidates_analysis_prefer_ok() throws {
        // only pick up from ingestion stage
        try  [
            Package(url: "1", status: .notFound, processingStage: .ingestion),
            Package(url: "2", status: .ok, processingStage: .ingestion),
            Package(url: "3", status: .analysisFailed, processingStage: .ingestion),
            Package(url: "4", status: .ok, processingStage: .ingestion),
            ].save(on: app.db).wait()
        let batch = try Package.fetchCandidates(app.db, for: .analysis, limit: 10).wait()
        XCTAssertEqual(batch.map(\.url), ["2", "4", "1", "3"])
    }

    func test_processing_pipeline() throws {
        // Test pipeline pick-up end to end

        // setup
        let urls = ["1", "2", "3"].gh
        Current.fetchMasterPackageList = { _ in .just(value: urls.urls) }
        Current.shell.run = { cmd, path in
            if cmd.string == "swift package dump-package" {
                return #"{ "name": "Mock", "products": [] }"#
            }
            if cmd.string.hasPrefix(#"git log -n1 --format=format:"%H-%ct""#) { return "sha-0" }
            return ""
        }

        // MUT - first stage
        try reconcile(client: app.client, database: app.db).wait()

        do {  // validate
            let packages = try Package.query(on: app.db).sort(\.$url).all().wait()
            XCTAssertEqual(packages.map(\.url), ["1", "2", "3"].gh)
            XCTAssertEqual(packages.map(\.status), [.none, .none, .none])
            XCTAssertEqual(packages.map(\.processingStage), [.reconciliation, .reconciliation, .reconciliation])
        }

        // MUT - second stage
        try ingest(application: app, database: app.db, limit: 10).wait()

        do { // validate
            let packages = try Package.query(on: app.db).sort(\.$url).all().wait()
            XCTAssertEqual(packages.map(\.url), ["1", "2", "3"].gh)
            XCTAssertEqual(packages.map(\.status), [.ok, .ok, .ok])
            XCTAssertEqual(packages.map(\.processingStage), [.ingestion, .ingestion, .ingestion])
        }

        // MUT - third stage
        try analyze(application: app, limit: 10).wait()

        do { // validate
            let packages = try Package.query(on: app.db).sort(\.$url).all().wait()
            XCTAssertEqual(packages.map(\.url), ["1", "2", "3"].gh)
            XCTAssertEqual(packages.map(\.status), [.ok, .ok, .ok])
            XCTAssertEqual(packages.map(\.processingStage), [.analysis, .analysis, .analysis])
        }

        // Now we've got a new package and a deletion
        Current.fetchMasterPackageList = { _ in .just(value: ["1", "3", "4"].gh.urls) }

        // MUT - reconcile again
        try reconcile(client: app.client, database: app.db).wait()

        do {  // validate - only new package moves to .reconciliation stage
            let packages = try Package.query(on: app.db).sort(\.$url).all().wait()
            XCTAssertEqual(packages.map(\.url), ["1", "3", "4"].gh)
            XCTAssertEqual(packages.map(\.status), [.ok, .ok, .none])
            XCTAssertEqual(packages.map(\.processingStage), [.analysis, .analysis, .reconciliation])
        }

        // MUT - ingest again
        try ingest(application: app, database: app.db, limit: 10).wait()

        do {  // validate - only new package moves to .ingestion stage
            let packages = try Package.query(on: app.db).sort(\.$url).all().wait()
            XCTAssertEqual(packages.map(\.url), ["1", "3", "4"].gh)
            XCTAssertEqual(packages.map(\.status), [.ok, .ok, .ok])
            XCTAssertEqual(packages.map(\.processingStage), [.analysis, .analysis, .ingestion])
        }

        // MUT - analyze again
        let lastAnalysis = Current.date()
        try analyze(application: app, limit: 10).wait()

        do {  // validate - only new package moves to .ingestion stage
            let packages = try Package.query(on: app.db).sort(\.$url).all().wait()
            XCTAssertEqual(packages.map(\.url), ["1", "3", "4"].gh)
            XCTAssertEqual(packages.map(\.status), [.ok, .ok, .ok])
            XCTAssertEqual(packages.map(\.processingStage), [.analysis, .analysis, .analysis])
            XCTAssertEqual(packages.map { $0.updatedAt! > lastAnalysis }, [false, false, true])
        }

        // fast forward our clock by the deadtime interval
        Current.date = { Date().addingTimeInterval(Constants.reIngestionDeadtime) }

        // MUT - ingest yet again
        try ingest(application: app, database: app.db, limit: 10).wait()

        do {  // validate - now all three packages should have been updated
            let packages = try Package.query(on: app.db).sort(\.$url).all().wait()
            XCTAssertEqual(packages.map(\.url), ["1", "3", "4"].gh)
            XCTAssertEqual(packages.map(\.status), [.ok, .ok, .ok])
            XCTAssertEqual(packages.map(\.processingStage), [.ingestion, .ingestion, .ingestion])
        }

        // MUT - re-run analysis to complete the sequence
        try analyze(application: app, limit: 10).wait()

        do {  // validate - only new package moves to .ingestion stage
            let packages = try Package.query(on: app.db).sort(\.$url).all().wait()
            XCTAssertEqual(packages.map(\.url), ["1", "3", "4"].gh)
            XCTAssertEqual(packages.map(\.status), [.ok, .ok, .ok])
            XCTAssertEqual(packages.map(\.processingStage), [.analysis, .analysis, .analysis])
        }

        // at this point we've ensured that retriggering ingestion after the deadtime will
        // refresh analysis as expected
    }

}

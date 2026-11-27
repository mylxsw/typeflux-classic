@testable import Typeflux
import XCTest

final class FullAppReleaseTests: XCTestCase {
    private let base = URL(string: "https://api.example.com")!

    private func payload(version: String = "1.2.0", code: String = "OK", assets: String? = nil) -> Data {
        let assetJSON = assets ?? """
        [
          {"platform":"macos","architecture":"arm64","package_type":"full_dmg","channel":"global","file_name":"a.dmg","file_size":10,"sha256":"aa","download_url":"/d/macos/arm64/global?package_type=full_dmg"},
          {"platform":"macos","architecture":"arm64","package_type":"app_only_zip","channel":"cn","file_name":"cn.zip","file_size":20,"sha256":"bb","download_url":"/d/macos/arm64/cn?package_type=app_only_zip"},
          {"platform":"macos","architecture":"arm64","package_type":"app_only_zip","channel":"global","file_name":"g.zip","file_size":30,"sha256":"CC","download_url":"/d/macos/arm64/global?package_type=app_only_zip&product=classic"},
          {"platform":"macos","architecture":"x86_64","package_type":"app_only_zip","channel":"global","file_name":"i.zip","file_size":40,"sha256":"","download_url":"/d/macos/x86_64/global?package_type=app_only_zip"}
        ]
        """
        return Data("""
        {"code":"\(code)","message":"","data":{"version":"\(version)","title":"Typeflux","release_notes":"",
        "minimum_os":"13.0","source_url":"","published_at":"2026-11-26T00:00:00Z","assets":\(assetJSON)}}
        """.utf8)
    }

    func testPicksGlobalAppOnlyZipForArchitecture() throws {
        let package = try XCTUnwrap(FullAppReleaseResolver.package(from: payload(), apiBaseURL: base, architecture: "arm64"))
        XCTAssertEqual(package.version, "1.2.0")
        XCTAssertEqual(package.sha256, "cc")
        XCTAssertEqual(package.fileSize, 30)
        let components = try XCTUnwrap(URLComponents(url: package.downloadURL, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.host, "api.example.com")
        XCTAssertEqual(components.path, "/d/macos/arm64/global")
        XCTAssertEqual(components.queryItems?.filter { $0.name == "product" }.map(\.value), ["typeflux"])
        XCTAssertEqual(components.queryItems?.first { $0.name == "package_type" }?.value, "app_only_zip")
    }

    func testIntelPackageGetsProductAndDropsEmptyChecksum() throws {
        let package = try XCTUnwrap(FullAppReleaseResolver.package(from: payload(), apiBaseURL: base, architecture: "x86_64"))
        XCTAssertNil(package.sha256)
        XCTAssertTrue(package.downloadURL.absoluteString.contains("product=typeflux"))
    }

    func testFallsBackToAnotherChannel() throws {
        let assets = """
        [{"platform":"macos","architecture":"arm64","package_type":"app_only_zip","channel":"cn","download_url":"https://cdn.example.com/c.zip"}]
        """
        let package = try XCTUnwrap(FullAppReleaseResolver.package(from: payload(assets: assets), apiBaseURL: base, architecture: "arm64"))
        XCTAssertEqual(package.downloadURL.absoluteString, "https://cdn.example.com/c.zip")
    }

    func testNoAssetForArchitectureMeansUnavailable() {
        let assets = """
        [{"platform":"macos","architecture":"x86_64","package_type":"full_dmg","channel":"global","download_url":"/d/x"}]
        """
        XCTAssertNil(FullAppReleaseResolver.package(from: payload(assets: assets), apiBaseURL: base, architecture: "arm64"))
        XCTAssertNil(FullAppReleaseResolver.package(from: payload(assets: "null"), apiBaseURL: base, architecture: "arm64"))
    }

    func testErrorEnvelopeMeansUnavailable() {
        let data = Data(#"{"code":"RELEASE_NOT_FOUND","message":"no release"}"#.utf8)
        XCTAssertNil(FullAppReleaseResolver.package(from: data, apiBaseURL: base, architecture: "arm64"))
        XCTAssertNil(FullAppReleaseResolver.package(from: Data("not json".utf8), apiBaseURL: base, architecture: "arm64"))
        XCTAssertNil(FullAppReleaseResolver.package(from: payload(code: "INTERNAL"), apiBaseURL: base, architecture: "arm64"))
    }

    func testClassicReleaseIsNeverOfferedAsTheFullApp() {
        // A server that ignores product=typeflux may answer with the latest Classic.
        XCTAssertNil(FullAppReleaseResolver.package(from: payload(version: "0.6.1"), apiBaseURL: base, architecture: "arm64"))
        XCTAssertNil(FullAppReleaseResolver.package(from: payload(version: ""), apiBaseURL: base, architecture: "arm64"))
        XCTAssertTrue(FullAppReleaseResolver.isFullAppVersion("v1.2.0"))
        XCTAssertTrue(FullAppReleaseResolver.isFullAppVersion("2.0"))
        XCTAssertFalse(FullAppReleaseResolver.isFullAppVersion("0.9.9"))
        XCTAssertFalse(FullAppReleaseResolver.isFullAppVersion("beta"))
    }

    func testRequestsTheFullTypefluxProduct() {
        XCTAssertEqual(FullAppReleaseResolver.product, "typeflux")
        XCTAssertNotEqual(FullAppReleaseResolver.product, TypefluxProduct.identifier)
    }

    func testDownloadURLRejectsUnsupportedSchemes() {
        XCTAssertNil(FullAppReleaseResolver.downloadURL(for: "file:///tmp/a.zip", apiBaseURL: base))
        XCTAssertNil(FullAppReleaseResolver.downloadURL(for: "  ", apiBaseURL: base))
    }

    func testDownloadURLKeepsBasePathPrefix() throws {
        let prefixed = try XCTUnwrap(URL(string: "https://example.com/gateway/"))
        let url = try XCTUnwrap(FullAppReleaseResolver.downloadURL(for: "/d/macos/arm64/global", apiBaseURL: prefixed))
        XCTAssertEqual(url.absoluteString, "https://example.com/gateway/d/macos/arm64/global?product=typeflux")
    }

    func testAPIBaseURLStripsReleasePath() throws {
        let response = try XCTUnwrap(URL(string: "https://example.com/gateway/api/v1/app/releases/latest?product=typeflux"))
        XCTAssertEqual(FullAppReleaseResolver.apiBaseURL(fromResponseURL: response)?.absoluteString, "https://example.com/gateway")
    }

    func testAPIBaseURLWithoutReleasePathIsKept() throws {
        let response = try XCTUnwrap(URL(string: "https://example.com/other?x=1#frag"))
        XCTAssertEqual(FullAppReleaseResolver.apiBaseURL(fromResponseURL: response)?.absoluteString, "https://example.com/other")
    }

    func testServerArchitectureMapsIntel() {
        XCTAssertEqual(FullAppReleaseResolver.serverArchitecture("amd64"), "x86_64")
        XCTAssertEqual(FullAppReleaseResolver.serverArchitecture("arm64"), "arm64")
    }
}


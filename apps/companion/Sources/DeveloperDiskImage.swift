import Foundation

/// The developer disk image the client's JIT helper mounts when the device has none mounted (debugserver
/// is in it; apps/client/spjit.m): the cryptex from this Mac's Xcode, copied into the app's data container
/// (Library/spddi/), as research/jittest/push-ddi.sh does. These are Apple's files, from the user's own
/// Xcode to the user's own device, and go nowhere else. Only the cryptex the device mounts is copied
/// (BuildManifest.plist and the four Cryptex1 payloads its "Developer Disk Image Cryptex" identity names,
/// ~17 MB for iOS, ~13 MB for visionOS). That identity is chip-independent, so one image serves every
/// device of the platform, and its version is Xcode's, not the device OS's: Xcode's image mounts on every
/// OS version it supports. Library/spddi/version.txt names the copy and is written last, so the image is
/// copied again when Xcode updates it, or when a copy was interrupted.
enum DeveloperDiskImage {
    /// Where the client finds it, in its data container.
    static let deviceDir = "Library/spddi"

    struct Image {
        /// Xcode's image directory (Restore/ and version.plist).
        let source: URL
        /// The files to copy, relative to Restore/.
        let files: [String]
        /// "Xcode <build>, image <build>".
        let version: String
    }

    /// The image for a device platform (xros, ios) in Xcode's install.
    static func local(platform: String) throws -> Image {
        let (dir, name) = platform == "xros" ? ("xrOS_DDI", "visionOS") : ("iOS_DDI", "iOS")
        let source = URL(fileURLWithPath: "/Library/Developer/DeveloperDiskImages/\(dir)")
        guard let version = NSDictionary(contentsOf: source.appending(path: "version.plist")),
              let manifest = NSDictionary(contentsOf: source.appending(path: "Restore/BuildManifest.plist")) as? [String: Any] else {
            throw Failure("Xcode has no developer disk image for \(name) (\(source.path)). In Xcode > Settings > Components, install the \(name) platform.")
        }
        let files = try cryptexFiles(manifest)
        for f in files where !FileManager.default.fileExists(atPath: source.appending(path: "Restore/\(f)").path) {
            throw Failure("Xcode's developer disk image for \(name) is missing \(f). In Xcode > Settings > Components, reinstall the \(name) platform.")
        }
        return Image(source: source, files: files,
                     version: "Xcode \(version["ProductBuildVersion"] ?? "?"), image \(version["BuildVersion"] ?? "?")")
    }

    /// The files the cryptex identity names, relative to Restore/ (as idevice's cryptex1_assets_load reads
    /// them): BuildManifest.plist and the identity's four Cryptex1 payloads.
    static func cryptexFiles(_ manifest: [String: Any]) throws -> [String] {
        let identities = (manifest["BuildIdentities"] as? [[String: Any]] ?? []).filter {
            ((($0["Info"] as? [String: Any])?["Variant"] as? String) ?? "").hasSuffix("Developer Disk Image Cryptex")
        }
        guard identities.count == 1, let entries = identities[0]["Manifest"] as? [String: Any] else {
            throw Failure("Xcode's developer disk image has \(identities.count) Developer Disk Image Cryptex identities, not one.")
        }
        var files = ["BuildManifest.plist"]
        for key in ["Cryptex1,GenericDmg", "Cryptex1,GenericTrustCache", "Cryptex1,CryptexInfoPlist", "Cryptex1,GenericVolume"] {
            guard let path = ((entries[key] as? [String: Any])?["Info"] as? [String: Any])?["Path"] as? String,
                  !path.isEmpty, !path.hasPrefix("/"), !path.split(separator: "/").contains("..") else {
                throw Failure("Xcode's developer disk image names no usable file for \(key).")
            }
            files.append(path)
        }
        return files
    }

    /// Copies the image into the app's data container unless it has this version already. Returns the
    /// version copied, or nil when there was nothing to do.
    static func sendIfNeeded(to device: Device, onLine log: (String) -> Void) async throws -> String? {
        let image = try local(platform: device.platform)
        let staging = FileManager.default.temporaryDirectory.appending(path: "spddi-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: staging) }
        let have = staging.appending(path: "have.txt")
        if (try? await device.fetch("\(deviceDir)/version.txt", to: have)) != nil,
           (try? String(contentsOf: have, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines) == image.version {
            return nil
        }
        for f in image.files {
            let file = image.source.appending(path: "Restore/\(f)")
            let size = (try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int) ?? 0
            log("copying the developer disk image's \(f) (\(size) bytes)")
            try await device.copy(file, to: "\(deviceDir)/Restore/\(f)")
        }
        let list = staging.appending(path: "files.txt"), version = staging.appending(path: "version.txt")
        try (image.files.joined(separator: "\n") + "\n").write(to: list, atomically: true, encoding: .utf8)
        try await device.copy(list, to: "\(deviceDir)/files.txt")
        try (image.version + "\n").write(to: version, atomically: true, encoding: .utf8)
        try await device.copy(version, to: "\(deviceDir)/version.txt")
        return image.version
    }
}

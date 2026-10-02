import UniformTypeIdentifiers

/// File types offered by the picker. Declared in `Info.plist` (`UTImportedTypeDeclarations`,
/// `project.yml`) so the Files app recognizes the extensions.
enum ImportFileTypes {
    static let gpx = UTType(importedAs: "com.topografix.gpx", conformingTo: .xml)
    static let tcx = UTType(importedAs: "com.garmin.tcx", conformingTo: .xml)
    static let fit = UTType(importedAs: "com.garmin.fit", conformingTo: .data)

    static let all = [gpx, tcx, fit]
}

//
//  main.swift
//  itunes_sync
//
//  Created by loop on 13.08.2018.
//  Copyright © 2018 loop. All rights reserved.
//

// Edit Scheme & set environment variable OS_ACTIVITY_MODE disable

import Foundation
import iTunesLibrary // add /Library/Frameworks to Build Settings/Framework Search Paths
import ScriptingBridge

@objc public protocol iTunesApplication {
    @objc optional func tracks() -> SBElementArray
//    @objc optional func elementArray(WithCode: DescType) -> SBElementArray
    @objc optional func add(_ x: [URL]!, to: SBObject!) -> iTunesTrack
}
extension SBApplication: iTunesApplication {}

@objc public protocol iTunesTrack {
    @objc optional func delete()
}
extension SBObject: iTunesTrack {}

@objc public protocol FinderApplication {
    @objc optional func items() -> SBElementArray
//    @objc optional func activate()
}
extension SBApplication: FinderApplication {}

@objc public protocol FinderItem {
    @objc optional func reveal()
}
extension SBObject: FinderItem {}

let itunes: iTunesApplication = SBApplication(bundleIdentifier: "com.apple.iTunes")!
let finder: FinderApplication = SBApplication(bundleIdentifier: "com.apple.Finder")!
let fm = FileManager.default
var lib = Set<String>()
var numWindows: Int = 0


func deleteTrack(persistentID: UInt64) {
    let strID = String(format: "%016lX", persistentID)
    print("delete track \(strID)")
    let tracks = itunes.tracks!().filtered(using: NSPredicate(format: "persistentID == %@", strID))
    if tracks.count == 1 {
        let track = tracks[0] as! iTunesTrack
        track.delete!()
    }
}

func revealItem(path: String) {
    print("reveal \(path)")
    if numWindows > 50 {
        return
    }
    let url = URL(fileURLWithPath: path)
    let item = finder.items!().object(atLocation: url) as! FinderItem
    item.reveal!()
//    itunes.activate!()
    numWindows += 1
}

func addFile(path: String) {
    print("add \(path)")
    let _ = itunes.add!([URL(fileURLWithPath: path)], to: nil)
}

func checkFileName(name: String) -> Bool {
    if name == "cover.jpg" || name == "error.txt" {
        return true
    }
    
    var tmp = name
    var regexp: NSRegularExpression
    var numMatches: Int
    
    regexp = try! NSRegularExpression(pattern: "\\[([^]]*)\\]", options: [])
    tmp = regexp.stringByReplacingMatches(in: tmp, options: [], range: NSMakeRange(0, tmp.count), withTemplate: "$1")
    
    regexp = try! NSRegularExpression(pattern: "\\(([^)]*)\\)", options: [])
    tmp = regexp.stringByReplacingMatches(in: tmp, options: [], range: NSMakeRange(0, tmp.count), withTemplate: "$1")
    
    regexp = try! NSRegularExpression(pattern: "^(\\d{2,4}\\.)?[-A-Za-z0-9,'&#%_!+=@$~ ^]*\\.cue$", options: [])
    numMatches = regexp.numberOfMatches(in: tmp, options: [], range: NSMakeRange(0, tmp.count))
    if numMatches == 1 {
        return true
    }
    
    regexp = try! NSRegularExpression(pattern: "^\\d{2,4}\\. [-A-Za-z0-9,'&#%_!+=@$~ ^]*\\.(mp3|m4a)$", options: [])
    numMatches = regexp.numberOfMatches(in: tmp, options: [], range: NSMakeRange(0, tmp.count))
    if numMatches == 1 {
        return true
    }
    
    return false
}

func checkDirName(name: String) -> Bool {
    var tmp = name
    var regexp: NSRegularExpression
    var numMatches: Int
    
    if name == "flac" {
        return false
    }
    
    regexp = try! NSRegularExpression(pattern: "\\[([^]]*)\\]", options: [])
    tmp = regexp.stringByReplacingMatches(in: tmp, options: [], range: NSMakeRange(0, tmp.count), withTemplate: "$1")
    
    regexp = try! NSRegularExpression(pattern: "\\(([^)]*)\\)", options: [])
    tmp = regexp.stringByReplacingMatches(in: tmp, options: [], range: NSMakeRange(0, tmp.count), withTemplate: "$1")
    
    regexp = try! NSRegularExpression(pattern: "^[-A-Za-z0-9,'&#%_!+=@$~ ^]*$", options: [])
    numMatches = regexp.numberOfMatches(in: tmp, options: [], range: NSMakeRange(0, tmp.count))
    if numMatches == 1 {
        return true
    }
    
    return false
}

func scanFolder(folder: String) {
    do {
        let items = try fm.contentsOfDirectory(atPath: folder)
        for item in items {
            let fullPath = folder + "/" + item
            let attr = try fm.attributesOfItem(atPath: fullPath)
            if attr[FileAttributeKey.type] as? FileAttributeType == FileAttributeType.typeDirectory {
                if !checkDirName(name: item) {
                    revealItem(path: fullPath)
                }
                scanFolder(folder: fullPath)
            } else {
                if !checkFileName(name: item) {
                    revealItem(path: fullPath)
                    continue
                }
                let url = URL(fileURLWithPath: fullPath)
                if ["mp3", "m4a"].contains(url.pathExtension) {
                    if !lib.contains(fullPath) {
                        addFile(path: fullPath)
                    }
                }
            }
        }
    } catch {
    }
}

func scanLibrary() {
    if let library = try? ITLibrary(apiVersion: "1.0") {
        library.reloadData()
        for item in library.allMediaItems.filter({ $0.locationType == ITLibMediaItemLocationType.file }) {
            if item.location == nil {
                deleteTrack(persistentID: item.persistentID.uint64Value)
                continue
            }
            if let found = try? item.location!.checkResourceIsReachable() {
                if found {
                    lib.insert(item.location!.path)
                    continue
                }
            }
            deleteTrack(persistentID: item.persistentID.uint64Value)
        }
    }
}

// too slow
//func scanLibrary2() {
//    let tracks = itunes.elementArray!(withCode: 0x63466C54) // cFlT
//    for item in tracks {
//        let item = item as! iTunesFileTrack
//        if item.index! % 1000 == 0 {
//            print(item.index!)
//        }
//        let item = item as! SBObject
//        let location = item.value(forKey: "location") as? URL
//        if location == nil {
//            print(item.value(forKey: "name"))
//            continue
//        }
//        print(location!.path)
//    }
//}

let startTime = CFAbsoluteTimeGetCurrent()
scanLibrary()
scanFolder(folder: "/Volumes/music")
scanFolder(folder: "/Volumes/data2/Labels")
print((CFAbsoluteTimeGetCurrent()-startTime)/60.0)

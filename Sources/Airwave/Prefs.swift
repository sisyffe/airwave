import Foundation

enum Prefs {
    static let hotstart = "hotstart"
    static let lastURL = "lastURL"
    static let volume = "volume"
    static let ytdlpPath = "ytdlpPath"          // empty = auto-detect
}

enum Backend {
    #if YOUTUBEKIT
    static let name = "YouTubeKit"
    #else
    static let name = "yt-dlp"
    #endif
}

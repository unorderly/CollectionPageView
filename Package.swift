// swift-tools-version: 5.10
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(name: "CollectionPageView",
                      platforms: [
                          .iOS(.v16), .watchOS(.v9), .macCatalyst(.v16), .macOS(.v13)
                      ],
                      products: [
                          .library(name: "CollectionPageView",
                                   targets: ["CollectionPageView"])
                      ],
                      dependencies: [
                          .package(path: "../LogMacro")
                      ],
                      targets: [
                          .target(name: "CollectionPageView",
                                  dependencies: [
                                      .product(name: "LogMacro", package: "LogMacro")
                                  ])
                      ])

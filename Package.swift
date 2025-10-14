// swift-tools-version: 5.10
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(name: "CollectionPageView",
                      platforms: [
                          .iOS(.v17), .watchOS(.v10), .macCatalyst(.v17), .macOS(.v14)
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

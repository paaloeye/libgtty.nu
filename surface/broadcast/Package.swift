// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.
//
//
//  SPDX-License-Identifier: MIT
//  Copyright (c) 2026 Paal Øye-Strømme
//
//  Package.swift
//  libgtty
//

import PackageDescription

let package = Package(
    name: "gtty-surface-broadcast",
    dependencies: [],
    targets: [
        .executableTarget(
            name: "gtty-surface-broadcast",
            dependencies: []
        ),
        .testTarget(
            name: "gtty-surface-broadcastTests",
            dependencies: ["gtty-surface-broadcast"]
        ),
    ],
    swiftLanguageModes: [.v6]
)

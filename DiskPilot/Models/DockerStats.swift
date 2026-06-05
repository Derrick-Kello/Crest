//
//  DockerStats.swift
//  DiskPilot
//

import Foundation

struct DockerStats {
    var imagesSize: UInt64 = 0
    var containersSize: UInt64 = 0
    var volumesSize: UInt64 = 0
    var reclaimableSize: UInt64 = 0
    var isDockerAvailable: Bool = false
    var rawOutput: String = ""

    var totalSize: UInt64 {
        imagesSize + containersSize + volumesSize
    }

    var formattedTotal: String { DiskUsageModel.formatBytes(totalSize) }
    var formattedReclaimable: String { DiskUsageModel.formatBytes(reclaimableSize) }
}

//
//  EmptyStateViews.swift
//  VVTerm
//

import SwiftUI

struct NoServersEmptyState: View {
    let onAddServer: () -> Void
    var onAddWorkspace: (() -> Void)? = nil
    var requiresWorkspace = false

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 16) {
                if requiresWorkspace {
                    Image(systemName: "folder")
                        .font(.system(size: 48))
                        .foregroundStyle(.tertiary)

                    VStack(spacing: 8) {
                        Text("No Workspaces")
                            .font(.headline)
                            .fontWeight(.semibold)

                        Text("Create a workspace before adding servers")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Image(systemName: "server.rack")
                        .font(.system(size: 48))
                        .foregroundStyle(.tertiary)

                    VStack(spacing: 8) {
                        Text("No Servers")
                            .font(.headline)
                            .fontWeight(.semibold)

                        Text("Add a server to get started")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            if let onAddWorkspace, requiresWorkspace {
                Button(action: onAddWorkspace) {
                    HStack(spacing: 8) {
                        Image(systemName: "folder.badge.plus")
                        Text("Create Workspace")
                            .fontWeight(.medium)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(.tint, in: RoundedRectangle(cornerRadius: 8))
                    .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            } else {
                Button(action: onAddServer) {
                    HStack(spacing: 8) {
                        Image(systemName: "plus.circle.fill")
                        Text("Add Server")
                            .fontWeight(.medium)
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(.tint, in: RoundedRectangle(cornerRadius: 8))
                    .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }
}

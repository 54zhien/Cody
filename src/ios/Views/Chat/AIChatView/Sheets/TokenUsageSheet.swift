//
//  TokenUsageSheet.swift
//  Cody - chat page (AIChatView)
//
//  Token usage of this session (input / output / cache) and its StatRow.
//
//  Map of the AIChatView files: AIChatView/AIChatView.swift.
//

import SwiftUI

// MARK: - Token Usage Sheet

struct TokenUsageSheet: View {
    @ObservedObject var vm: AIChatViewModel
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                let s = vm.sessionTokenStats

                Section {
                    if let window = vm.currentModelContextWindow, window > 0 {
                        let ratio = min(max(Double(s.context) / Double(window), 0), 1)
                        VStack(alignment: .leading, spacing: CodySpacing.sm) {
                            HStack {
                                Text(verbatim: "\(formatted(s.context)) / \(formatted(window))")
                                    .font(CodyTypography.code.monospacedDigit())
                                    .foregroundStyle(CodyColors.textPrimary)
                                Spacer()
                                Text(ratio, format: .percent.precision(.fractionLength(0)))
                                    .font(CodyTypography.labelMedium.monospacedDigit())
                                    .foregroundStyle(CodyColors.textSecondary)
                            }
                            CodyProgressBar(progress: ratio)
                        }
                        .padding(.vertical, CodySpacing.xs)
                        .listRowBackground(CodyColors.bgGroupedSurface)
                        .listRowSeparatorTint(CodyColors.separator)
                    }
                    StatRow(label: "Context Used", value: formatted(s.context), icon: "text.alignleft")
                    if let window = vm.currentModelContextWindow {
                        StatRow(label: "Context Window", value: formatted(window), icon: "arrow.left.and.right")
                    }
                    if let maxOut = vm.currentModelMaxOutputTokens {
                        StatRow(label: "Max Output", value: formatted(maxOut), icon: "arrow.up.to.line")
                    }
                } header: {
                    Text("Context")
                        .font(CodyTypography.sectionHeader)
                        .foregroundStyle(CodyColors.textSecondary)
                }

                if let thinkingInfo = vm.currentModelThinkingInfo {
                    Section {
                        StatRow(label: "Thinking", value: thinkingInfo.enabled ? "On" : "Off", icon: "lightbulb", customIcon: Image("ThinkingIcon"))
                        if thinkingInfo.enabled {
                            StatRow(label: "Level", value: thinkingInfo.level, icon: "slider.horizontal.3")
                        }
                        StatRow(label: "Supported", value: thinkingInfo.supported ? "Yes" : "No", icon: "checkmark.circle")
                    } header: {
                        Text("Thinking")
                            .font(CodyTypography.sectionHeader)
                            .foregroundStyle(CodyColors.textSecondary)
                    }
                }

                Section {
                    let inputTotal = s.input + s.cacheRead + s.cacheWrite
                    StatRow(label: "Input (incl. cache)", value: formatted(inputTotal), icon: "arrow.down.circle")
                    StatRow(label: "Output", value: formatted(s.output), icon: "arrow.up.circle")
                    rawTokenBreakdown(input: s.input, output: s.output, cacheRead: s.cacheRead, cacheWrite: s.cacheWrite)
                } header: {
                    Text("Tokens (Session Total)")
                        .font(CodyTypography.sectionHeader)
                        .foregroundStyle(CodyColors.textSecondary)
                }

                Section {
                    StatRow(label: "Cache Read", value: formatted(s.cacheRead), icon: "arrow.triangle.2.circlepath")
                    StatRow(label: "Cache Write", value: formatted(s.cacheWrite), icon: "square.and.arrow.down")
                    // [T-ios-token-usage-cache-hit-rate] Cache hit rate = cache read
                    // over total input (incl. cache) — the same denominator as the
                    // "Input (incl. cache)" row above (input + cacheRead + cacheWrite).
                    // Shows how much of this session's input was served from cache.
                    let totalInput = s.input + s.cacheRead + s.cacheWrite
                    if totalInput > 0 && s.cacheRead > 0 {
                        let hitRate = Double(s.cacheRead) / Double(totalInput) * 100
                        StatRow(label: "Cache Hit Rate", value: String(format: "%.1f%%", hitRate), icon: "percent")
                    }
                } header: {
                    Text("Cache (Session Total)")
                        .font(CodyTypography.sectionHeader)
                        .foregroundStyle(CodyColors.textSecondary)
                }

                Section {
                    let speed = vm.sessionOutputTokensPerSecond
                    StatRow(label: "Output Speed", value: speed > 0 ? String(format: "%.1f tok/s", speed) : "—", icon: "speedometer")
                } header: {
                    Text("Speed")
                        .font(CodyTypography.sectionHeader)
                        .foregroundStyle(CodyColors.textSecondary)
                }

                Section {
                    StatRow(label: "Total Loops", value: "\(s.loopCount)", icon: "repeat")
                } header: {
                    Text("Agent Loop")
                        .font(CodyTypography.sectionHeader)
                        .foregroundStyle(CodyColors.textSecondary)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(CodyColors.bgGrouped)
            .navigationTitle("Session Token Usage")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                        .font(CodyTypography.labelLarge)
                        .foregroundStyle(CodyColors.textPrimary)
                }
            }
        }
    }

    private func rawTokenBreakdown(input: Int, output: Int, cacheRead: Int, cacheWrite: Int) -> some View {
        let shape = RoundedRectangle(cornerRadius: CodyRadius.control, style: .continuous)
        return Text(verbatim: "in=\(input)  out=\(output)  cache_r=\(cacheRead)  cache_w=\(cacheWrite)")
            .font(CodyTypography.code.monospacedDigit())
            .foregroundStyle(CodyColors.textSecondary)
            .textSelection(.enabled)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, CodySpacing.md)
            .padding(.vertical, CodySpacing.sm)
            .background(shape.fill(CodyColors.bgCodeBlock))
            .overlay {
                shape.strokeBorder(CodyColors.borderLight, lineWidth: CodySpacing.px)
                    .allowsHitTesting(false)
            }
            .listRowBackground(CodyColors.bgGroupedSurface)
            .listRowSeparatorTint(CodyColors.separator)
    }

    private func formatted(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000 { return String(format: "%.1fK", Double(n) / 1_000) }
        return "\(n)"
    }
}

private struct StatRow: View {
    let label: LocalizedStringKey
    let value: String
    let icon: String
    var customIcon: Image?

    var body: some View {
        HStack(spacing: CodySpacing.md) {
            if let customIcon {
                let shape = RoundedRectangle(cornerRadius: CodyRadius.md, style: .continuous)
                customIcon
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(CodyColors.iconPrimary)
                    .frame(width: 14, height: 14)
                    .frame(width: CodyMetrics.Sidebar.iconSize, height: CodyMetrics.Sidebar.iconSize)
                    .background(shape.fill(CodyColors.bgListIcon))
                    .clipShape(shape)
                    .overlay {
                        shape.strokeBorder(CodyColors.borderListIcon, lineWidth: CodySpacing.px)
                            .allowsHitTesting(false)
                    }
                    .accessibilityHidden(true)
            } else {
                CodyListIconBadge(systemImage: icon, tint: .neutral)
            }
            Text(label)
                .font(CodyTypography.bodyLarge)
                .foregroundStyle(CodyColors.textPrimary)
            Spacer(minLength: CodySpacing.sm)
            Text(value)
                .font(CodyTypography.bodyMedium.monospacedDigit())
                .foregroundStyle(CodyColors.textSecondary)
        }
        .frame(minHeight: CodyControlHeight.sm)
        .listRowBackground(CodyColors.bgGroupedSurface)
        .listRowSeparatorTint(CodyColors.separator)
    }
}

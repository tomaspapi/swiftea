import SwiftUI

struct HistoryChartCard: View {
    @Bindable var model: AppModel
    @State private var selectedMetric: MugHistoryMetric = .battery

    private var lineColor: Color {
        switch selectedMetric {
        case .battery:
            .green
        case .temperature:
            .orange
        }
    }

    var body: some View {
        DashboardCard {
            TimelineView(.periodic(from: Date(), by: 60)) { context in
                let now = stableChartNow(from: context.date)
                let windowStart = now.addingTimeInterval(-model.chartTimeframePreference.duration)
                let segments = model.historyChartSegments(metric: selectedMetric, now: now)
                let xAxisTicks = xAxisTickDates(from: windowStart, through: now)
                let yAxisValues = model.historyChartYAxisValues(for: selectedMetric)
                let yDomain = model.historyChartYDomain(for: selectedMetric)

                VStack(spacing: 8) {
                    Picker("", selection: $selectedMetric) {
                        ForEach(MugHistoryMetric.allCases) { metric in
                            Text(metric.title)
                                .tag(metric)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .controlSize(.small)
                    .frame(width: 168)

                    LightweightHistoryLineChart(
                        segments: segments,
                        xAxisTicks: xAxisTicks,
                        yAxisValues: yAxisValues,
                        yDomain: yDomain,
                        windowStart: windowStart,
                        now: now,
                        lineColor: lineColor,
                        yAxisLabel: yAxisLabel(for:),
                        xAxisLabel: model.historyChartTimeLabel(for:),
                        xAxisLabelWidth: model.timeFormatPreference.chartXAxisLabelWidth,
                        xAxisLabelFontSize: model.timeFormatPreference.chartXAxisLabelFontSize,
                        xAxisMeridiemLabelFontSize: model.timeFormatPreference.chartXAxisMeridiemLabelFontSize
                    )
                    .frame(height: 112)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 8)
            }
        }
    }

    private func stableChartNow(from date: Date) -> Date {
        if let chartNowOverride = model.chartNowOverride {
            return chartNowOverride
        }

        let interval = date.timeIntervalSinceReferenceDate
        return Date(timeIntervalSinceReferenceDate: floor(interval / 60) * 60)
    }

    private func xAxisTickDates(from windowStart: Date, through now: Date) -> [Date] {
        let stride = TimeInterval(model.chartTimeframePreference.xAxisStrideMinutes * 60)
        guard stride > 0 else {
            return []
        }

        var ticks: [Date] = []
        var tick = windowStart
        while tick <= now {
            ticks.append(tick)
            tick = tick.addingTimeInterval(stride)
        }
        return ticks
    }

    private func yAxisLabel(for value: Double) -> String {
        switch selectedMetric {
        case .battery:
            "\(Int(value.rounded()))%"
        case .temperature:
            switch model.temperatureUnitPreference {
            case .celsius:
                "\(Int(value.rounded()))°C"
            case .fahrenheit:
                "\(Int(value.rounded()))°F"
            }
        }
    }
}

private struct LightweightHistoryLineChart: View {
    let segments: [MugHistoryChartSegment]
    let xAxisTicks: [Date]
    let yAxisValues: [Double]
    let yDomain: ClosedRange<Double>
    let windowStart: Date
    let now: Date
    let lineColor: Color
    let yAxisLabel: (Double) -> String
    let xAxisLabel: (Date) -> String
    let xAxisLabelWidth: CGFloat
    let xAxisLabelFontSize: CGFloat
    let xAxisMeridiemLabelFontSize: CGFloat

    var body: some View {
        GeometryReader { geometry in
            let layout = ChartLayout(size: geometry.size, xAxisLabelWidth: xAxisLabelWidth)

            ZStack(alignment: .topLeading) {
                Canvas { context, size in
                    let layout = ChartLayout(size: size, xAxisLabelWidth: xAxisLabelWidth)
                    drawGrid(in: &context, layout: layout)
                    drawSegments(in: &context, layout: layout)
                }

                ForEach(yAxisValues, id: \.self) { value in
                    Text(yAxisLabel(value))
                        .font(HistoryChartLayoutMetrics.axisLabelFont)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                        .frame(width: HistoryChartLayoutMetrics.yAxisLabelWidth, alignment: .trailing)
                        .position(
                            x: HistoryChartLayoutMetrics.yAxisLabelWidth / 2,
                            y: yPosition(for: value, layout: layout)
                        )
                }

                ForEach(xAxisTicks, id: \.self) { date in
                    let label = xAxisLabel(date)
                    xAxisTickLabel(label)
                        .position(
                            x: xPosition(for: date, layout: layout),
                            y: layout.plotMaxY + xAxisLabelOffsetY(for: label)
                        )
                }
            }
        }
    }

    @ViewBuilder
    private func xAxisTickLabel(_ label: String) -> some View {
        let parts = label.split(separator: "\n", maxSplits: 1, omittingEmptySubsequences: false)
        if parts.count == 2 {
            VStack(spacing: HistoryChartLayoutMetrics.xAxisLabelLineSpacing) {
                Text(String(parts[0]))
                    .font(.system(size: xAxisLabelFontSize))
                    .monospacedDigit()
                Text(String(parts[1]))
                    .font(.system(size: xAxisMeridiemLabelFontSize))
            }
            .multilineTextAlignment(.center)
            .foregroundStyle(.secondary)
            .frame(width: xAxisLabelWidth, alignment: .center)
        } else {
            Text(label)
                .font(.system(size: xAxisLabelFontSize))
                .monospacedDigit()
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .frame(width: xAxisLabelWidth, alignment: .center)
        }
    }

    private func drawGrid(in context: inout GraphicsContext, layout: ChartLayout) {
        var horizontalGuides = Path()
        for value in yAxisValues {
            let y = yPosition(for: value, layout: layout)
            horizontalGuides.move(to: CGPoint(x: layout.plotMinX, y: y))
            horizontalGuides.addLine(to: CGPoint(x: layout.plotMaxX, y: y))
        }

        context.stroke(
            horizontalGuides,
            with: .color(.secondary.opacity(0.22)),
            style: StrokeStyle(lineWidth: 0.6)
        )

        var verticalGuides = Path()
        for date in xAxisTicks {
            let x = xPosition(for: date, layout: layout)
            verticalGuides.move(to: CGPoint(x: x, y: layout.plotMinY))
            verticalGuides.addLine(to: CGPoint(x: x, y: layout.plotMaxY + HistoryChartLayoutMetrics.verticalGuideOverhang))
        }

        context.stroke(
            verticalGuides,
            with: .color(.secondary.opacity(0.22)),
            style: StrokeStyle(lineWidth: 0.6)
        )
    }

    private func drawSegments(in context: inout GraphicsContext, layout: ChartLayout) {
        for segment in segments {
            guard segment.points.count > 1 else { continue }

            var line = Path()
            for (index, point) in segment.points.enumerated() {
                let mappedPoint = CGPoint(
                    x: xPosition(for: point.timestamp, layout: layout),
                    y: yPosition(for: point.value, layout: layout)
                )

                if index == 0 {
                    line.move(to: mappedPoint)
                } else {
                    line.addLine(to: mappedPoint)
                }
            }

            context.stroke(
                line,
                with: .color(lineColor),
                style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round)
            )
        }
    }

    private func xPosition(for date: Date, layout: ChartLayout) -> CGFloat {
        let duration = max(now.timeIntervalSince(windowStart), 1)
        let ratio = min(max(date.timeIntervalSince(windowStart) / duration, 0), 1)
        return layout.plotMinX + CGFloat(ratio) * layout.plotWidth
    }

    private func yPosition(for value: Double, layout: ChartLayout) -> CGFloat {
        let valueRange = max(yDomain.upperBound - yDomain.lowerBound, 1)
        let ratio = min(max((value - yDomain.lowerBound) / valueRange, 0), 1)
        return layout.plotMaxY - CGFloat(ratio) * layout.plotHeight
    }

    private func xAxisLabelOffsetY(for label: String) -> CGFloat {
        label.contains("\n")
            ? HistoryChartLayoutMetrics.twoLineXAxisLabelOffsetY
            : HistoryChartLayoutMetrics.xAxisLabelOffsetY
    }

    private struct ChartLayout {
        let size: CGSize
        let xAxisLabelWidth: CGFloat

        var plotMinX: CGFloat {
            HistoryChartLayoutMetrics.yAxisLabelWidth
                + HistoryChartLayoutMetrics.yAxisLabelGap
        }

        var plotMaxX: CGFloat {
            max(plotMinX + 1, size.width - xAxisLabelWidth / 2)
        }

        var plotWidth: CGFloat {
            max(plotMaxX - plotMinX, 1)
        }

        var plotMinY: CGFloat {
            2
        }

        var plotMaxY: CGFloat {
            max(plotMinY + 1, size.height - 28)
        }

        var plotHeight: CGFloat {
            max(plotMaxY - plotMinY, 1)
        }
    }
}

private enum HistoryChartLayoutMetrics {
    static let yAxisLabelWidth: CGFloat = 38
    static let yAxisLabelGap: CGFloat = 8
    static let xAxisLabelOffsetY: CGFloat = 21
    static let twoLineXAxisLabelOffsetY: CGFloat = 22
    static let xAxisLabelLineSpacing: CGFloat = -4
    static let verticalGuideOverhang: CGFloat = 8
    static let axisLabelFont = Font.system(size: 10)
}

#Preview {
    HistoryChartCard(model: AppModel.previewConnected())
        .padding()
}

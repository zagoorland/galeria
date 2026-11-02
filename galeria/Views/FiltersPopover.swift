import SwiftUI

struct FiltersPopover: View {
    @Environment(GalleryModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Filters")
                    .font(.headline)
                Spacer()
                Button("Clear All") {
                    model.clearFilters()
                }
                .disabled(!model.sortFilter.filter.isActive)
            }
            .padding(.horizontal, 14)
            .frame(height: 42)
            .overlay(alignment: .bottom) {
                Rectangle().fill(.separator.opacity(0.6)).frame(height: 1)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    filterSection("File Type") {
                        let formats = availableFormats
                        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())],
                                  alignment: .leading, spacing: 6) {
                            ForEach(formats) { format in
                                Toggle(format.displayName, isOn: formatBinding(format))
                                    .toggleStyle(.checkbox)
                            }
                        }
                    }

                    filterSection("Orientation") {
                        Picker("Orientation", selection: orientationBinding) {
                            ForEach(OrientationFilter.allCases) { value in
                                Text(value.displayName).tag(value)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }

                    filterSection("Minimum Dimensions") {
                        HStack(spacing: 10) {
                            Picker("Min Width", selection: widthBinding) {
                                dimensionOptions
                            }
                            .labelsHidden()
                            .frame(width: 100)
                            Text("×").foregroundStyle(.secondary)
                            Picker("Min Height", selection: heightBinding) {
                                dimensionOptions
                            }
                            .labelsHidden()
                            .frame(width: 100)
                            Text("px").font(.caption).foregroundStyle(.secondary)
                            Spacer()
                        }
                    }

                    filterSection("Rating") {
                        Picker("Minimum Rating", selection: minimumRatingBinding) {
                            Text("Any").tag(0)
                            ForEach(1...5, id: \.self) { value in
                                Text("\(value)+").tag(value)
                            }
                        }
                        .labelsHidden()
                        .frame(width: 120)
                    }

                    filterSection("Color Label") {
                        Picker("Color Label", selection: labelBinding) {
                            Text("Any").tag(FinderColorLabel?.none)
                            ForEach(FinderColorLabel.allCases) { label in
                                Text(label.displayName).tag(Optional(label))
                            }
                        }
                        .labelsHidden()
                        .frame(width: 150)
                    }

                    filterSection("Flag") {
                        Picker("Flag", selection: flagBinding) {
                            ForEach(FlagFilter.allCases) { value in
                                Text(value.displayName).tag(value)
                            }
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                    }
                }
                .padding(14)
            }

            HStack {
                Text("Filters apply immediately")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 14)
            .frame(height: 46)
            .overlay(alignment: .top) {
                Rectangle().fill(.separator.opacity(0.6)).frame(height: 1)
            }
        }
        .frame(width: 360, height: 480)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var availableFormats: [ImageFormat] {
        let present = Set(model.folderStore.items.map(\.format))
        let formats = present.isEmpty ? Set(ImageFormat.allCases.filter { $0 != .other }) : present
        return formats.sorted { $0.displayName.localizedStandardCompare($1.displayName) == .orderedAscending }
    }

    private func filterSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            content()
        }
    }

    @ViewBuilder
    private var dimensionOptions: some View {
        Text("Any").tag(0)
        Text("500 px").tag(500)
        Text("1000 px").tag(1000)
        Text("2000 px").tag(2000)
        Text("3000 px").tag(3000)
        Text("4000 px").tag(4000)
        Text("6000 px").tag(6000)
    }

    private func formatBinding(_ format: ImageFormat) -> Binding<Bool> {
        Binding(get: { model.sortFilter.filter.formats.contains(format) },
                set: { enabled in
                    if enabled {
                        model.sortFilter.filter.formats.insert(format)
                    } else {
                        model.sortFilter.filter.formats.remove(format)
                    }
                })
    }

    private var orientationBinding: Binding<OrientationFilter> {
        Binding(get: { model.sortFilter.filter.orientation },
                set: { model.sortFilter.filter.orientation = $0 })
    }

    private var widthBinding: Binding<Int> {
        Binding(get: { model.sortFilter.filter.minimumWidth },
                set: { model.sortFilter.filter.minimumWidth = max(0, $0) })
    }

    private var heightBinding: Binding<Int> {
        Binding(get: { model.sortFilter.filter.minimumHeight },
                set: { model.sortFilter.filter.minimumHeight = max(0, $0) })
    }

    private var minimumRatingBinding: Binding<Int> {
        Binding(get: { model.sortFilter.filter.minimumRating },
                set: { model.sortFilter.filter.minimumRating = $0 })
    }

    private var labelBinding: Binding<FinderColorLabel?> {
        Binding(get: { model.sortFilter.filter.label },
                set: { model.sortFilter.filter.label = $0 })
    }

    private var flagBinding: Binding<FlagFilter> {
        Binding(get: { model.sortFilter.filter.flag },
                set: { model.sortFilter.filter.flag = $0 })
    }
}

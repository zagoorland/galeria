import AppKit
import MapKit
import SwiftUI

struct PhotoMapView: View {
    @Environment(GalleryModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    private var photos: [ImageItem] {
        model.folderStore.items.filter(\.hasLocation)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: "map")
                    .font(.title3)
                    .foregroundStyle(.tint)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Photo Map")
                        .font(.headline)
                    Text("\(photos.count) geotagged \(photos.count == 1 ? "image" : "images") · click a pin to reveal it in the grid")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Close Map")
            }
            .padding(14)
            Divider()

            if photos.isEmpty {
                ContentUnavailableView {
                    Label("No Geotagged Images", systemImage: "mappin.slash")
                } description: {
                    Text("Images with GPS metadata appear here.")
                } actions: {
                    Button("Close") { dismiss() }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                PhotoMapRepresentable(photos: photos) { url in
                    model.jumpToImageInGrid(url)
                    dismiss()
                }
            }
        }
        .frame(minWidth: 720, minHeight: 520)
    }
}

private struct PhotoMapRepresentable: NSViewRepresentable {
    let photos: [ImageItem]
    let onSelect: (URL) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onSelect: onSelect)
    }

    func makeNSView(context: Context) -> MKMapView {
        let map = MKMapView(frame: .zero)
        map.delegate = context.coordinator
        map.isPitchEnabled = false
        map.isRotateEnabled = false
        map.showsCompass = true
        map.showsScale = true
        map.pointOfInterestFilter = .includingAll
        return map
    }

    func updateNSView(_ map: MKMapView, context: Context) {
        context.coordinator.onSelect = onSelect
        let existing = Set(map.annotations.compactMap { ($0 as? PhotoAnnotation)?.url })
        let wanted = Set(photos.map(\.url))
        if existing != wanted {
            map.removeAnnotations(map.annotations)
            for photo in photos {
                guard let latitude = photo.latitude, let longitude = photo.longitude else { continue }
                let annotation = PhotoAnnotation(
                    coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
                    title: photo.name,
                    url: photo.url
                )
                map.addAnnotation(annotation)
            }
        }
        guard !photos.isEmpty else { return }
        let coordinates = photos.compactMap { photo -> CLLocationCoordinate2D? in
            guard let latitude = photo.latitude, let longitude = photo.longitude else { return nil }
            return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        }
        guard let first = coordinates.first else { return }
        var minLat = first.latitude, maxLat = first.latitude
        var minLon = first.longitude, maxLon = first.longitude
        for coordinate in coordinates.dropFirst() {
            minLat = min(minLat, coordinate.latitude)
            maxLat = max(maxLat, coordinate.latitude)
            minLon = min(minLon, coordinate.longitude)
            maxLon = max(maxLon, coordinate.longitude)
        }
        let center = CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2,
                                            longitude: (minLon + maxLon) / 2)
        let span = MKCoordinateSpan(latitudeDelta: max((maxLat - minLat) * 1.4, 0.02),
                                    longitudeDelta: max((maxLon - minLon) * 1.4, 0.02))
        map.setRegion(MKCoordinateRegion(center: center, span: span), animated: false)

        // Trigger the initial region only once per data set.
        context.coordinator.hasFitted = true
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        var onSelect: (URL) -> Void
        var hasFitted = false

        init(onSelect: @escaping (URL) -> Void) {
            self.onSelect = onSelect
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: any MKAnnotation) -> MKAnnotationView? {
            guard let photo = annotation as? PhotoAnnotation else { return nil }
            let identifier = "PhotoPin"
            let view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView
                ?? MKMarkerAnnotationView(annotation: photo, reuseIdentifier: identifier)
            view.annotation = photo
            view.markerTintColor = NSColor.controlAccentColor
            view.glyphImage = NSImage(systemSymbolName: "photo", accessibilityDescription: "Photo")
            view.canShowCallout = true
            view.animatesWhenAdded = true
            return view
        }

        func mapView(_ mapView: MKMapView, didSelect view: MKAnnotationView) {
            guard let photo = view.annotation as? PhotoAnnotation else { return }
            onSelect(photo.url)
        }
    }
}

private final class PhotoAnnotation: NSObject, MKAnnotation {
    let coordinate: CLLocationCoordinate2D
    let title: String?
    let url: URL

    init(coordinate: CLLocationCoordinate2D, title: String, url: URL) {
        self.coordinate = coordinate
        self.title = title
        self.url = url
        super.init()
    }
}

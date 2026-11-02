import MapKit
import SwiftUI

struct PhotoLocationMap: NSViewRepresentable {
    let latitude: Double
    let longitude: Double
    let title: String

    func makeNSView(context: Context) -> MKMapView {
        let map = MKMapView(frame: .zero)
        map.isPitchEnabled = false
        map.isRotateEnabled = false
        map.showsCompass = false
        map.showsScale = false
        map.showsZoomControls = false
        return map
    }

    func updateNSView(_ map: MKMapView, context: Context) {
        map.removeAnnotations(map.annotations)
        let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        let annotation = PhotoMapAnnotation(coordinate: coordinate, title: title)
        map.addAnnotation(annotation)
        let region = MKCoordinateRegion(center: coordinate,
                                        latitudinalMeters: 2400,
                                        longitudinalMeters: 2400)
        map.setRegion(region, animated: false)
    }
}

private final class PhotoMapAnnotation: NSObject, MKAnnotation {
    let coordinate: CLLocationCoordinate2D
    let title: String?

    init(coordinate: CLLocationCoordinate2D, title: String) {
        self.coordinate = coordinate
        self.title = title
        super.init()
    }
}

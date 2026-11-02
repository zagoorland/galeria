import Foundation
import Testing
@testable import galeria

struct FinderTagTests {
    @Test("Ratings are encoded as Finder tags and clamped")
    func ratingEncoding() {
        var tags = FinderTagCodec.applyingRating(4, to: ["Vacation"])
        #expect(FinderTagCodec.rating(from: tags) == 4)
        #expect(tags.contains("Vacation"))
        #expect(tags.contains("Rating 4"))
        tags = FinderTagCodec.applyingRating(2, to: tags)
        #expect(FinderTagCodec.rating(from: tags) == 2)
        #expect(!tags.contains("Rating 4"))
        tags = FinderTagCodec.applyingRating(0, to: tags)
        #expect(FinderTagCodec.rating(from: tags) == 0)
        #expect(FinderTagCodec.rating(from: ["Rating 9", "Rating x"]) == 0)
    }

    @Test("Pick and Reject are mutually exclusive")
    func flagEncoding() {
        var tags = FinderTagCodec.applyingFlag(.pick, to: ["Trip"])
        #expect(FinderTagCodec.isPick(tags))
        #expect(!FinderTagCodec.isReject(tags))
        tags = FinderTagCodec.applyingFlag(.reject, to: tags)
        #expect(!FinderTagCodec.isPick(tags))
        #expect(FinderTagCodec.isReject(tags))
        tags = FinderTagCodec.applyingFlag(.none, to: tags)
        #expect(!FinderTagCodec.isPick(tags))
        #expect(!FinderTagCodec.isReject(tags))
        #expect(tags == ["Trip"])
    }

    @Test("One Finder color label is kept")
    func labelEncoding() {
        let tags = FinderTagCodec.applyingLabel(.green, to: ["Holiday", "Red"])
        #expect(FinderTagCodec.colorLabel(from: tags) == .green)
        #expect(!tags.contains("Red"))
        #expect(tags.contains("Holiday"))
    }

    @Test("Tag canonicalization removes duplicates and empty values")
    func canonical() {
        #expect(FinderTagCodec.canonical(["A", "A", "", "B", "B"]) == ["A", "B"])
    }
}

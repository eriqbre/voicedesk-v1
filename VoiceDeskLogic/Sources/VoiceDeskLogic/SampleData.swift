import Foundation

/// Coastal / Bridget-shaped sample cards for the onboarding tour and UI demo.
public enum SampleData {
    public static let listingAddress = "1842 Beach Drive NE"

    public static func email() -> EmailItem {
        EmailItem(
            fromName: "Jordan Hale",
            fromEmail: "jordan.hale@example.com",
            sentAtLabel: "Today 7:14 AM",
            subject: "Saturday showing at Beach Drive?",
            preview: "Bridget — we can do Saturday morning. Can you confirm 11am at 1842 Beach Drive NE and whether the inspection window still works?",
            filterTag: "Listings",
            relatedListing: listingAddress,
            relatedPeople: ["Jordan Hale", "Priya Shah"]
        )
    }

    public static func listing() -> ListingItem {
        ListingItem(
            priceLabel: "$875,000",
            addressLine: listingAddress,
            cityLine: "St. Petersburg, FL 33704",
            beds: 3,
            baths: 2,
            sqft: 1842,
            status: "Active",
            ownership: "Inferred mine — confirm to claim",
            relatedPeople: ["Jordan Hale · buyer", "Priya Shah · partner"]
        )
    }

    public static func buyer() -> PersonItem {
        PersonItem(
            name: "Jordan Hale",
            roleLabel: "Buyer",
            detail: "Wrote this morning about Saturday 11am.",
            phoneLabel: "(727) 555-0142",
            accentHue: 0.58
        )
    }

    public static func partner() -> PersonItem {
        PersonItem(
            name: "Priya Shah",
            roleLabel: "Showing partner",
            detail: "Coastal — can cover if you’re in Tampa.",
            phoneLabel: "(813) 555-0194",
            accentHue: 0.82
        )
    }

    public static func draftReply() -> DraftConfirmItem {
        DraftConfirmItem(
            actionTitle: "Send reply",
            channel: "Gmail",
            toLine: "Jordan Hale <jordan.hale@example.com>",
            subject: "Re: Saturday showing at Beach Drive?",
            body: "Jordan — Saturday at 11am at 1842 Beach Drive NE works. I’ll meet you out front. Inspection window is still open through Tuesday. Reply if you want Priya there too."
        )
    }

    public static func statute() -> StatuteItem {
        StatuteItem(
            title: "Brokerage relationship disclosure",
            plainLanguage: "Florida requires you to disclose the brokerage relationship you’re operating under (transaction broker, single agent, or no brokerage) before, or at, entering into a listing or representation agreement — and before showing property as a single agent.",
            citation: "Fla. Stat. § 475.278",
            confidence: 86,
            disclaimer: "Not a substitute for a lawyer or your broker of record."
        )
    }

    public static func connectGoogle(isConnected: Bool = false) -> ConnectGoogleItem {
        ConnectGoogleItem(
            isConnected: isConnected,
            statusLine: isConnected ? "Connected" : "Required for a real day"
        )
    }

    public static func calendarEvent() -> CalendarItem {
        CalendarItem(
            providerID: "evt-sample",
            title: "Saturday showing",
            whenLabel: "Sat 11:00 AM",
            location: listingAddress,
            relatedPeople: ["Jordan Hale"],
            notes: "Lockbox on the north railing. Allow 15 minutes to park."
        )
    }

    public static func openTask() -> TaskItem {
        TaskItem(
            providerID: "task-sample",
            title: "Confirm inspection window",
            dueLabel: "Tue",
            notes: "Beach Drive — through Tuesday."
        )
    }

    public static func syncedEmail() -> EmailItem {
        EmailItem(
            providerID: "msg-live-1",
            threadID: "thr-live-1",
            fromName: "Ada Cole",
            fromEmail: "ada.cole@example.com",
            sentAtLabel: "Today 8:02 AM",
            subject: "Inspection questions",
            preview: "Can we walk the punch list before Thursday?",
            filterTag: "Inbox"
        )
    }
}

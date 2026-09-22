import Foundation

/// Whether an error is only a piece of work that was cancelled, rather than a failure worth telling
/// anyone about. SwiftUI cancels a view's `.task` when the view goes away, and each of these view
/// models cancels the request a newer one supersedes; in both cases the right response is silence,
/// not an error surface.
///
/// The check needs both halves: `URLSession` reports its own cancellation as `URLError.cancelled`,
/// never as a `CancellationError`, so testing for one alone would let the other through as a real
/// failure. Getting that wrong in one of three copies is exactly what having three copies invites,
/// which is why there is now one.
func isCancellation(_ error: Error) -> Bool {
    error is CancellationError || (error as? URLError)?.code == .cancelled
}

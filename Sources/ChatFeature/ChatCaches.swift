/// What the chat keeps in memory for the whole process, beyond any one chat screen: generated images, search images
/// and computer_use screenshots. All of it came from the paired computer.
public enum ChatCaches {
    /// Called when the computer is unpaired, revoked or replaced: nothing of the old one stays in memory.
    @MainActor
    public static func clearAll() {
        GeneratedImageCache.shared.removeAll()
        SearchMediaCache.shared.removeAll()
        ComputerUseFrameStore.shared.removeAll()
    }
}

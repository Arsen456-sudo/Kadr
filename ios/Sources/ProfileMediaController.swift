import UIKit

/// Dedicated library keeps the profile overview focused on the creator.
final class ProfileMediaController: UICollectionViewController {
    private let store: LocalStore
    private let profileID: UUID?
    private let section: ProfileSection
    private var clips: [Clip] = []
    var onClip: ((Clip) -> Void)?

    init(store: LocalStore, profileID: UUID?, section: ProfileSection) {
        self.store = store; self.profileID = profileID; self.section = section
        let layout = UICollectionViewCompositionalLayout { _, _ in
            let item = NSCollectionLayoutItem(layoutSize: .init(widthDimension: .fractionalWidth(1), heightDimension: .fractionalHeight(1)))
            let group = NSCollectionLayoutGroup.horizontal(layoutSize: .init(widthDimension: .fractionalWidth(1), heightDimension: .fractionalWidth(0.66)), repeatingSubitem: item, count: 2)
            group.interItemSpacing = .fixed(8)
            let section = NSCollectionLayoutSection(group: group)
            section.interGroupSpacing = 8; section.contentInsets = .init(top: 16, leading: 16, bottom: 24, trailing: 16)
            return section
        }
        super.init(collectionViewLayout: layout)
    }
    required init?(coder: NSCoder) { fatalError("Use init(store:profileID:section:)") }
    override func viewDidLoad() {
        super.viewDidLoad(); title = section.title
        collectionView.backgroundColor = .systemBackground
        collectionView.register(ClipThumbnailCell.self, forCellWithReuseIdentifier: "clip")
        collectionView.topEdgeEffect.style = .soft
    }
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        let own = profileID == store.active?.id
        switch section {
        case .posts: clips = store.allClips.filter { $0.authorID == profileID && (own || !$0.settings.onlyMe) }
        case .saved: clips = own ? store.feed(.saved) : []
        case .liked: clips = own ? store.allClips.filter { store.liked($0) } : []
        case .comments: clips = own ? store.allClips.filter { clip in store.comments(clip).contains { $0.authorID == profileID } } : []
        case .overview: clips = []
        }
        collectionView.reloadData()
        if clips.isEmpty {
            var empty = UIContentUnavailableConfiguration.empty(); empty.text = "Тут поки немає кадрів"
            empty.image = AppSymbol.image(section.symbol); contentUnavailableConfiguration = empty
        } else { contentUnavailableConfiguration = nil }
    }
    override func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int { clips.count }
    override func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: "clip", for: indexPath) as! ClipThumbnailCell
        cell.layer.cornerRadius = 18; cell.clipsToBounds = true; cell.show(clips[indexPath.item], modern: true); return cell
    }
    override func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let clip = clips[indexPath.item]
        if let onClip { onClip(clip) } else { navigationController?.pushViewController(ClipPreviewController(clip: clip, store: store), animated: true) }
    }
}

import UIKit

extension UIViewController {
    func postMenu(_ clip: Clip, store: LocalStore, onChange: (() -> Void)? = nil, previous: (() -> Void)? = nil) -> UIMenu {
        var actions: [UIMenuElement] = [UIAction(title: "Поділитися", image: AppSymbol.image("square.and.arrow.up")) { [weak self] _ in
            self?.present(UIActivityViewController(activityItems: [URL(string: "kadr://post/\(clip.id)")!], applicationActivities: nil), animated: true)
        }, UIAction(title: "До колекції", image: AppSymbol.image("folder.badge.plus")) { [weak self] _ in
            guard let self, store.active != nil else { return }
            let page = ActionListController("До колекції")
            page.rows = store.studio.collections.map { collection in StudioRow(title: collection.title, icon: "bookmark", action: { [weak page] in
                store.addToCollection(clip, collectionID: collection.id); page?.dismiss(animated: true)
            }) }
            page.rows.insert(StudioRow(title: "Нова колекція", icon: "plus", action: { [weak page] in
                page?.prompt("Назва") { title in
                    guard !title.isEmpty else { return }
                    store.changeStudio { $0.collections.append(SavedCollection(title: title, posts: [clip.id], cover: clip.id)) }
                    if !store.bookmarked(clip) { store.toggleReaction(clip, bookmark: true) }; page?.dismiss(animated: true)
                }
            }), at: 0)
            self.present(UINavigationController(rootViewController: page), animated: true)
        }, UIAction(title: "Приватна нотатка", image: AppSymbol.image("note.text")) { [weak self] _ in
            guard let self, store.active != nil else { return }
            let alert = UIAlertController(title: "Нотатка", message: "Видно тільки тобі", preferredStyle: .alert)
            alert.addTextField { $0.text = store.studio.notes[clip.id] }
            alert.addAction(UIAlertAction(title: "Зберегти", style: .default) { _ in store.changeStudio { $0.notes[clip.id] = alert.textFields?.first?.text } })
            alert.addAction(UIAlertAction(title: "Скасувати", style: .cancel)); self.present(alert, animated: true)
        }]
        if let previous { actions.append(UIAction(title: "Попередня публікація", image: AppSymbol.image("arrow.uturn.backward")) { _ in previous() }) }
        actions.append(UIMenu(title: "Тип публікацій", children: [("all", "Усе"), ("video", "Відео"), ("photo", "Фото")].map { value, title in
            UIAction(title: title, state: store.studio.preferences.mediaFilter == value ? .on : .off) { _ in store.changeStudio { $0.preferences.mediaFilter = value }; onChange?() }
        }))
        actions.append(UIMenu(title: "Швидкість", children: [Float(0.5), 0.75, 1, 1.25, 1.5, 2].map { rate in
            UIAction(title: "\(rate)×", state: store.studio.preferences.playbackRate == rate ? .on : .off) { _ in store.changeStudio { $0.preferences.playbackRate = rate }; onChange?() }
        }))
        actions.append(UIAction(title: "Не цікаво", image: AppSymbol.image("hand.thumbsdown")) { _ in store.changeStudio { $0.preferences.hiddenPosts.insert(clip.id) }; onChange?() })
        actions.append(UIAction(title: "Більше такого", image: AppSymbol.image("sparkles")) { _ in
            let tags = clip.settings.tags.split(whereSeparator: { $0.isWhitespace || $0 == "#" }).map { $0.lowercased() }
            store.changeStudio { $0.preferences.preferredTags.formUnion(tags) }; onChange?()
        })
        if let author = clip.authorID, author != store.active?.id {
            actions.append(UIAction(title: "Приховати автора", image: AppSymbol.image("eye.slash")) { _ in store.changeStudio { $0.preferences.hiddenAuthors.insert(author) }; onChange?() })
            actions.append(UIAction(title: "Заблокувати автора", image: AppSymbol.image("person.slash"), attributes: .destructive) { _ in store.changeStudio { $0.preferences.blocked.insert(author) }; onChange?() })
        }
        if store.active?.id == clip.authorID {
            actions.append(UIAction(title: "Редагувати публікацію", image: AppSymbol.image("pencil")) { [weak self] _ in
                self?.present(UINavigationController(rootViewController: PostEditController(store: store, clip: clip)), animated: true)
            })
        }
        return UIMenu(children: actions)
    }
}

import PhotosUI
import UIKit

final class AccountController: FormController {
    private let store: LocalStore
    var onAuthenticated: (() -> Void)?
    var onGuest: (() -> Void)?

    init(store: LocalStore) {
        self.store = store
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("Use init(store:)") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Профіль у Кадрі"
        content.addArrangedSubview(makeLabel(.body, text: "Створи локальний профіль, щоб ставити лайки, коментувати й додавати відео.", color: .secondaryLabel))
        content.addArrangedSubview(textButton("Створити локальний акаунт", symbol: "person.badge.plus", prominent: true) { [weak self] in
            guard let self else { return }
            let photo = AccountPhotoController(store: self.store)
            photo.onAuthenticated = { [weak self] in self?.onAuthenticated?() }
            self.navigationController?.pushViewController(photo, animated: true)
        })
        for profile in store.profiles {
            content.addArrangedSubview(textButton("Продовжити як @\(profile.handle)") { [weak self] in
                guard let self else { return }
                self.store.select(profile.id)
                if self.store.active?.id == profile.id {
                    self.onAuthenticated?()
                } else {
                    self.showMessage(self.store.errorMessage ?? "Не вдалося відкрити профіль.")
                    self.store.errorMessage = nil
                }
            })
        }
        content.addArrangedSubview(textButton("Дивитися без акаунта") { [weak self] in
            self?.onGuest?()
        })
    }
}

private final class AccountPhotoController: FormController, PHPickerViewControllerDelegate {
    let store: LocalStore
    private let avatar = avatarView()
    private var photo: Data?
    private var generation = 0
    var onAuthenticated: (() -> Void)?

    init(store: LocalStore) {
        self.store = store
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("Use init(store:)") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Фото профілю"
        let well = UIView()
        avatar.translatesAutoresizingMaskIntoConstraints = false
        well.addSubview(avatar)
        NSLayoutConstraint.activate([
            avatar.centerXAnchor.constraint(equalTo: well.centerXAnchor),
            avatar.topAnchor.constraint(equalTo: well.topAnchor),
            avatar.bottomAnchor.constraint(equalTo: well.bottomAnchor),
            avatar.widthAnchor.constraint(equalTo: avatar.heightAnchor),
            avatar.heightAnchor.constraint(equalToConstant: 96)
        ])
        content.addArrangedSubview(well)
        content.addArrangedSubview(textButton("Вибрати фото", symbol: "photo") { [weak self] in
            guard let self else { return }
            var configuration = PHPickerConfiguration()
            configuration.filter = .images
            let picker = PHPickerViewController(configuration: configuration)
            picker.delegate = self
            self.present(picker, animated: true)
        })
        content.addArrangedSubview(textButton("Далі", prominent: true) { [weak self] in self?.advance() })
        content.addArrangedSubview(textButton("Пропустити фото") { [weak self] in
            self?.photo = nil
            self?.avatar.image = AppSymbol.image( "person.crop.circle.fill")
            self?.advance()
        })
    }

    private func advance() {
        generation += 1
        let handle = AccountHandleController(store: store, avatar: photo)
        handle.onAuthenticated = { [weak self] in self?.onAuthenticated?() }
        navigationController?.pushViewController(handle, animated: true)
    }

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard let provider = results.first?.itemProvider else { return }
        generation += 1
        let request = generation
        provider.loadObject(ofClass: UIImage.self) { [weak self] object, _ in
            DispatchQueue.main.async {
                guard let self, self.generation == request else { return }
                guard let image = object as? UIImage, image.size.width > 0, image.size.height > 0 else {
                    self.showMessage("Не вдалося відкрити фото.")
                    return
                }
                let size = CGSize(width: 300, height: 300)
                let scale = max(size.width / image.size.width, size.height / image.size.height)
                let width = image.size.width * scale
                let height = image.size.height * scale
                let rendered = UIGraphicsImageRenderer(size: size).jpegData(withCompressionQuality: 0.82) { _ in
                    image.draw(in: CGRect(x: (size.width - width) / 2, y: (size.height - height) / 2,
                                          width: width, height: height))
                }
                self.avatar.image = UIImage(data: rendered)
                self.photo = rendered
            }
        }
    }
}

private final class AccountHandleController: FormController {
    private let store: LocalStore
    private let avatar: Data?
    private let field = UITextField()
    var onAuthenticated: (() -> Void)?

    init(store: LocalStore, avatar: Data?) {
        self.store = store
        self.avatar = avatar
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("Use init(store:avatar:)") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Нікнейм"
        content.addArrangedSubview(makeLabel(.body, text: "За @нікнеймом інші зможуть знайти твій профіль."))
        field.borderStyle = .roundedRect
        field.placeholder = "@нікнейм"
        field.accessibilityIdentifier = "account.handle"
        field.autocapitalizationType = .none
        field.autocorrectionType = .no
        field.keyboardType = .asciiCapable
        field.font = .preferredFont(forTextStyle: .body)
        field.adjustsFontForContentSizeCategory = true
        field.returnKeyType = .next
        field.addAction(UIAction { [weak self] _ in self?.advance() }, for: .editingDidEndOnExit)
        content.addArrangedSubview(field)
        content.addArrangedSubview(textButton("Далі", prominent: true) { [weak self] in self?.advance() })
    }

    private func advance() {
        let value = field.text ?? ""
        if let error = store.validate(handle: value) { showMessage(error); return }
        field.resignFirstResponder()
        let name = AccountNameController(store: store, handle: value, avatar: avatar)
        name.onAuthenticated = { [weak self] in self?.onAuthenticated?() }
        navigationController?.pushViewController(name, animated: true)
    }
}

private final class AccountNameController: FormController {
    private let store: LocalStore
    private let handle: String
    private let avatar: Data?
    private let name = UITextField()
    private let bio = UITextField()
    var onAuthenticated: (() -> Void)?

    init(store: LocalStore, handle: String, avatar: Data?) {
        self.store = store
        self.handle = handle
        self.avatar = avatar
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("Use init(store:handle:avatar:)") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Твоє ім’я"
        for field in [name, bio] {
            field.borderStyle = .roundedRect
            field.font = .preferredFont(forTextStyle: .body)
            field.adjustsFontForContentSizeCategory = true
            content.addArrangedSubview(field)
        }
        name.placeholder = "Ім’я"
        name.accessibilityIdentifier = "account.name"
        bio.placeholder = "Опис профілю"
        content.addArrangedSubview(textButton("Завершити", prominent: true) { [weak self] in
            guard let self else { return }
            if let error = self.store.register(handle: self.handle, name: String((self.name.text ?? "").prefix(60)),
                                               bio: String((self.bio.text ?? "").prefix(200)), avatar: self.avatar) {
                self.showMessage(error)
                self.store.errorMessage = nil
            } else {
                self.onAuthenticated?()
            }
        })
    }
}

func avatarView(_ data: Data? = nil) -> UIImageView {
    let avatar = UIImageView(image: data.flatMap { UIImage(data: $0) } ?? AppSymbol.image( "person.crop.circle.fill"))
    avatar.contentMode = .scaleAspectFill
    avatar.tintColor = .kadrPeach
    avatar.clipsToBounds = true
    avatar.isAccessibilityElement = false
    return avatar
}

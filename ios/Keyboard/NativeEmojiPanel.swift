import UIKit

/// Local Unicode input. Uses the platform emoji font and never reads the document.
@MainActor final class NativeEmojiPanel: UIView {
    var onInput: ((String) -> Void)?
    var onDelete: (() -> Void)?
    var onBack: (() -> Void)?
    private let categories = UIStackView()
    private let scroll = UIScrollView()
    private let grid = UIStackView()
    private let footer = UIStackView()
    private let back = UIButton(type: .system)
    private let delete = UIButton(type: .system)
    private var category = 0
    private var columns = 0
    private var headerHeight: NSLayoutConstraint!
    private var footerHeight: NSLayoutConstraint!
    private static let groups = EmojiCatalog.groups
    override init(frame: CGRect) {
        super.init(frame: frame)
        accessibilityIdentifier = "emoji-panel"
        let layout = UIStackView(arrangedSubviews: [categories, scroll, footer])
        layout.axis = .vertical; layout.spacing = 4; layout.translatesAutoresizingMaskIntoConstraints = false
        addSubview(layout)
        NSLayoutConstraint.activate([layout.leadingAnchor.constraint(equalTo: leadingAnchor), layout.trailingAnchor.constraint(equalTo: trailingAnchor), layout.topAnchor.constraint(equalTo: topAnchor), layout.bottomAnchor.constraint(equalTo: bottomAnchor)])
        categories.distribution = .fillEqually; categories.spacing = 2
        headerHeight = categories.heightAnchor.constraint(equalToConstant: 44); headerHeight.isActive = true
        grid.axis = .vertical; grid.spacing = 4; grid.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(grid); scroll.alwaysBounceVertical = true
        NSLayoutConstraint.activate([grid.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor), grid.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor), grid.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor), grid.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor), grid.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor)])
        for (index, group) in Self.groups.enumerated() {
            let button = UIButton(type: .system)
            button.setTitle(group.0, for: .normal); button.titleLabel?.font = .systemFont(ofSize: 25)
            button.accessibilityLabel = L(group.1); button.accessibilityIdentifier = "emoji-category-\(index)"
            button.layer.cornerRadius = 8
            button.addAction(UIAction { [weak self] _ in self?.select(index) }, for: .touchUpInside)
            categories.addArrangedSubview(button)
        }
        back.accessibilityIdentifier = "emoji-back"; back.tintColor = Palette.ink
        back.backgroundColor = Palette.specialKey; back.layer.cornerRadius = 8
        back.addAction(UIAction { [weak self] _ in self?.onBack?() }, for: .touchUpInside)
        delete.setImage(UIImage(systemName: "delete.left"), for: .normal); delete.tintColor = Palette.ink
        delete.accessibilityLabel = L("삭제"); delete.accessibilityIdentifier = "emoji-delete"
        delete.backgroundColor = Palette.specialKey; delete.layer.cornerRadius = 8
        delete.addAction(UIAction { [weak self] _ in self?.onDelete?() }, for: .touchUpInside)
        let title = UILabel(); title.text = L("이모지"); title.textColor = Palette.secondary; title.textAlignment = .center
        footer.addArrangedSubview(back); footer.addArrangedSubview(title); footer.addArrangedSubview(delete); footer.spacing = 8
        NSLayoutConstraint.activate([back.widthAnchor.constraint(equalToConstant: 64), delete.widthAnchor.constraint(equalTo: back.widthAnchor)])
        footerHeight = footer.heightAnchor.constraint(equalToConstant: 44); footerHeight.isActive = true
        select(0)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func configure(backTitle: String, compact: Bool) {
        back.setTitle(backTitle, for: .normal); back.accessibilityLabel = L("자판으로 돌아가기")
        headerHeight.constant = compact ? 32 : 44; footerHeight.constant = compact ? 32 : 44
    }
    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0 else { return }
        let count = max(1, Int(bounds.width / 45))
        if count != columns { columns = count; render() }
    }
    private func select(_ index: Int) {
        category = index
        for (i, view) in categories.arrangedSubviews.enumerated() {
            view.backgroundColor = i == index ? Palette.softAccent : .clear
            view.accessibilityTraits = i == index ? [.button, .selected] : .button
        }
        render(); scroll.setContentOffset(.zero, animated: false)
    }
    private func render() {
        guard columns > 0 else { return }
        grid.arrangedSubviews.forEach { grid.removeArrangedSubview($0); $0.removeFromSuperview() }
        let emoji = Self.groups[category].2.split(separator: " ").map(String.init), width = max(1, columns)
        for start in stride(from: 0, to: emoji.count, by: width) {
            let row = UIStackView(); row.spacing = 4; row.distribution = .fillEqually
            for offset in 0..<width {
                let button = UIButton(type: .system); button.titleLabel?.font = .systemFont(ofSize: 30)
                if start + offset < emoji.count {
                    let value = emoji[start + offset]
                    button.setTitle(value, for: .normal); button.accessibilityLabel = value; button.accessibilityIdentifier = "emoji-" + value
                    button.addAction(UIAction { [weak self] _ in self?.onInput?(value) }, for: .touchUpInside)
                } else { button.isEnabled = false; button.isAccessibilityElement = false }
                row.addArrangedSubview(button)
            }
            row.heightAnchor.constraint(equalToConstant: 44).isActive = true
            grid.addArrangedSubview(row)
        }
    }
}

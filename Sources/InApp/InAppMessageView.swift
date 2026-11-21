import UIKit

/// The built-in in-app message display, drawn like the Console's preview (Push › In-app):
/// - modal: centred card over a dimmed app, image 2:1, buttons stacked;
/// - banner: slim bar at the top or the bottom (the message's position), small square image, buttons in the bar,
///   the app stays usable;
/// - fullscreen: the whole screen, image on the upper part, buttons at the bottom;
/// - card: at the bottom without dimming, image 3:1, buttons side by side.
/// Close button on the top corner of the panel (left for right-to-left text). The message's own colours win.
public class InAppMessageView: UIView {
    private let message: InAppMessage
    private let content: InAppMessageContent
    private var onButtonClick: ((InAppButton) -> Void)?
    private var onDismiss: (() -> Void)?
    private var dismissed = false

    /// Image width : height, as in the Console.
    static let modalImageRatio: CGFloat = 2
    static let fullscreenImageRatio: CGFloat = 2
    static let cardImageRatio: CGFloat = 3

    private static let primary = UIColor(red: 0x1C / 255.0, green: 0x72 / 255.0, blue: 0xC8 / 255.0, alpha: 1)
    private static let destructive = UIColor(red: 0xDC / 255.0, green: 0x26 / 255.0, blue: 0x26 / 255.0, alpha: 1)

    private lazy var bg: UIColor = InAppMessageView.parseColor(content.backgroundColor) ?? .white
    private lazy var fg: UIColor = InAppMessageView.parseColor(content.textColor)
        ?? UIColor(red: 0x18 / 255.0, green: 0x18 / 255.0, blue: 0x1B / 255.0, alpha: 1)
    private lazy var rtl: Bool = InAppMessageView.isRightToLeft(content)

    /// The panel (card, bar or page); touches outside it reach the app for banner and card.
    private let shadowView = UIView()
    private let panel = UIView()

    // MARK: - Initialization

    public init(message: InAppMessage, content: InAppMessageContent) {
        self.message = message
        self.content = content
        super.init(frame: .zero)
        semanticContentAttribute = rtl ? .forceRightToLeft : .forceLeftToRight
        setupView()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Public Methods

    public static func show(
        in viewController: UIViewController,
        message: InAppMessage,
        content: InAppMessageContent,
        onButtonClick: @escaping (InAppButton) -> Void,
        onDismiss: @escaping () -> Void
    ) -> InAppMessageView {
        let view = InAppMessageView(message: message, content: content)
        view.onButtonClick = onButtonClick
        view.onDismiss = onDismiss

        view.translatesAutoresizingMaskIntoConstraints = false
        viewController.view.addSubview(view)

        NSLayoutConstraint.activate([
            view.leadingAnchor.constraint(equalTo: viewController.view.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: viewController.view.trailingAnchor),
            view.topAnchor.constraint(equalTo: viewController.view.topAnchor),
            view.bottomAnchor.constraint(equalTo: viewController.view.bottomAnchor)
        ])

        view.animateIn()
        return view
    }

    /// Closes the message (no callback: the caller decided).
    public func dismiss() {
        guard !dismissed else { return }
        dismissed = true
        animateOut { [weak self] in
            self?.removeFromSuperview()
        }
    }

    /// Right-to-left when the phone's language is, or the text itself is (a Farsi app's own words).
    static func isRightToLeft(_ content: InAppMessageContent, locale: Locale = .current) -> Bool {
        if let code = locale.languageCode, Locale.characterDirection(forLanguage: code) == .rightToLeft { return true }
        return (content.title + content.body).unicodeScalars.contains { (0x0590...0x08FF).contains($0.value) }
    }

    /// Banner and card leave the rest of the screen to the app.
    public override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        switch message.type {
        case .banner, .card:
            return shadowView.frame.contains(point)
        case .modal, .fullscreen:
            return super.point(inside: point, with: event)
        }
    }

    // MARK: - Setup

    private func setupView() {
        shadowView.translatesAutoresizingMaskIntoConstraints = false
        shadowView.layer.shadowColor = UIColor.black.cgColor
        shadowView.layer.shadowOpacity = 0.28
        shadowView.layer.shadowRadius = 14
        shadowView.layer.shadowOffset = CGSize(width: 0, height: 6)
        panel.translatesAutoresizingMaskIntoConstraints = false
        panel.backgroundColor = bg
        panel.clipsToBounds = true
        panel.semanticContentAttribute = semanticContentAttribute
        shadowView.addSubview(panel)
        pin(panel, to: shadowView)
        addSubview(shadowView)

        switch message.type {
        case .modal: setupModal()
        case .banner: setupBanner()
        case .fullscreen: setupFullscreen()
        case .card: setupCard()
        }
    }

    private func setupModal() {
        backgroundColor = UIColor.black.withAlphaComponent(0.45)
        let tap = UITapGestureRecognizer(target: self, action: #selector(closeTapped))
        tap.delegate = self
        addGestureRecognizer(tap)
        panel.layer.cornerRadius = 16

        let column = verticalStack()
        if let url = content.imageUrl { column.addArrangedSubview(imageView(url, ratio: InAppMessageView.modalImageRatio)) }
        column.addArrangedSubview(textBlock(titleSize: 16, bodySize: 13.5))
        column.addArrangedSubview(buttons(row: false) ?? spacer(12))
        panel.addSubview(column)
        pin(column, to: panel)
        addRoundClose(top: panel.topAnchor, constant: 8)

        NSLayoutConstraint.activate([
            shadowView.centerXAnchor.constraint(equalTo: centerXAnchor),
            shadowView.centerYAnchor.constraint(equalTo: centerYAnchor),
            shadowView.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 18),
            shadowView.widthAnchor.constraint(lessThanOrEqualToConstant: 420),
            shadowView.topAnchor.constraint(greaterThanOrEqualTo: safeAreaLayoutGuide.topAnchor, constant: 16)
        ])
        let wide = shadowView.widthAnchor.constraint(equalTo: widthAnchor, constant: -36)
        wide.priority = .defaultHigh
        wide.isActive = true
    }

    private func setupBanner() {
        backgroundColor = .clear
        panel.layer.cornerRadius = 14
        let bar = UIStackView()
        bar.axis = .horizontal
        bar.alignment = .center
        bar.spacing = 8
        bar.isLayoutMarginsRelativeArrangement = true
        bar.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 10, leading: 10, bottom: 10, trailing: 6)
        bar.translatesAutoresizingMaskIntoConstraints = false

        if let url = content.imageUrl {
            let image = imageView(url, ratio: 1)
            image.layer.cornerRadius = 8
            image.widthAnchor.constraint(equalToConstant: 40).isActive = true
            bar.addArrangedSubview(image)
        }
        let texts = verticalStack()
        texts.spacing = 2
        texts.addArrangedSubview(label(content.title, size: 14, bold: true, lines: 1))
        if !content.body.isEmpty { texts.addArrangedSubview(label(content.body, size: 12, alpha: 0.8, lines: 2)) }
        texts.setContentHuggingPriority(.defaultLow, for: .horizontal)
        texts.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        bar.addArrangedSubview(texts)
        for button in content.buttons { bar.addArrangedSubview(makeButton(button, compact: true)) }
        bar.addArrangedSubview(plainClose())
        panel.addSubview(bar)
        pin(bar, to: panel)

        let bottom = content.position == "bottom"
        NSLayoutConstraint.activate([
            shadowView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            shadowView.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
            bottom
                ? shadowView.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -12)
                : shadowView.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 8)
        ])
        let swipe = UISwipeGestureRecognizer(target: self, action: #selector(closeTapped))
        swipe.direction = bottom ? .down : .up
        shadowView.addGestureRecognizer(swipe)
    }

    private func setupFullscreen() {
        backgroundColor = .clear
        shadowView.layer.shadowOpacity = 0
        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.alwaysBounceVertical = false
        scroll.contentInsetAdjustmentBehavior = .never
        let page = verticalStack()
        if let url = content.imageUrl {
            page.addArrangedSubview(imageView(url, ratio: InAppMessageView.fullscreenImageRatio))
        } else {
            page.addArrangedSubview(spacer(56))
        }
        page.addArrangedSubview(textBlock(titleSize: 22, bodySize: 15, top: 18))
        scroll.addSubview(page)
        panel.addSubview(scroll)

        let actions = buttons(row: false) ?? spacer(16)
        actions.translatesAutoresizingMaskIntoConstraints = false
        panel.addSubview(actions)

        NSLayoutConstraint.activate([
            page.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            page.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            page.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            page.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            page.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor),
            scroll.topAnchor.constraint(equalTo: panel.topAnchor),
            scroll.leadingAnchor.constraint(equalTo: panel.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: panel.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: actions.topAnchor),
            actions.leadingAnchor.constraint(equalTo: panel.leadingAnchor),
            actions.trailingAnchor.constraint(equalTo: panel.trailingAnchor),
            actions.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -8),
            shadowView.topAnchor.constraint(equalTo: topAnchor),
            shadowView.bottomAnchor.constraint(equalTo: bottomAnchor),
            shadowView.leadingAnchor.constraint(equalTo: leadingAnchor),
            shadowView.trailingAnchor.constraint(equalTo: trailingAnchor)
        ])
        addRoundClose(top: safeAreaLayoutGuide.topAnchor, constant: 10)
    }

    private func setupCard() {
        backgroundColor = .clear
        panel.layer.cornerRadius = 16
        let column = verticalStack()
        if let url = content.imageUrl { column.addArrangedSubview(imageView(url, ratio: InAppMessageView.cardImageRatio)) }
        column.addArrangedSubview(textBlock(titleSize: 15, bodySize: 13))
        column.addArrangedSubview(buttons(row: true) ?? spacer(12))
        panel.addSubview(column)
        pin(column, to: panel)
        addRoundClose(top: panel.topAnchor, constant: 8)

        NSLayoutConstraint.activate([
            shadowView.centerXAnchor.constraint(equalTo: centerXAnchor),
            shadowView.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 10),
            shadowView.widthAnchor.constraint(lessThanOrEqualToConstant: 480),
            shadowView.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -16)
        ])
        let wide = shadowView.widthAnchor.constraint(equalTo: widthAnchor, constant: -20)
        wide.priority = .defaultHigh
        wide.isActive = true
        let swipe = UISwipeGestureRecognizer(target: self, action: #selector(closeTapped))
        swipe.direction = .down
        shadowView.addGestureRecognizer(swipe)
    }

    // MARK: - Building blocks

    private func pin(_ view: UIView, to parent: UIView) {
        view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: parent.topAnchor),
            view.bottomAnchor.constraint(equalTo: parent.bottomAnchor),
            view.leadingAnchor.constraint(equalTo: parent.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: parent.trailingAnchor)
        ])
    }

    private func verticalStack() -> UIStackView {
        let stack = UIStackView()
        stack.axis = .vertical
        stack.alignment = .fill
        stack.semanticContentAttribute = semanticContentAttribute
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }

    private func spacer(_ height: CGFloat) -> UIView {
        let view = UIView()
        view.heightAnchor.constraint(equalToConstant: height).isActive = true
        return view
    }

    private func label(_ text: String, size: CGFloat, bold: Bool = false, alpha: CGFloat = 1, lines: Int = 0) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = bold ? .boldSystemFont(ofSize: size) : .systemFont(ofSize: size)
        label.textColor = fg.withAlphaComponent(alpha)
        label.numberOfLines = lines
        label.lineBreakMode = lines == 0 ? .byWordWrapping : .byTruncatingTail
        label.textAlignment = .natural
        label.semanticContentAttribute = semanticContentAttribute
        return label
    }

    /// Title and body, as the Console's preview: bold title, body slightly faded.
    private func textBlock(titleSize: CGFloat, bodySize: CGFloat, top: CGFloat = 12) -> UIStackView {
        let stack = verticalStack()
        stack.spacing = 6
        stack.isLayoutMarginsRelativeArrangement = true
        stack.directionalLayoutMargins = NSDirectionalEdgeInsets(top: top, leading: 14, bottom: 4, trailing: 14)
        if !content.title.isEmpty { stack.addArrangedSubview(label(content.title, size: titleSize, bold: true)) }
        if !content.body.isEmpty { stack.addArrangedSubview(label(content.body, size: bodySize, alpha: 0.85)) }
        return stack
    }

    private func imageView(_ link: String, ratio: CGFloat) -> UIImageView {
        let view = UIImageView()
        view.contentMode = .scaleAspectFill
        view.clipsToBounds = true
        view.backgroundColor = UIColor.black.withAlphaComponent(0.08)
        view.translatesAutoresizingMaskIntoConstraints = false
        view.heightAnchor.constraint(equalTo: view.widthAnchor, multiplier: 1 / ratio).isActive = true
        if let url = URL(string: link) {
            URLSession.shared.dataTask(with: url) { data, _, _ in
                guard let data = data, let image = UIImage(data: data) else { return }
                DispatchQueue.main.async {
                    view.image = image
                    view.backgroundColor = .clear
                }
            }.resume()
        }
        return view
    }

    /// Buttons as in the Console: stacked (modal, full screen) or side by side (card). nil without buttons.
    private func buttons(row: Bool) -> UIStackView? {
        guard !content.buttons.isEmpty else { return nil }
        let stack = UIStackView()
        stack.axis = row ? .horizontal : .vertical
        stack.distribution = row ? .fillEqually : .fill
        stack.spacing = 6
        stack.semanticContentAttribute = semanticContentAttribute
        stack.isLayoutMarginsRelativeArrangement = true
        stack.directionalLayoutMargins = NSDirectionalEdgeInsets(top: 10, leading: 14, bottom: 14, trailing: 14)
        for button in content.buttons { stack.addArrangedSubview(makeButton(button, compact: false)) }
        return stack
    }

    private func makeButton(_ config: InAppButton, compact: Bool) -> UIButton {
        let button = UIButton(type: .system)
        button.setTitle(config.text, for: .normal)
        button.titleLabel?.lineBreakMode = .byTruncatingTail
        button.tag = content.buttons.firstIndex(where: { $0.id == config.id }) ?? 0
        button.addTarget(self, action: #selector(buttonTapped(_:)), for: .touchUpInside)
        let boxed = config.style == .primary || config.style == .secondary
        let size: CGFloat = compact ? 12.5 : 14
        button.titleLabel?.font = boxed ? .boldSystemFont(ofSize: size) : .systemFont(ofSize: size, weight: .medium)
        button.contentEdgeInsets = UIEdgeInsets(top: compact ? 4 : 8, left: 10, bottom: compact ? 4 : 8, right: 10)
        button.layer.cornerRadius = 9
        if !compact { button.heightAnchor.constraint(greaterThanOrEqualToConstant: boxed ? 40 : 32).isActive = true }
        switch config.style {
        case .primary:
            button.backgroundColor = InAppMessageView.primary
            button.setTitleColor(.white, for: .normal)
        case .secondary:
            button.backgroundColor = .clear
            button.setTitleColor(fg.withAlphaComponent(0.85), for: .normal)
            button.layer.borderWidth = 1
            button.layer.borderColor = fg.withAlphaComponent(0.85).cgColor
        case .text:
            button.backgroundColor = .clear
            button.setTitleColor(fg.withAlphaComponent(0.8), for: .normal)
        case .destructive:
            button.backgroundColor = .clear
            button.setTitleColor(InAppMessageView.destructive, for: .normal)
        }
        button.setContentCompressionResistancePriority(.required, for: .horizontal)
        return button
    }

    /// Round close button on the panel's top corner (trailing: left in right-to-left).
    private func addRoundClose(top: NSLayoutYAxisAnchor, constant: CGFloat) {
        let close = UIButton(type: .custom)
        close.setTitle("✕", for: .normal)
        close.setTitleColor(.white, for: .normal)
        close.titleLabel?.font = .systemFont(ofSize: 13, weight: .semibold)
        close.backgroundColor = UIColor.black.withAlphaComponent(0.35)
        close.layer.cornerRadius = 14
        close.accessibilityLabel = NSLocalizedString("Close", comment: "")
        close.translatesAutoresizingMaskIntoConstraints = false
        close.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        panel.addSubview(close)
        NSLayoutConstraint.activate([
            close.widthAnchor.constraint(equalToConstant: 28),
            close.heightAnchor.constraint(equalToConstant: 28),
            close.topAnchor.constraint(equalTo: top, constant: constant),
            close.trailingAnchor.constraint(equalTo: panel.trailingAnchor, constant: -8)
        ])
    }

    private func plainClose() -> UIButton {
        let close = UIButton(type: .system)
        close.setTitle("✕", for: .normal)
        close.setTitleColor(fg.withAlphaComponent(0.7), for: .normal)
        close.titleLabel?.font = .systemFont(ofSize: 14)
        close.accessibilityLabel = NSLocalizedString("Close", comment: "")
        close.widthAnchor.constraint(equalToConstant: 32).isActive = true
        close.heightAnchor.constraint(equalToConstant: 32).isActive = true
        close.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        return close
    }

    // MARK: - Actions

    @objc private func buttonTapped(_ sender: UIButton) {
        guard content.buttons.indices.contains(sender.tag) else { return }
        onButtonClick?(content.buttons[sender.tag])
    }

    @objc private func closeTapped() {
        guard !dismissed else { return }
        dismiss()
        onDismiss?()
    }

    // MARK: - Animation

    private func animateIn() {
        let offset: CGFloat
        switch message.type {
        case .banner: offset = content.position == "bottom" ? 40 : -40
        case .card: offset = 40
        default: offset = 0
        }
        // Lay out first: a first layout inside the animation block would also animate every label and button
        // from a zero frame (text flying in from the corner).
        superview?.layoutIfNeeded()
        alpha = 0
        shadowView.transform = message.type == .modal
            ? CGAffineTransform(scaleX: 0.92, y: 0.92)
            : CGAffineTransform(translationX: 0, y: offset)
        UIView.animate(withDuration: 0.22, delay: 0, options: .curveEaseOut) {
            self.alpha = 1
            self.shadowView.transform = .identity
        }
    }

    private func animateOut(completion: @escaping () -> Void) {
        UIView.animate(withDuration: 0.16) {
            self.alpha = 0
        } completion: { _ in
            completion()
        }
    }

    // MARK: - Helpers

    /// `#RRGGBB` or `#AARRGGBB`.
    static func parseColor(_ hex: String?) -> UIColor? {
        guard let hex = hex?.trimmingCharacters(in: .whitespacesAndNewlines), !hex.isEmpty else { return nil }
        let clean = hex.replacingOccurrences(of: "#", with: "")
        guard clean.count == 6 || clean.count == 8, let value = UInt64(clean, radix: 16) else { return nil }
        let a = clean.count == 8 ? CGFloat((value >> 24) & 0xFF) / 255 : 1
        return UIColor(
            red: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: a
        )
    }
}

// MARK: - UIGestureRecognizerDelegate

extension InAppMessageView: UIGestureRecognizerDelegate {
    public func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
        // The backdrop only, not the panel.
        return touch.view == self
    }
}

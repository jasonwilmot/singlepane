// FeedbackPopoverViewController.swift
// Popover content for submitting user feedback via GitHub Issues.
// User types feedback, clicks button, and it opens a pre-filled GitHub issue in the browser.

import AppKit

@MainActor
final class FeedbackPopoverViewController: NSViewController {

    // MARK: - Properties

    /// Reference to the owning popover for programmatic dismissal on success.
    weak var owningPopover: NSPopover?


    // MARK: - Constants

    private static let githubIssueURL = "https://github.com/jasonwilmot/singlepane/issues/new"
    private static let popoverWidth: CGFloat = 520
    private static let textViewHeight: CGFloat = 100
    private static let padding: CGFloat = 12

    // MARK: - UI Elements

    private let contentStack = NSStackView()
    private var textScrollView: NSScrollView!
    private var textView: NSTextView!
    private let sendButton = NSButton(frame: .zero)

    // MARK: - Init

    init() {
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: - Lifecycle

    override func loadView() {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false
        self.view = container
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        buildUI()
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        // Auto-focus the text view — dispatch to next run loop so the popover
        // window is fully ready to accept first responder.
        DispatchQueue.main.async { [weak self] in
            guard let self, let window = self.view.window else { return }
            window.makeFirstResponder(self.textView)
        }
    }

    // MARK: - Build UI

    private func buildUI() {
        let theme = ThemeManager.shared.activeTheme
        let font = FontManager.shared.activeFont

        // Vertical stack for form elements
        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = 8
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(contentStack)

        // Section header
        let header = NSTextField(labelWithString: "Send Feedback")
        header.font = font.withSize(9)
        header.textColor = theme.chromeTextSecondary
        contentStack.addArrangedSubview(header)

        // Multi-line text view — create with full text system wiring
        let contentWidth = Self.popoverWidth - Self.padding * 2
        let textStorage = NSTextStorage()
        let layoutManager = NSLayoutManager()
        textStorage.addLayoutManager(layoutManager)
        let textContainer = NSTextContainer(size: NSSize(width: contentWidth, height: .greatestFiniteMagnitude))
        textContainer.widthTracksTextView = true
        layoutManager.addTextContainer(textContainer)

        textView = NSTextView(frame: NSRect(x: 0, y: 0, width: contentWidth, height: Self.textViewHeight), textContainer: textContainer)
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.allowsUndo = true
        textView.drawsBackground = true
        textView.backgroundColor = theme.backgroundColor
        textView.insertionPointColor = theme.hookGreen
        textView.font = font.withSize(12)
        textView.textColor = theme.hookGreen
        textView.typingAttributes = [
            .font: font.withSize(12),
            .foregroundColor: theme.hookGreen,
        ]
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainerInset = NSSize(width: 4, height: 4)
        textView.delegate = self

        textScrollView = NSScrollView()
        textScrollView.hasVerticalScroller = true
        textScrollView.hasHorizontalScroller = false
        textScrollView.autohidesScrollers = true
        textScrollView.borderType = .lineBorder
        textScrollView.drawsBackground = true
        textScrollView.backgroundColor = theme.backgroundColor
        textScrollView.documentView = textView
        textScrollView.translatesAutoresizingMaskIntoConstraints = false
        contentStack.addArrangedSubview(textScrollView)

        // Send button — styled like layout manager save button
        sendButton.bezelStyle = .inline
        sendButton.isBordered = false
        sendButton.title = "Open Issue on GitHub"
        sendButton.font = font.withSize(11)
        sendButton.contentTintColor = theme.chromeText
        sendButton.wantsLayer = true
        sendButton.layer?.backgroundColor = theme.chromeAccent.withAlphaComponent(0.25).cgColor
        sendButton.layer?.cornerRadius = 4
        sendButton.target = self
        sendButton.action = #selector(sendClicked)
        sendButton.isEnabled = false
        sendButton.alphaValue = 0.4
        contentStack.addArrangedSubview(sendButton)

        // Layout
        NSLayoutConstraint.activate([
            contentStack.topAnchor.constraint(equalTo: view.topAnchor, constant: Self.padding),
            contentStack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -Self.padding),
            contentStack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Self.padding),
            contentStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Self.padding),

            textScrollView.widthAnchor.constraint(equalToConstant: Self.popoverWidth - Self.padding * 2),
            textScrollView.heightAnchor.constraint(equalToConstant: Self.textViewHeight),

            sendButton.widthAnchor.constraint(equalTo: textScrollView.widthAnchor),
            sendButton.heightAnchor.constraint(equalToConstant: 26),

            view.widthAnchor.constraint(equalToConstant: Self.popoverWidth),
        ])
    }

    // MARK: - Actions

    @objc private func sendClicked() {
        let text = textView.string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }

        var components = URLComponents(string: Self.githubIssueURL)!
        components.queryItems = [
            URLQueryItem(name: "body", value: text),
            URLQueryItem(name: "labels", value: "feedback"),
        ]

        if let url = components.url {
            NSWorkspace.shared.open(url)
        }

        textView.string = ""
        updateSendButtonState()
        owningPopover?.close()
    }

    // MARK: - Send Button State

    /// Enables or disables the send button based on whether the text view has content.
    private func updateSendButtonState() {
        let hasText = !textView.string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        sendButton.isEnabled = hasText
        sendButton.alphaValue = hasText ? 1.0 : 0.4
    }
}

// MARK: - NSTextViewDelegate

extension FeedbackPopoverViewController: NSTextViewDelegate {

    func textDidChange(_ notification: Notification) {
        updateSendButtonState()
    }
}

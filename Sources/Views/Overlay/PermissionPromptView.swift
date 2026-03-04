import SwiftUI
import AppKit

// MARK: - Overlay style constants (Speech Bubble + Tight Crisp Shadow)

private enum OverlayStyle {
    static let cardBg = Color.white
    static let cardShadow = Color(red: 35/255, green: 17/255, blue: 60/255).opacity(0.22)
    static let codeBg = Color(red: 250/255, green: 249/255, blue: 247/255)  // #faf9f7
    static let codeBorder = Color(red: 35/255, green: 17/255, blue: 60/255).opacity(0.06)
    static let textPrimary = Color(red: 35/255, green: 17/255, blue: 60/255)
    static let textMuted = Color(red: 35/255, green: 17/255, blue: 60/255).opacity(0.55)
    static let textHint = Color(red: 35/255, green: 17/255, blue: 60/255).opacity(0.30)
    static let orange = Color(red: 249/255, green: 93/255, blue: 2/255)
    static let orangeBorder = Color(red: 249/255, green: 93/255, blue: 2/255).opacity(0.25)
    static let selectedBg = Color(red: 249/255, green: 93/255, blue: 2/255).opacity(0.06)
    static let denyBorder = Color(red: 35/255, green: 17/255, blue: 60/255).opacity(0.12)
    static let denyText = Color(red: 35/255, green: 17/255, blue: 60/255).opacity(0.50)
    static let radioBorder = Color(red: 35/255, green: 17/255, blue: 60/255).opacity(0.20)
    static let inputBg = Color(red: 35/255, green: 17/255, blue: 60/255).opacity(0.04)

    static let tailHeight: CGFloat = 8
}

// MARK: - Tail Side Environment

/// Which edge of the speech bubble the tail protrudes from
enum TailSide {
    case bottom, top, left, right

    var paddingEdge: Edge.Set {
        switch self {
        case .bottom: return .bottom
        case .top: return .top
        case .left: return .leading
        case .right: return .trailing
        }
    }
}

private struct TailSideKey: EnvironmentKey {
    static let defaultValue: TailSide = .bottom
}

private struct TailPercentKey: EnvironmentKey {
    static let defaultValue: CGFloat = 0.80
}

extension EnvironmentValues {
    var speechBubbleTailSide: TailSide {
        get { self[TailSideKey.self] }
        set { self[TailSideKey.self] = newValue }
    }
    /// Position along the tail's edge (0.0–1.0). For top/bottom = horizontal, for left/right = vertical.
    var speechBubbleTailPercent: CGFloat {
        get { self[TailPercentKey.self] }
        set { self[TailPercentKey.self] = newValue }
    }
}

// MARK: - Speech Bubble Shape

/// Card with 14px corners and a triangular tail on any of the 4 edges.
/// `tailSide` controls which edge; `tailPercent` controls position along that edge.
private struct SpeechBubbleShape: Shape {
    var tailSide: TailSide = .bottom
    var tailPercent: CGFloat = 0.80

    private let r: CGFloat = 14
    private let tailH: CGFloat = OverlayStyle.tailHeight
    private let tailW: CGFloat = 14

    func path(in rect: CGRect) -> Path {
        switch tailSide {
        case .bottom: return bottomPath(in: rect)
        case .top:    return topPath(in: rect)
        case .left:   return leftPath(in: rect)
        case .right:  return rightPath(in: rect)
        }
    }

    // Clamp tail center along an axis so it stays inside corner radii
    private func clamp(_ value: CGFloat, length: CGFloat) -> CGFloat {
        let minV = r + tailW / 2
        let maxV = length - r - tailW / 2
        return max(minV, min(value, maxV))
    }

    private func bottomPath(in rect: CGRect) -> Path {
        let cardBottom = rect.height - tailH
        let tc = clamp(rect.width * tailPercent, length: rect.width)
        var p = Path()
        p.move(to: CGPoint(x: r, y: 0))
        p.addLine(to: CGPoint(x: rect.width - r, y: 0))
        p.addArc(center: CGPoint(x: rect.width - r, y: r), radius: r, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
        p.addLine(to: CGPoint(x: rect.width, y: cardBottom - r))
        p.addArc(center: CGPoint(x: rect.width - r, y: cardBottom - r), radius: r, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        p.addLine(to: CGPoint(x: tc + tailW / 2, y: cardBottom))
        p.addLine(to: CGPoint(x: tc, y: rect.height))
        p.addLine(to: CGPoint(x: tc - tailW / 2, y: cardBottom))
        p.addLine(to: CGPoint(x: r, y: cardBottom))
        p.addArc(center: CGPoint(x: r, y: cardBottom - r), radius: r, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        p.addLine(to: CGPoint(x: 0, y: r))
        p.addArc(center: CGPoint(x: r, y: r), radius: r, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        p.closeSubpath()
        return p
    }

    private func topPath(in rect: CGRect) -> Path {
        let cardTop = tailH
        let tc = clamp(rect.width * tailPercent, length: rect.width)
        var p = Path()
        p.move(to: CGPoint(x: r, y: cardTop))
        p.addLine(to: CGPoint(x: tc - tailW / 2, y: cardTop))
        p.addLine(to: CGPoint(x: tc, y: 0))
        p.addLine(to: CGPoint(x: tc + tailW / 2, y: cardTop))
        p.addLine(to: CGPoint(x: rect.width - r, y: cardTop))
        p.addArc(center: CGPoint(x: rect.width - r, y: cardTop + r), radius: r, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
        p.addLine(to: CGPoint(x: rect.width, y: rect.height - r))
        p.addArc(center: CGPoint(x: rect.width - r, y: rect.height - r), radius: r, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        p.addLine(to: CGPoint(x: r, y: rect.height))
        p.addArc(center: CGPoint(x: r, y: rect.height - r), radius: r, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        p.addLine(to: CGPoint(x: 0, y: cardTop + r))
        p.addArc(center: CGPoint(x: r, y: cardTop + r), radius: r, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        p.closeSubpath()
        return p
    }

    private func leftPath(in rect: CGRect) -> Path {
        let cardLeft = tailH
        let tc = clamp(rect.height * tailPercent, length: rect.height)
        var p = Path()
        p.move(to: CGPoint(x: cardLeft + r, y: 0))
        p.addLine(to: CGPoint(x: rect.width - r, y: 0))
        p.addArc(center: CGPoint(x: rect.width - r, y: r), radius: r, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
        p.addLine(to: CGPoint(x: rect.width, y: rect.height - r))
        p.addArc(center: CGPoint(x: rect.width - r, y: rect.height - r), radius: r, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        p.addLine(to: CGPoint(x: cardLeft + r, y: rect.height))
        p.addArc(center: CGPoint(x: cardLeft + r, y: rect.height - r), radius: r, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        // Left edge with tail (going down to up)
        p.addLine(to: CGPoint(x: cardLeft, y: tc + tailW / 2))
        p.addLine(to: CGPoint(x: 0, y: tc))
        p.addLine(to: CGPoint(x: cardLeft, y: tc - tailW / 2))
        p.addLine(to: CGPoint(x: cardLeft, y: r))
        p.addArc(center: CGPoint(x: cardLeft + r, y: r), radius: r, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        p.closeSubpath()
        return p
    }

    private func rightPath(in rect: CGRect) -> Path {
        let cardRight = rect.width - tailH
        let tc = clamp(rect.height * tailPercent, length: rect.height)
        var p = Path()
        p.move(to: CGPoint(x: r, y: 0))
        p.addLine(to: CGPoint(x: cardRight - r, y: 0))
        p.addArc(center: CGPoint(x: cardRight - r, y: r), radius: r, startAngle: .degrees(-90), endAngle: .degrees(0), clockwise: false)
        // Right edge with tail (going top to bottom)
        p.addLine(to: CGPoint(x: cardRight, y: tc - tailW / 2))
        p.addLine(to: CGPoint(x: rect.width, y: tc))
        p.addLine(to: CGPoint(x: cardRight, y: tc + tailW / 2))
        p.addLine(to: CGPoint(x: cardRight, y: rect.height - r))
        p.addArc(center: CGPoint(x: cardRight - r, y: rect.height - r), radius: r, startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
        p.addLine(to: CGPoint(x: r, y: rect.height))
        p.addArc(center: CGPoint(x: r, y: rect.height - r), radius: r, startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
        p.addLine(to: CGPoint(x: 0, y: r))
        p.addArc(center: CGPoint(x: r, y: r), radius: r, startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        p.closeSubpath()
        return p
    }
}

// MARK: - Shortcut Badge (reusable)

/// Small capsule badge showing ⌘N, overlaid on buttons/options when holding ⌘
private struct ShortcutBadge: View {
    let index: Int
    let isSelected: Bool

    var body: some View {
        Text("⌘\(index + 1)")
            .font(.system(size: 9, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(isSelected ? OverlayStyle.orange : OverlayStyle.textPrimary.opacity(0.7))
            .clipShape(Capsule())
            .transition(.scale.combined(with: .opacity))
    }
}

/// Small inline badge for action shortcuts (⌘↩, ⌘Esc, ⌘M)
private struct ActionBadge: View {
    let label: String

    var body: some View {
        Text(label)
            .font(.system(size: 8, weight: .bold, design: .rounded))
            .foregroundStyle(.white)
            .padding(.horizontal, 4)
            .padding(.vertical, 1.5)
            .background(OverlayStyle.textPrimary.opacity(0.55))
            .clipShape(Capsule())
            .transition(.scale.combined(with: .opacity))
    }
}

/// Render markdown string as AttributedString, falling back to plain text
private func markdownText(_ string: String) -> Text {
    if let attributed = try? AttributedString(markdown: string, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)) {
        return Text(attributed)
    }
    return Text(string)
}

/// Activate the terminal running the Claude Code session.
/// Delegates to shared IDETerminalFocus utility (supports exact tab switching via IDE extension).
private func focusTerminal(pid: Int? = nil, shellPid: Int? = nil) {
    IDETerminalFocus.focus(terminalPid: pid, shellPid: shellPid)
}

// MARK: - AskUserQuestion View

struct AskUserQuestionView: View {
    let permission: PendingPermission
    let questions: [ParsedQuestion]
    let onAnswer: ([String: String]) -> Void
    let onDeny: () -> Void
    let onLater: () -> Void
    var showShortcuts: Bool = false

    @Environment(\.speechBubbleTailSide) private var tailSide
    @Environment(\.speechBubbleTailPercent) private var tailPercent
    @Environment(GlobalHotkeyManager.self) private var hotkeyManager
    @Environment(PendingPermissionStore.self) private var pendingPermissionStore
    @State private var selections: [String: String] = [:]
    @State private var multiSelections: [String: Set<String>] = [:]
    @State private var customInputs: [String: String] = [:]
    @State private var usingCustom: Set<String> = []
    @FocusState private var otherFieldFocused: String?

    private var allAnswered: Bool {
        questions.allSatisfy { q in
            if usingCustom.contains(q.question) {
                return !(customInputs[q.question] ?? "").isEmpty
            }
            if q.multiSelect {
                return !(multiSelections[q.question] ?? []).isEmpty
            }
            return selections[q.question] != nil
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            // Header
            HStack {
                Image(systemName: "questionmark.circle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(OverlayStyle.orange)
                Text("Question")
                    .font(Constants.heading(size: 11, weight: .bold))
                    .foregroundStyle(OverlayStyle.textPrimary)

                Spacer()

                HStack(spacing: 3) {
                    Button { focusTerminal(pid: permission.event.terminalPid, shellPid: permission.event.shellPid) } label: {
                        Image(systemName: "terminal.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(OverlayStyle.textHint)
                    }
                    .buttonStyle(.plain)
                    .help("Open terminal")

                    if showShortcuts { ActionBadge(label: "⌘M") }
                }

                Button { onLater() } label: {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 10))
                        .foregroundStyle(OverlayStyle.textHint)
                }
                .buttonStyle(.plain)
                .help("Handle later")
            }

            ScrollView(.vertical, showsIndicators: true) {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(questions.enumerated()), id: \.offset) { _, question in
                        questionView(question)
                    }
                }
            }
            .frame(maxHeight: 200)

            // Submit / Skip
            HStack(spacing: 5) {
                Button {
                    var answers: [String: String] = [:]
                    for q in questions {
                        if usingCustom.contains(q.question) {
                            answers[q.question] = customInputs[q.question] ?? ""
                        } else if q.multiSelect {
                            answers[q.question] = (multiSelections[q.question] ?? []).sorted().joined(separator: ", ")
                        } else {
                            answers[q.question] = selections[q.question] ?? ""
                        }
                    }
                    onAnswer(answers)
                } label: {
                    HStack(spacing: 4) {
                        Text("Submit")
                            .font(Constants.heading(size: 11, weight: .semibold))
                            .foregroundStyle(.white)
                        if showShortcuts { ActionBadge(label: "⌘↩") }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                    .background(allAnswered ? OverlayStyle.orange : Color.gray.opacity(0.3))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .disabled(!allAnswered)

                Button {
                    onDeny()
                } label: {
                    HStack(spacing: 4) {
                        Text("Skip")
                            .font(Constants.heading(size: 11, weight: .semibold))
                            .foregroundStyle(OverlayStyle.denyText)
                        if showShortcuts { ActionBadge(label: "⌘⎋") }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                    .background(Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(OverlayStyle.denyBorder, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
        .padding(tailSide.paddingEdge, OverlayStyle.tailHeight)
        .background(OverlayStyle.cardBg)
        .clipShape(SpeechBubbleShape(tailSide: tailSide, tailPercent: tailPercent))
        .shadow(color: OverlayStyle.cardShadow, radius: 3, x: 0, y: 2)
        .onChange(of: hotkeyManager.selectedButtonIndex) { _, newIdx in
            guard showShortcuts, let idx = newIdx, let q = questions.first else { return }
            if idx < q.options.count {
                usingCustom.remove(q.question)
                if q.multiSelect {
                    var set = multiSelections[q.question] ?? []
                    let label = q.options[idx].label
                    if set.contains(label) { set.remove(label) } else { set.insert(label) }
                    multiSelections[q.question] = set
                } else {
                    selections[q.question] = q.options[idx].label
                }
            } else if idx == q.options.count {
                // "Other" option — activate app + make panel key so text field can receive focus
                pendingPermissionStore.onRequestTextInputFocus?()
                usingCustom.insert(q.question)
                selections.removeValue(forKey: q.question)
                otherFieldFocused = q.question
            }
        }
        .onChange(of: hotkeyManager.confirmTrigger) { _, _ in
            guard showShortcuts, allAnswered else { return }
            var answers: [String: String] = [:]
            for q in questions {
                if usingCustom.contains(q.question) {
                    answers[q.question] = customInputs[q.question] ?? ""
                } else if q.multiSelect {
                    answers[q.question] = (multiSelections[q.question] ?? []).sorted().joined(separator: ", ")
                } else {
                    answers[q.question] = selections[q.question] ?? ""
                }
            }
            onAnswer(answers)
        }
    }

    @ViewBuilder
    private func questionView(_ question: ParsedQuestion) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            if let header = question.header {
                Text(header)
                    .font(Constants.heading(size: 10, weight: .bold))
                    .foregroundStyle(OverlayStyle.orange)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .overlay(Capsule().stroke(OverlayStyle.orangeBorder, lineWidth: 1))
            }

            markdownText(question.question)
                .font(Constants.body(size: 11, weight: .medium))
                .foregroundStyle(OverlayStyle.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .contentShape(Rectangle())
                .onTapGesture { focusTerminal(pid: permission.event.terminalPid, shellPid: permission.event.shellPid) }

            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(question.options.enumerated()), id: \.offset) { idx, option in
                    optionRow(question: question, option: option, index: idx)
                }
                otherRow(question: question)
            }
        }
    }

    @ViewBuilder
    private func optionRow(question: ParsedQuestion, option: ParsedOption, index: Int) -> some View {
        let isMulti = question.multiSelect
        let isSelected: Bool = {
            guard !usingCustom.contains(question.question) else { return false }
            if isMulti {
                return multiSelections[question.question]?.contains(option.label) == true
            }
            return selections[question.question] == option.label
        }()

        Button {
            usingCustom.remove(question.question)
            if isMulti {
                var set = multiSelections[question.question] ?? []
                if set.contains(option.label) { set.remove(option.label) } else { set.insert(option.label) }
                multiSelections[question.question] = set
            } else {
                selections[question.question] = option.label
            }
        } label: {
            HStack(alignment: .top, spacing: 5) {
                Image(systemName: isMulti
                    ? (isSelected ? "checkmark.square.fill" : "square")
                    : (isSelected ? "checkmark.circle.fill" : "circle"))
                    .font(.system(size: 11))
                    .foregroundStyle(isSelected ? OverlayStyle.orange : OverlayStyle.radioBorder)
                    .frame(width: 13)

                VStack(alignment: .leading, spacing: 1) {
                    markdownText(option.label)
                        .font(Constants.body(size: 11, weight: .medium))
                        .foregroundStyle(OverlayStyle.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    if let desc = option.description, !desc.isEmpty {
                        markdownText(desc)
                            .font(Constants.body(size: 9))
                            .foregroundStyle(OverlayStyle.textMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Spacer(minLength: 0)

                if showShortcuts {
                    ShortcutBadge(index: index, isSelected: hotkeyManager.selectedButtonIndex == index)
                }
            }
            .padding(.vertical, 2)
            .padding(.horizontal, 5)
            .background(
                (hotkeyManager.selectedButtonIndex == index && showShortcuts)
                    ? OverlayStyle.orange.opacity(0.12)
                    : (isSelected ? OverlayStyle.selectedBg : Color.clear)
            )
            .clipShape(RoundedRectangle(cornerRadius: 7))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func otherRow(question: ParsedQuestion) -> some View {
        let isCustom = usingCustom.contains(question.question)
        let otherIndex = question.options.count

        VStack(alignment: .leading, spacing: 2) {
            Button {
                pendingPermissionStore.onRequestTextInputFocus?()
                usingCustom.insert(question.question)
                selections.removeValue(forKey: question.question)
                otherFieldFocused = question.question
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: isCustom ? "checkmark.circle.fill" : "circle")
                        .font(.system(size: 11))
                        .foregroundStyle(isCustom ? OverlayStyle.orange : OverlayStyle.radioBorder)
                        .frame(width: 13)

                    Text("Other")
                        .font(Constants.body(size: 11, weight: .medium))
                        .foregroundStyle(OverlayStyle.textMuted)

                    Spacer(minLength: 0)

                    if showShortcuts {
                        ShortcutBadge(index: otherIndex, isSelected: hotkeyManager.selectedButtonIndex == otherIndex)
                    }
                }
                .padding(.vertical, 2)
                .padding(.horizontal, 5)
                .background(
                    (hotkeyManager.selectedButtonIndex == otherIndex && showShortcuts)
                        ? OverlayStyle.orange.opacity(0.12)
                        : (isCustom ? OverlayStyle.selectedBg : Color.clear)
                )
                .clipShape(RoundedRectangle(cornerRadius: 7))
            }
            .buttonStyle(.plain)

            if isCustom {
                TextField("Type your answer...", text: Binding(
                    get: { customInputs[question.question] ?? "" },
                    set: { customInputs[question.question] = $0 }
                ))
                .focused($otherFieldFocused, equals: question.question)
                .textFieldStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(OverlayStyle.textPrimary)
                .padding(3)
                .background(OverlayStyle.inputBg)
                .clipShape(RoundedRectangle(cornerRadius: 7))
                .padding(.leading, 22)
            }
        }
    }
}

// MARK: - ExitPlanMode View

struct ExitPlanModeView: View {
    let permission: PendingPermission
    let onDecision: (PermissionDecision) -> Void
    let onFeedback: ((String) -> Void)?
    let onAllowWithPermissions: (([PermissionSuggestion]) -> Void)?
    let onLater: () -> Void
    var showShortcuts: Bool = false

    @Environment(\.speechBubbleTailSide) private var tailSide
    @Environment(\.speechBubbleTailPercent) private var tailPercent
    @Environment(GlobalHotkeyManager.self) private var hotkeyManager
    @Environment(PendingPermissionStore.self) private var pendingPermissionStore
    @State private var selectedOption = 1
    @State private var feedbackText = ""
    @State private var isExpanded = false
    @State private var planContent: String?
    @FocusState private var feedbackFocused: Bool

    private let options = [
        "Yes, clear context and auto-accept edits",
        "Yes, auto-accept edits",
        "Yes, manually approve edits",
        "Tell Claude what to change",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            // Header
            HStack {
                Image(systemName: "doc.text.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(OverlayStyle.orange)
                Text("Plan Ready")
                    .font(Constants.heading(size: 11, weight: .bold))
                    .foregroundStyle(OverlayStyle.textPrimary)

                Spacer()

                HStack(spacing: 3) {
                    Button { focusTerminal(pid: permission.event.terminalPid, shellPid: permission.event.shellPid) } label: {
                        Image(systemName: "terminal.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(OverlayStyle.textHint)
                    }
                    .buttonStyle(.plain)
                    .help("Open terminal")

                    if showShortcuts { ActionBadge(label: "⌘M") }
                }

                Button { onLater() } label: {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 10))
                        .foregroundStyle(OverlayStyle.textHint)
                }
                .buttonStyle(.plain)
                .help("Handle later")
            }

            // Plan content (rendered as markdown)
            if let content = planContent {
                if isExpanded {
                    ScrollView(.vertical, showsIndicators: true) {
                        markdownText(content)
                            .font(.system(size: 10))
                            .foregroundStyle(OverlayStyle.textPrimary.opacity(0.85))
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 120)
                    .padding(5)
                    .background(OverlayStyle.codeBg)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(OverlayStyle.codeBorder, lineWidth: 1))
                    .contentShape(Rectangle())
                    .onTapGesture { isExpanded = false }

                    Text("tap to collapse")
                        .font(.system(size: 9))
                        .foregroundStyle(OverlayStyle.textHint)
                } else {
                    let preview = content.split(separator: "\n", omittingEmptySubsequences: false)
                        .prefix(4)
                        .joined(separator: "\n")

                    markdownText(preview)
                        .font(.system(size: 10))
                        .foregroundStyle(OverlayStyle.textPrimary.opacity(0.75))
                        .lineLimit(4)
                        .padding(5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(OverlayStyle.codeBg)
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                        .overlay(RoundedRectangle(cornerRadius: 7).stroke(OverlayStyle.codeBorder, lineWidth: 1))
                        .contentShape(Rectangle())
                        .onTapGesture { isExpanded = true }

                    Text("tap to expand full plan")
                        .font(.system(size: 9))
                        .foregroundStyle(OverlayStyle.textHint)
                }
            } else {
                Text("Plan file not found")
                    .font(.system(size: 10))
                    .foregroundStyle(OverlayStyle.textMuted)
            }

            // Options
            VStack(alignment: .leading, spacing: 2) {
                ForEach(Array(options.enumerated()), id: \.offset) { idx, label in
                    Button {
                        selectedOption = idx
                        if idx == 3 {
                            pendingPermissionStore.onRequestTextInputFocus?()
                            feedbackFocused = true
                        }
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: selectedOption == idx ? "checkmark.circle.fill" : "circle")
                                .font(.system(size: 11))
                                .foregroundStyle(selectedOption == idx ? OverlayStyle.orange : OverlayStyle.radioBorder)
                                .frame(width: 13)

                            Text(label)
                                .font(Constants.body(size: 11, weight: .medium))
                                .foregroundStyle(OverlayStyle.textPrimary)

                            Spacer(minLength: 0)

                            if showShortcuts {
                                ShortcutBadge(index: idx, isSelected: hotkeyManager.selectedButtonIndex == idx)
                            }
                        }
                        .padding(.vertical, 2)
                        .padding(.horizontal, 5)
                        .background(
                            (hotkeyManager.selectedButtonIndex == idx && showShortcuts)
                                ? OverlayStyle.orange.opacity(0.12)
                                : (selectedOption == idx ? OverlayStyle.selectedBg : Color.clear)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                    }
                    .buttonStyle(.plain)
                }

                if selectedOption == 3 {
                    TextField("Type your feedback...", text: $feedbackText)
                        .focused($feedbackFocused)
                        .textFieldStyle(.plain)
                        .font(.system(size: 11))
                        .foregroundStyle(OverlayStyle.textPrimary)
                        .padding(3)
                        .background(OverlayStyle.inputBg)
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                        .padding(.leading, 22)
                }
            }

            // Approve / Deny
            HStack(spacing: 5) {
                Button {
                    if selectedOption == 3 && !feedbackText.isEmpty {
                        onFeedback?(feedbackText)
                    } else if selectedOption <= 1 {
                        let autoAccept = [
                            PermissionSuggestion(type: "setMode", destination: "session", behavior: nil, rules: nil, mode: "acceptEdits"),
                        ]
                        onAllowWithPermissions?(autoAccept)
                    } else {
                        onDecision(.allow)
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text("Approve")
                            .font(Constants.heading(size: 11, weight: .semibold))
                            .foregroundStyle(.white)
                        if showShortcuts { ActionBadge(label: "⌘↩") }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                    .background(
                        (selectedOption == 3 && feedbackText.isEmpty)
                            ? Color.gray.opacity(0.3)
                            : OverlayStyle.orange
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                }
                .buttonStyle(.plain)
                .disabled(selectedOption == 3 && feedbackText.isEmpty)

                Button {
                    onDecision(.deny)
                } label: {
                    HStack(spacing: 4) {
                        Text("Deny")
                            .font(Constants.heading(size: 11, weight: .semibold))
                            .foregroundStyle(OverlayStyle.denyText)
                        if showShortcuts { ActionBadge(label: "⌘⎋") }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 4)
                    .background(Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(OverlayStyle.denyBorder, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(8)
        .padding(tailSide.paddingEdge, OverlayStyle.tailHeight)
        .background(OverlayStyle.cardBg)
        .clipShape(SpeechBubbleShape(tailSide: tailSide, tailPercent: tailPercent))
        .shadow(color: OverlayStyle.cardShadow, radius: 3, x: 0, y: 2)
        .onAppear {
            planContent = permission.planFileContent
        }
        .onChange(of: hotkeyManager.selectedButtonIndex) { _, newIdx in
            guard showShortcuts, let idx = newIdx, idx < options.count else { return }
            selectedOption = idx
            if idx == 3 {
                pendingPermissionStore.onRequestTextInputFocus?()
                feedbackFocused = true
            }
        }
        .onChange(of: hotkeyManager.confirmTrigger) { _, _ in
            guard showShortcuts else { return }
            if selectedOption == 3 && !feedbackText.isEmpty {
                onFeedback?(feedbackText)
            } else if selectedOption <= 1 {
                let autoAccept = [
                    PermissionSuggestion(type: "setMode", destination: "session", behavior: nil, rules: nil, mode: "acceptEdits"),
                ]
                onAllowWithPermissions?(autoAccept)
            } else {
                onDecision(.allow)
            }
        }
    }
}

// MARK: - Standard Permission Prompt (Allow/Deny)

struct PermissionPromptView: View {
    let permission: PendingPermission
    let onDecision: (PermissionDecision) -> Void
    let onAnswers: (([String: String]) -> Void)?
    let onFeedback: ((String) -> Void)?
    let onAllowWithPermissions: (([PermissionSuggestion]) -> Void)?
    let onLater: () -> Void
    var showShortcuts: Bool = false
    init(permission: PendingPermission, onDecision: @escaping (PermissionDecision) -> Void, onAnswers: (([String: String]) -> Void)? = nil, onFeedback: ((String) -> Void)? = nil, onAllowWithPermissions: (([PermissionSuggestion]) -> Void)? = nil, onLater: @escaping () -> Void, showShortcuts: Bool = false) {
        self.permission = permission
        self.onDecision = onDecision
        self.onAnswers = onAnswers
        self.onFeedback = onFeedback
        self.onAllowWithPermissions = onAllowWithPermissions
        self.onLater = onLater
        self.showShortcuts = showShortcuts
    }

    @Environment(\.speechBubbleTailSide) private var tailSide
    @Environment(\.speechBubbleTailPercent) private var tailPercent
    @Environment(GlobalHotkeyManager.self) private var hotkeyManager
    @State private var isExpanded = false

    var body: some View {
        if permission.event.toolName == "ExitPlanMode" {
            ExitPlanModeView(
                permission: permission,
                onDecision: onDecision,
                onFeedback: onFeedback,
                onAllowWithPermissions: onAllowWithPermissions,
                onLater: onLater,
                showShortcuts: showShortcuts
            )
        } else if let questions = permission.parsedQuestions, !questions.isEmpty {
            AskUserQuestionView(
                permission: permission,
                questions: questions,
                onAnswer: { answers in onAnswers?(answers) },
                onDeny: { onDecision(.deny) },
                onLater: onLater,
                showShortcuts: showShortcuts
            )
        } else {
            standardPermissionView
        }
    }

    private var standardPermissionView: some View {
        VStack(alignment: .leading, spacing: 6) {
            // Header: tool name + terminal + later button
            HStack {
                Text(permission.toolName)
                    .font(Constants.heading(size: 11, weight: .bold))
                    .foregroundStyle(OverlayStyle.orange)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .overlay(Capsule().stroke(OverlayStyle.orangeBorder, lineWidth: 1))

                Spacer()

                HStack(spacing: 3) {
                    Button { focusTerminal(pid: permission.event.terminalPid, shellPid: permission.event.shellPid) } label: {
                        Image(systemName: "terminal.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(OverlayStyle.textHint)
                    }
                    .buttonStyle(.plain)
                    .help("Open terminal")

                    if showShortcuts { ActionBadge(label: "⌘M") }
                }

                Button { onLater() } label: {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 10))
                        .foregroundStyle(OverlayStyle.textHint)
                }
                .buttonStyle(.plain)
                .help("Handle later")
            }

            // Code preview
            if isExpanded {
                ScrollView(.vertical, showsIndicators: true) {
                    Text(permission.fullToolInputText)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(OverlayStyle.textPrimary.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 150)
                .padding(5)
                .background(OverlayStyle.codeBg)
                .clipShape(RoundedRectangle(cornerRadius: 7))
                .overlay(RoundedRectangle(cornerRadius: 7).stroke(OverlayStyle.codeBorder, lineWidth: 1))
                .contentShape(Rectangle())
                .onTapGesture { isExpanded = false }

                Text("tap to collapse")
                    .font(.system(size: 9))
                    .foregroundStyle(OverlayStyle.textHint)
            } else {
                Text(permission.toolInputPreview)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(OverlayStyle.textPrimary.opacity(0.75))
                    .lineLimit(2)
                    .padding(5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(OverlayStyle.codeBg)
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                    .overlay(RoundedRectangle(cornerRadius: 7).stroke(OverlayStyle.codeBorder, lineWidth: 1))
                    .contentShape(Rectangle())
                    .onTapGesture { isExpanded = true }
            }

            // Buttons: Allow / Deny
            let suggestions = permission.permissionSuggestions

            VStack(spacing: 3) {
                HStack(spacing: 5) {
                    Button {
                        onDecision(.allow)
                    } label: {
                        HStack(spacing: 4) {
                            Spacer(minLength: 0)
                            Text("Allow")
                                .font(Constants.heading(size: 11, weight: .semibold))
                                .foregroundStyle(.white)
                            if showShortcuts { ActionBadge(label: "⌘↩") }
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 4)
                        .background(OverlayStyle.orange)
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                    }
                    .buttonStyle(.plain)

                    Button {
                        onDecision(.deny)
                    } label: {
                        HStack(spacing: 4) {
                            Spacer(minLength: 0)
                            Text("Deny")
                                .font(Constants.heading(size: 11, weight: .semibold))
                                .foregroundStyle(OverlayStyle.denyText)
                            if showShortcuts { ActionBadge(label: "⌘⎋") }
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 4)
                        .background(Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                        .overlay(RoundedRectangle(cornerRadius: 7).stroke(OverlayStyle.denyBorder, lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }

                // "Always allow" suggestions (numbered: ⌘1, ⌘2, ...)
                ForEach(Array(suggestions.enumerated()), id: \.element.id) { sugIndex, suggestion in
                    Button {
                        onAllowWithPermissions?([suggestion])
                    } label: {
                        HStack(spacing: 4) {
                            Spacer(minLength: 0)
                            Text(suggestion.displayLabel)
                                .font(Constants.body(size: 10, weight: .medium))
                                .foregroundStyle(OverlayStyle.denyText)
                            if showShortcuts {
                                ShortcutBadge(index: sugIndex, isSelected: hotkeyManager.selectedButtonIndex == sugIndex)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.vertical, 3)
                        .background(
                            (hotkeyManager.selectedButtonIndex == sugIndex && showShortcuts)
                                ? OverlayStyle.orange.opacity(0.08)
                                : Color.clear
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 7))
                        .overlay(RoundedRectangle(cornerRadius: 7).stroke(
                            (hotkeyManager.selectedButtonIndex == sugIndex && showShortcuts)
                                ? OverlayStyle.orange
                                : OverlayStyle.denyBorder,
                            lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(8)
        .padding(tailSide.paddingEdge, OverlayStyle.tailHeight)
        .background(OverlayStyle.cardBg)
        .clipShape(SpeechBubbleShape(tailSide: tailSide, tailPercent: tailPercent))
        .shadow(color: OverlayStyle.cardShadow, radius: 3, x: 0, y: 2)
        .onChange(of: hotkeyManager.confirmTrigger) { _, _ in
            guard showShortcuts else { return }
            let sug = permission.permissionSuggestions
            if let idx = hotkeyManager.selectedButtonIndex, idx < sug.count {
                // A suggestion is selected — apply it
                onAllowWithPermissions?([sug[idx]])
            } else {
                // No suggestion selected — ⌘↩ means Allow
                onDecision(.allow)
            }
        }
    }
}

// MARK: - Collapsed Permission Pill

/// Compact pill shown when user clicks "Later" — tap to re-expand
private struct CollapsedPermissionPill: View {
    let permission: PendingPermission
    let onExpand: () -> Void
    let onAllow: () -> Void
    let onDeny: () -> Void
    var showShortcuts: Bool = false

    @Environment(GlobalHotkeyManager.self) private var hotkeyManager

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: "hand.raised.fill")
                .font(.system(size: 9))
                .foregroundStyle(OverlayStyle.orange)

            Text(permission.toolName)
                .font(Constants.heading(size: 10, weight: .bold))
                .foregroundStyle(OverlayStyle.textPrimary)

            Text(permission.toolInputPreview)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(OverlayStyle.textMuted)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 0)

            Button { focusTerminal(pid: permission.event.terminalPid, shellPid: permission.event.shellPid) } label: {
                Image(systemName: "terminal.fill")
                    .font(.system(size: 9))
                    .foregroundStyle(OverlayStyle.textHint)
            }
            .buttonStyle(.plain)
            .help("Open terminal")

            Button { onAllow() } label: {
                HStack(spacing: 3) {
                    Text("Allow")
                        .font(Constants.heading(size: 9, weight: .semibold))
                        .foregroundStyle(.white)
                    if showShortcuts { ActionBadge(label: "⌘↩") }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(OverlayStyle.orange)
                .clipShape(RoundedRectangle(cornerRadius: 5))
            }
            .buttonStyle(.plain)

            Button { onDeny() } label: {
                HStack(spacing: 3) {
                    Text("Deny")
                        .font(Constants.heading(size: 9, weight: .semibold))
                        .foregroundStyle(OverlayStyle.denyText)
                    if showShortcuts { ActionBadge(label: "⌘⎋") }
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(OverlayStyle.denyBorder, lineWidth: 1))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(OverlayStyle.cardBg)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: OverlayStyle.cardShadow, radius: 2, x: 0, y: 1)
        .contentShape(Rectangle())
        .onTapGesture { onExpand() }
        .onChange(of: hotkeyManager.confirmTrigger) { _, _ in
            guard showShortcuts else { return }
            onAllow()
        }
    }
}

// MARK: - Permission Stack Container

struct PermissionStackView: View {
    @Environment(PendingPermissionStore.self) var pendingPermissionStore
    @Environment(GlobalHotkeyManager.self) var hotkeyManager

    var body: some View {
        if !pendingPermissionStore.pending.isEmpty {
            VStack(spacing: 4) {
                // Bulk actions when multiple pending
                if pendingPermissionStore.pending.count > 1 {
                    HStack(spacing: 6) {
                        Text("\(pendingPermissionStore.pending.count) pending")
                            .font(Constants.body(size: 10, weight: .medium))
                            .foregroundStyle(OverlayStyle.textMuted)

                        Spacer()

                        Button {
                            pendingPermissionStore.resolveAll(decision: .allow)
                        } label: {
                            Text("Allow All")
                                .font(Constants.heading(size: 10, weight: .semibold))
                                .foregroundStyle(OverlayStyle.orange)
                        }
                        .buttonStyle(.plain)

                        Button {
                            pendingPermissionStore.resolveAll(decision: .deny)
                        } label: {
                            Text("Deny All")
                                .font(Constants.heading(size: 10, weight: .semibold))
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                }

                ForEach(Array(pendingPermissionStore.pending.reversed().enumerated()), id: \.element.id) { index, perm in
                    let isTopmost = index == 0
                    let showShortcuts = hotkeyManager.isCmdHeld && isTopmost

                    if pendingPermissionStore.collapsed.contains(perm.id) {
                        CollapsedPermissionPill(
                            permission: perm,
                            onExpand: { pendingPermissionStore.expand(id: perm.id) },
                            onAllow: { pendingPermissionStore.resolve(id: perm.id, decision: .allow) },
                            onDeny: { pendingPermissionStore.resolve(id: perm.id, decision: .deny) },
                            showShortcuts: showShortcuts
                        )
                        .transition(.move(edge: .top).combined(with: .opacity))
                    } else {
                        PermissionPromptView(
                            permission: perm,
                            onDecision: { decision in
                                pendingPermissionStore.resolve(id: perm.id, decision: decision)
                            },
                            onAnswers: { answers in
                                pendingPermissionStore.resolveWithAnswers(id: perm.id, answers: answers)
                            },
                            onFeedback: { feedback in
                                pendingPermissionStore.resolveWithFeedback(id: perm.id, feedback: feedback)
                            },
                            onAllowWithPermissions: { suggestions in
                                pendingPermissionStore.resolveWithPermissions(id: perm.id, suggestions: suggestions)
                            },
                            onLater: {
                                pendingPermissionStore.collapse(id: perm.id)
                            },
                            showShortcuts: showShortcuts
                        )
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
            }
            .animation(.easeInOut(duration: 0.15), value: hotkeyManager.isCmdHeld)
            .animation(.easeInOut(duration: 0.15), value: hotkeyManager.selectedButtonIndex)
            .animation(.easeInOut(duration: 0.2), value: pendingPermissionStore.pending.count)
        }
    }
}


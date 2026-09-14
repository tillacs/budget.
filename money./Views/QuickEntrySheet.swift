// QuickEntrySheet.swift
// budget. — das Blatt, für das es diese App gibt
//
// Zweimal auf die Rückseite tippen, und hier landet man: Richtung steht, Kategorie
// steht (die zuletzt benutzte), der Ziffernblock wartet. Ein Betrag sind drei bis
// vier Tasten, dann „Sichern". Nichts davon braucht die Systemtastatur, nichts
// davon braucht einen zweiten Bildschirm.
//
// Eingetippt wird von rechts nach links, wie an der Kasse: 1-2-5-0 ergibt 12,50 €.
// Ein Dezimaltrennzeichen gibt es deshalb nicht — es wäre eine Taste, die man nur
// treffen kann, wenn man vorher darüber nachdenkt.

import SwiftUI

struct QuickEntrySheet: View {
    let store: AppStore
    let direction: Direction
    /// Gesetzt, wenn eine bestehende Buchung geändert wird.
    let editing: Entry?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var currentDirection: Direction = .expense
    /// Der Betrag als Ziffernfolge in Cent. „1250" sind 12,50 €.
    @State private var digits = ""
    @State private var categoryID: UUID?
    @State private var note = ""
    @State private var date: CalendarDate = .today()
    @State private var pad: Pad = .digits
    @State private var showsNewCategory = false
    @State private var prepared = false
    @FocusState private var noteFocused: Bool

    private enum Pad { case digits, date, note }

    private var amount: Decimal {
        guard !digits.isEmpty, let cents = Decimal(string: digits) else { return 0 }
        return cents / 100
    }

    private var categories: [BudgetCategory] { store.data.categories(for: currentDirection) }
    private var canSave: Bool { amount > 0 && categoryID != nil }

    var body: some View {
        VStack(spacing: 0) {
            topBar
            switcher
                .padding(.horizontal, Metrics.screenInset)
                .padding(.top, 14)

            // Zwei Zwischenräume statt einem: Betrag, Kategorie und Notiz sitzen als
            // Block in der freien Fläche, statt am oberen Rand zu kleben.
            Spacer(minLength: 0)
            amountDisplay
            categoryRow
            noteRow
            Spacer(minLength: 0)

            padArea
            saveButton
        }
        .background(Palette.canvas)
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
        .presentationBackground(Palette.canvas)
        .task { prepare() }
        .onChange(of: noteFocused) { _, focused in
            withAnimation(motion) { pad = focused ? .note : .digits }
        }
        .sheet(isPresented: $showsNewCategory) {
            CategoryEditorSheet(store: store, editing: nil, direction: currentDirection) {
                categoryID = $0.id
            }
        }
        .sensoryFeedback(.impact(weight: .light), trigger: digits)
        .sensoryFeedback(.selection, trigger: categoryID)
    }

    // MARK: - Kopf

    private var topBar: some View {
        HStack {
            Button { dismiss() } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Palette.muted)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(Palette.raised))
            }
            .buttonStyle(PressableRowStyle())
            .accessibilityLabel("Abbrechen")

            Spacer()

            Button {
                noteFocused = false
                withAnimation(motion) { pad = pad == .date ? .digits : .date }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "calendar")
                        .font(.caption)
                    Text(dateLabel)
                        .font(.subheadline.weight(.medium))
                }
                .foregroundStyle(pad == .date ? Palette.ink : Palette.muted)
                .padding(.vertical, 7)
                .padding(.horizontal, 12)
                .background(Capsule().fill(Palette.raised))
            }
            .buttonStyle(PressableRowStyle())
            .accessibilityLabel("Datum: \(dateLabel)")
        }
        .padding(.horizontal, Metrics.screenInset)
        .padding(.top, 14)
    }

    /// Ausgabe oder Einnahme. Beim Ändern wechselt auch die Kategorienauswahl mit —
    /// „Gehalt" hat in den Ausgaben nichts zu suchen.
    private var switcher: some View {
        HStack(spacing: 4) {
            ForEach(Direction.allCases, id: \.self) { candidate in
                let isOn = currentDirection == candidate
                Button {
                    withAnimation(motion) {
                        currentDirection = candidate
                        categoryID = store.data.preferredCategory(for: candidate)?.id
                    }
                } label: {
                    Text(candidate.label)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(isOn ? Palette.canvas : Palette.muted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background {
                            if isOn {
                                Capsule().fill(Palette.ink)
                            }
                        }
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isOn ? [.isSelected] : [])
            }
        }
        .padding(4)
        .background(Capsule().fill(Palette.raised))
    }

    // MARK: - Betrag

    private var amountDisplay: some View {
        HStack(alignment: .firstTextBaseline, spacing: 2) {
            Text(currentDirection == .expense ? "−" : "+")
                .font(.system(size: 34, weight: .medium))
                .foregroundStyle(
                    digits.isEmpty
                        ? Palette.faint
                        : (currentDirection == .expense ? Palette.negative : Palette.positive))

            Text(MoneyFormat.amount(amount))
                .font(.system(size: 52, weight: .semibold))
                .monospacedDigit()
                .tracking(-1.6)
                .contentTransition(.numericText())
                .foregroundStyle(digits.isEmpty ? Palette.faint : Palette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.4)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 26)
        .padding(.bottom, 20)
        .padding(.horizontal, Metrics.screenInset)
        .animation(motion, value: digits.isEmpty)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(currentDirection.label) \(MoneyFormat.amount(amount))")
    }

    // MARK: - Kategorie

    private var categoryRow: some View {
        ScrollViewReader { scroll in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(categories) { category in
                        chip(category)
                            .id(category.id)
                    }
                    newCategoryChip
                }
                .padding(.horizontal, Metrics.screenInset)
                .padding(.vertical, 2)
            }
            .onChange(of: categoryID) { _, id in
                guard let id else { return }
                withAnimation(motion) { scroll.scrollTo(id, anchor: .center) }
            }
            .task {
                guard let id = categoryID else { return }
                scroll.scrollTo(id, anchor: .center)
            }
        }
    }

    private func chip(_ category: BudgetCategory) -> some View {
        let isOn = categoryID == category.id
        let tint = Palette.tint(category.tint)
        return Button {
            withAnimation(motion) { categoryID = category.id }
        } label: {
            HStack(spacing: 7) {
                Text(category.symbol).font(.system(size: 15))
                Text(category.name)
                    .font(.subheadline.weight(isOn ? .semibold : .regular))
                    .foregroundStyle(isOn ? Palette.ink : Palette.muted)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
            .background(Capsule().fill(isOn ? tint.opacity(0.18) : Palette.raised))
            .overlay(
                Capsule().strokeBorder(isOn ? tint : .clear, lineWidth: 1.5))
        }
        .buttonStyle(PressableRowStyle())
        .accessibilityLabel(category.name)
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }

    private var newCategoryChip: some View {
        Button {
            noteFocused = false
            showsNewCategory = true
        } label: {
            Image(systemName: "plus")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(Palette.muted)
                .frame(width: 40, height: 40)
                .background(Circle().fill(Palette.raised))
        }
        .buttonStyle(PressableRowStyle())
        .accessibilityLabel("Neue Kategorie")
    }

    // MARK: - Notiz

    private var noteRow: some View {
        HStack(spacing: 8) {
            Image(systemName: "text.alignleft")
                .font(.caption)
                .foregroundStyle(Palette.faint)
            TextField("Notiz", text: $note)
                .font(.subheadline)
                .foregroundStyle(Palette.ink)
                .focused($noteFocused)
                .submitLabel(.done)
                .onSubmit { noteFocused = false }
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(noteFocused ? Palette.card : Palette.canvas))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(noteFocused ? Palette.hairline : .clear, lineWidth: 1))
        .padding(.horizontal, Metrics.screenInset)
        .padding(.top, 12)
    }

    // MARK: - Unteres Feld

    @ViewBuilder
    private var padArea: some View {
        switch pad {
        case .digits:
            keypad
                .transition(.opacity)
        case .date:
            datePad
                .transition(.opacity)
        case .note:
            // Die Systemtastatur übernimmt die Fläche.
            Color.clear.frame(height: 0)
        }
    }

    private var keypad: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: 9), count: 3), spacing: 9
        ) {
            ForEach(1...9, id: \.self) { number in
                key("\(number)") { append("\(number)") }
            }
            key("00") { append("00") }
            key("0") { append("0") }
            backspaceKey
        }
        .padding(.horizontal, Metrics.screenInset)
    }

    private func key(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 27, weight: .regular))
                .monospacedDigit()
                .foregroundStyle(Palette.ink)
                .frame(maxWidth: .infinity, minHeight: 58)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Palette.raised))
        }
        .buttonStyle(PressableRowStyle())
    }

    /// Kurz tippen löscht eine Ziffer, lange drücken den ganzen Betrag.
    private var backspaceKey: some View {
        Button {
            if !digits.isEmpty { digits.removeLast() }
        } label: {
            Image(systemName: "delete.left")
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(Palette.ink)
                .frame(maxWidth: .infinity, minHeight: 58)
                .background(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Palette.raised))
        }
        .buttonStyle(PressableRowStyle())
        .simultaneousGesture(LongPressGesture().onEnded { _ in digits = "" })
        .accessibilityLabel("Löschen")
    }

    private var datePad: some View {
        DatePicker(
            "Datum",
            selection: Binding(
                get: { date.asDate ?? Date() },
                set: { date = CalendarDate(from: $0) }),
            displayedComponents: [.date])
        .datePickerStyle(.graphical)
        .tint(Palette.ink)
        .padding(.horizontal, Metrics.screenInset)
        .frame(maxHeight: 320)
    }

    // MARK: - Sichern

    private var saveButton: some View {
        Button(action: save) {
            Text(editing == nil ? "Sichern" : "Änderung sichern")
                .font(.headline)
                .foregroundStyle(canSave ? Palette.canvas : Palette.faint)
                .frame(maxWidth: .infinity, minHeight: 54)
                .background(
                    Capsule().fill(canSave ? Palette.ink : Palette.raised))
        }
        .buttonStyle(PressableRowStyle())
        .disabled(!canSave)
        .padding(.horizontal, Metrics.screenInset)
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    // MARK: - Ablauf

    private func append(_ text: String) {
        // Neun Ziffern sind 9.999.999,99 € — darüber hinaus tippt hier niemand etwas ein,
        // und die Anzeige würde anfangen zu schrumpfen.
        guard digits.count + text.count <= 9 else { return }
        guard !(digits.isEmpty && text == "00") else { return }
        digits += text
    }

    private func save() {
        guard canSave, let categoryID else { return }

        if let editing {
            var updated = editing
            updated.amount = amount
            updated.direction = currentDirection
            updated.categoryID = categoryID
            updated.note = note.trimmingCharacters(in: .whitespacesAndNewlines)
            updated.date = date
            store.update(updated)
        } else {
            store.add(Entry(
                date: date,
                amount: amount,
                direction: currentDirection,
                categoryID: categoryID,
                note: note.trimmingCharacters(in: .whitespacesAndNewlines)))
        }
        dismiss()
    }

    private func prepare() {
        guard !prepared else { return }
        prepared = true
        currentDirection = direction

        if let editing {
            digits = Self.digits(from: editing.amount)
            categoryID = editing.categoryID
            note = editing.note
            date = editing.date
        } else {
            categoryID = store.data.preferredCategory(for: direction)?.id
        }
    }

    /// Betrag zurück in die Ziffernfolge, mit der er eingetippt worden wäre.
    private static func digits(from amount: Decimal) -> String {
        var cents = amount * 100
        var rounded = Decimal()
        NSDecimalRound(&rounded, &cents, 0, .plain)
        return NSDecimalNumber(decimal: rounded).stringValue
    }

    private var dateLabel: String {
        date == .today() ? "Heute" : MoneyFormat.day(date)
    }

    private var motion: Animation? {
        reduceMotion ? nil : .spring(duration: 0.3, bounce: 0.1)
    }
}

#Preview("Erfassen") {
    Color.clear.sheet(isPresented: .constant(true)) {
        QuickEntrySheet(store: .preview, direction: .expense, editing: nil)
    }
}

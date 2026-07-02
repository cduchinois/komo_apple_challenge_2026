//  CardsView.swift
//  Komo
//
//  Cards tab — three sections that fill up as the user interacts with the
//  Reflect card on Home:
//    1. Saved insights   from `.save` / `.writeNote`
//    2. To-dos           from `.remindMe` (reminder) / `.addToCalendar` (calendar)
//    3. Energy advice    a light seeded feed of evergreen tips
//  Each section shows a soft empty state until it has content.

import SwiftUI

struct CardsView: View {
    @Environment(AppState.self) private var app
    var namespace: Namespace.ID

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) { // Increased gap between cards slightly
                header

                // --- SECTION 1: Saved Insights (Purple Card) ---
                VStack(alignment: .leading, spacing: 12) {
                    section(title: "Saved insights",
                            icon: "bookmark.fill",
                            empty: "Nothing saved yet — tap Save on a KOMO insight to keep it here.") {
                        savedInsightsList
                    }
                }
                .padding(24) // 1. Extra internal breathing room
                .frame(maxWidth: .infinity, alignment: .leading) // 2. Forces card to span edge-to-edge
                .background(Color.purple.opacity(0.08), in: RoundedRectangle(cornerRadius: 32))
                .glassEffect(.clear.interactive(), in: RoundedRectangle(cornerRadius: 32))

                // --- SECTION 2: To-dos (Blue Card) ---
                VStack(alignment: .leading, spacing: 12) {
                    section(title: "To-dos",
                            icon: "checklist",
                            empty: "No to-dos yet — Remind me or Add to calendar on an insight to add one.") {
                        todosList
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.blue.opacity(0.08), in: RoundedRectangle(cornerRadius: 32))
                .glassEffect(.clear.interactive(), in: RoundedRectangle(cornerRadius: 32))

                // --- SECTION 3: Energy Advice (Orange Card) ---
                VStack(alignment: .leading, spacing: 12) {
                    section(title: "Energy advice",
                            icon: "sparkles",
                            empty: "Advice coming soon.") {
                        adviceList
                    }
                }
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 32))
                .glassEffect(.clear.interactive(), in: RoundedRectangle(cornerRadius: 32))

                Spacer(minLength: 20)
            }
            .padding(.top, Theme.Space.screenTop)
            .padding(.bottom, 40)
        }
        .safeAreaPadding(.horizontal, 20)
    }

    // MARK: Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Cards")
                .font(Theme.Font.title(26))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.3), radius: 8, y: 1)
            Text("What KOMO has learned, saved, and reminded you about.")
                .font(Theme.Font.body(13))
                .foregroundStyle(.white.opacity(0.85))
                .shadow(color: .black.opacity(0.25), radius: 6, y: 1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: Generic section wrapper

    @ViewBuilder
    private func section<Content: View>(
        title: String,
        icon: String,
        empty: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white.opacity(0.85))
                Text(title.uppercased())
                    .font(Theme.Font.label(11, weight: .heavy))
                    .foregroundStyle(.white.opacity(0.85))
                    .tracking(1.2)
            }
            .padding(.leading, 4)

            let isEmpty = sectionIsEmpty(title)
            if isEmpty {
                Text(empty)
                    .font(Theme.Font.body(13))
                    .foregroundStyle(.white.opacity(0.75))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                            .fill(Color.white.opacity(0.10))
                            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card)
                                .strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
                    )
            } else {
                content()
            }
        }
    }

    private func sectionIsEmpty(_ title: String) -> Bool {
        switch title {
        case "Saved insights": return app.savedInsights.isEmpty
        case "To-dos":         return app.todos.isEmpty
        default:               return AppState.energyAdvice.isEmpty
        }
    }

    // MARK: Saved insights list

    private var savedInsightsList: some View {
        VStack(spacing: 10) {
            ForEach(app.savedInsights) { item in
                SavedInsightCard(item: item) {
                    withAnimation(.easeOut(duration: 0.2)) {
                        app.removeSavedInsight(item)
                    }
                }
            }
        }
    }

    // MARK: To-dos list

    private var todosList: some View {
        VStack(spacing: 8) {
            ForEach(app.todos) { todo in
                TodoRow(todo: todo,
                        onToggle: { app.toggleTodo(todo) },
                        onDelete: {
                            withAnimation(.easeOut(duration: 0.2)) {
                                app.removeTodo(todo)
                            }
                        })
            }
        }
    }

    // MARK: Energy advice list (static, seeded)

    private var adviceList: some View {
        VStack(spacing: 8) {
            ForEach(AppState.energyAdvice, id: \.self) { line in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "leaf.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.Palette.leaf)
                        .padding(.top, 3)
                    Text(line)
                        .font(Theme.Font.body(14))
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                        .fill(Color.white.opacity(0.12))
                        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.chip)
                            .strokeBorder(Color.white.opacity(0.18), lineWidth: 1))
                )
            }
        }
    }
}

// MARK: - Saved insight card

private struct SavedInsightCard: View {
    let item: SavedInsight
    var onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(item.observation)
                        .font(Theme.Font.body(14, weight: .semibold))
                        .foregroundStyle(.white)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(item.suggestion)
                        .font(Theme.Font.body(13))
                        .foregroundStyle(.white.opacity(0.85))
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button(action: onDelete) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white.opacity(0.7))
                        .padding(6)
                        .background(Color.white.opacity(0.12), in: Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove saved insight")
            }

            if let note = item.note, !note.isEmpty {
                Text(note)
                    .font(Theme.Font.body(13, weight: .medium))
                    .foregroundStyle(.white.opacity(0.9))
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.white.opacity(0.1),
                                in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .fill(Color.white.opacity(0.14))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card)
                    .strokeBorder(Color.white.opacity(0.22), lineWidth: 1))
        )
    }
}

// MARK: - Todo row

private struct TodoRow: View {
    let todo: TodoItem
    var onToggle: () -> Void
    var onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onToggle) {
                Image(systemName: todo.completed ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22, weight: .medium))
                    .foregroundStyle(todo.completed ? Theme.Palette.leaf : .white.opacity(0.7))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(todo.completed ? "Completed. Uncheck." : "Mark done.")

            VStack(alignment: .leading, spacing: 2) {
                Text(todo.text)
                    .font(Theme.Font.body(14, weight: .medium))
                    .foregroundStyle(.white.opacity(todo.completed ? 0.55 : 1))
                    .strikethrough(todo.completed, color: .white.opacity(0.55))
                    .fixedSize(horizontal: false, vertical: true)
                HStack(spacing: 5) {
                    Image(systemName: todo.kind == .calendar ? "calendar" : "bell")
                        .font(.system(size: 10, weight: .semibold))
                    Text(todo.kind == .calendar ? "Calendar" : "Reminder")
                        .font(Theme.Font.label(11, weight: .semibold))
                }
                .foregroundStyle(.white.opacity(0.65))
            }

            Spacer()

            Button(action: onDelete) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.white.opacity(0.7))
                    .padding(6)
                    .background(Color.white.opacity(0.12), in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Remove to-do")
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.chip, style: .continuous)
                .fill(Color.white.opacity(0.14))
                .overlay(RoundedRectangle(cornerRadius: Theme.Radius.chip)
                    .strokeBorder(Color.white.opacity(0.22), lineWidth: 1))
        )
    }
}

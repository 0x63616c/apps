import SwiftUI

struct DiscoverView: View {
    @Environment(AppModel.self) private var model
    @State private var showingAbout = false
    @State private var path: [String] = []

    var body: some View {
        @Bindable var model = model
        NavigationStack(path: $path) {
            ScrollView {
                LazyVStack(spacing: 14) {
                    Picker("Show", selection: $model.showFavouritesOnly) {
                        Text("All").tag(false)
                        Text("Favourites").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("discoverFilter")
                    .padding(.bottom, 4)

                    if model.visibleFestivals.isEmpty {
                        ContentUnavailableView(
                            model.showFavouritesOnly ? "No favourites yet" : "No upcoming festivals",
                            systemImage: model.showFavouritesOnly ? "heart" : "calendar",
                            description: Text(model.showFavouritesOnly ? "Tap the heart on a festival to keep it here." : "Check back soon.")
                        )
                        .padding(.top, 40)
                    }

                    ForEach(model.visibleFestivals) { festival in
                        ZStack(alignment: .topTrailing) {
                            FestivalCard(festival: festival)
                                .onTapGesture { path.append(festival.id) }
                                .accessibilityElement(children: .combine)
                                .accessibilityAddTraits(.isButton)
                                .accessibilityAction { path.append(festival.id) }
                                .accessibilityIdentifier("festival-\(festival.id)")
                            FavouriteButton(festival: festival)
                                .padding(18)
                        }
                    }

                    FeedFooter()
                        .padding(.top, 8)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 24)
            }
            .screenBackground()
            .navigationTitle("Discover")
            .navigationDestination(for: String.self) { id in
                if let festival = model.festival(id: id) {
                    FestivalView(festival: festival)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("About", systemImage: "info.circle") { showingAbout = true }
                }
            }
            .sheet(isPresented: $showingAbout) { AboutView() }
            .refreshable { await model.refresh() }
        }
    }
}

struct FestivalCard: View {
    @Environment(AppModel.self) private var model
    var festival: Festival

    var body: some View {
        let clock = FestivalClock(festival)
        let days = festival.daysUntil(now: model.now())
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(festival.name)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.primary)
                Text("\(clock.dateRange(festival)) · \(festival.location)")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Pill(text: Countdown.label(daysUntil: days), systemImage: days == 0 ? "dot.radiowaves.left.and.right" : nil, tint: days == 0 ? Palette.live : Palette.accent)
                    if !festival.hasSetTimes {
                        Pill(text: "Lineup only", tint: .secondary)
                    }
                }
                .padding(.top, 4)
            }
            Spacer(minLength: 0)
            Color.clear.frame(width: 44, height: 44)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(.rect(cornerRadius: 26))
        .glassCard()
    }
}

struct FavouriteButton: View {
    @Environment(AppModel.self) private var model
    var festival: Festival

    var body: some View {
        let isFavourite = model.isFavourite(festival)
        Button {
            withAnimation(.snappy) { model.toggleFavourite(festival) }
        } label: {
            Image(systemName: isFavourite ? "heart.fill" : "heart")
                .font(.title3)
                .foregroundStyle(isFavourite ? Palette.accent : .secondary)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 44, height: 44)
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: .circle)
        .accessibilityLabel(isFavourite ? "Remove from favourites" : "Add to favourites")
        .accessibilityIdentifier("favourite-\(festival.id)")
    }
}

struct FeedFooter: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        VStack(spacing: 4) {
            Text("Times updated \(model.feed.generatedAt.formatted(date: .abbreviated, time: .omitted))")
            if model.refreshFailed {
                Text("Offline. Showing saved times.")
            } else if let checked = model.lastChecked {
                Text("Checked \(checked.formatted(.relative(presentation: .named)))")
            }
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
        .accessibilityIdentifier("feedFooter")
    }
}

struct AboutView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var feedURL = UserDefaults.standard.string(forKey: "feedURL") ?? ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Text("Festr keeps festival set times, your schedule, lock-screen wallpapers and a Live Activity in one place. Set times can change; check the festival's own channels on the day.")
                        .font(.callout)
                }
                Section("Data") {
                    LabeledContent("Times updated", value: model.feed.generatedAt.formatted(date: .abbreviated, time: .shortened))
                    if let checked = model.lastChecked {
                        LabeledContent("Last checked", value: checked.formatted(date: .abbreviated, time: .shortened))
                    }
                    TextField("Feed URL", text: $feedURL)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Button("Use this feed") {
                        model.setFeedURL(feedURL)
                        Task { await model.refresh() }
                    }
                }
                Section("Privacy") {
                    Text("No account, no tracking. Your favourites and schedule stay on this iPhone.")
                        .font(.callout)
                }
            }
            .navigationTitle("About Festr")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", systemImage: "checkmark") { dismiss() }
                }
            }
        }
    }
}

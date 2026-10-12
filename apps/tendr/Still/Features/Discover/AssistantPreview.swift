import SwiftUI

struct AssistantPreview: View {
    var body: some View {
        NavigationStack {
            ZStack {
                Theme.background.ignoresSafeArea()
                VStack(spacing: 24) {
                    HStack { Spacer(); Text("How has my progress changed this month?").padding(18).background(.indigo.opacity(0.1), in: RoundedRectangle(cornerRadius: 20)).frame(maxWidth: 260) }
                    HStack { VStack(alignment: .leading, spacing: 12) { Capsule().fill(.secondary.opacity(0.2)).frame(width: 200, height: 10); Capsule().fill(.secondary.opacity(0.2)).frame(width: 170, height: 10); Capsule().fill(.secondary.opacity(0.2)).frame(width: 220, height: 10) }.padding(20).background(Theme.card, in: RoundedRectangle(cornerRadius: 20)); Spacer() }
                    HStack { Spacer(); Text("Help me prepare for my next appointment.").padding(18).background(.indigo.opacity(0.1), in: RoundedRectangle(cornerRadius: 20)).frame(maxWidth: 260) }
                    Spacer()
                }.padding(24).blur(radius: 6).opacity(0.45).accessibilityHidden(true)
                VStack(spacing: 18) {
                    Image(systemName: "sparkles").font(.system(size: 36, weight: .medium)).foregroundStyle(.indigo).frame(width: 82, height: 82).background(.indigo.opacity(0.10), in: RoundedRectangle(cornerRadius: 24))
                    Text("A little more support.").font(.title2.bold())
                    Text("Explore your journal.\nPrepare better questions.").font(.body).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Text("COMING SOON").font(.caption2.bold()).tracking(1.5).padding(.horizontal, 15).padding(.vertical, 9).background(.indigo.opacity(0.08), in: Capsule()).foregroundStyle(.indigo)
                    Text("Preview only. No AI is connected.").font(.caption).foregroundStyle(.secondary)
                }.padding(28).frame(maxWidth: .infinity).background(.regularMaterial, in: RoundedRectangle(cornerRadius: 28)).padding(24)
            }.navigationTitle("Assistant")
        }
    }
}

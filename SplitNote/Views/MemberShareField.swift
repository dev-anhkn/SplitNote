//
//  MemberShareField.swift
//  SplitNote
//

import SwiftUI

/// "Chi cho ai" multi-select: a row of tappable chips — "Tất cả" plus one
/// per member. Never lets `selectedMembers` end up empty (the view model's
/// `didSet` already guards this too; this is just belt-and-suspenders for
/// the tap gesture itself).
struct MemberShareField: View {
    let members: [String]
    @Binding var selectedMembers: Set<String>

    private var isAll: Bool { selectedMembers.count == members.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                IconBadge(systemName: "person.2.fill", color: .orange, size: 28)
                Text("Chi cho ai")
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    chip("Tất cả", isOn: isAll) {
                        selectedMembers = Set(members)
                    }
                    ForEach(members, id: \.self) { member in
                        chip(member, isOn: selectedMembers.contains(member)) {
                            toggle(member)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func toggle(_ member: String) {
        if selectedMembers.contains(member) {
            selectedMembers.remove(member)
        } else {
            selectedMembers.insert(member)
        }
    }

    private func chip(_ title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if isOn {
                    Image(systemName: "checkmark")
                        .font(.caption.weight(.bold))
                }
                Text(title)
                    .font(.subheadline.weight(isOn ? .semibold : .regular))
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(isOn ? AnyShapeStyle(Color.accentColor.gradient) : AnyShapeStyle(.quaternary.opacity(0.5)), in: Capsule())
            .foregroundStyle(isOn ? Color.white : Color.primary)
        }
        .buttonStyle(.plain)
        .animation(.snappy, value: isOn)
    }
}

#Preview {
    @Previewable @State var selected: Set<String> = ["An", "Bình"]
    return Form {
        MemberShareField(members: ["An", "Bình", "Chi"], selectedMembers: $selected)
    }
}

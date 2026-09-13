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
        VStack(alignment: .leading, spacing: 6) {
            Text("Chi cho ai")
                .font(.caption)
                .foregroundStyle(.secondary)
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
            Text(title)
                .font(.subheadline)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isOn ? Color.accentColor : Color.gray.opacity(0.2))
                .foregroundStyle(isOn ? Color.white : Color.primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    @Previewable @State var selected: Set<String> = ["An", "Bình"]
    return Form {
        MemberShareField(members: ["An", "Bình", "Chi"], selectedMembers: $selected)
    }
}

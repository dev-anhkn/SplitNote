//
//  MemberShareField.swift
//  SplitNote
//

import SwiftUI

/// Chọn nhiều "Chi cho ai" bằng các chip — "Tất cả" + mỗi thành viên 1 chip.
struct MemberShareField: View {
    let members: [String]
    @Binding var selectedMembers: Set<String>

    private var isAll: Bool { selectedMembers.count == members.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                IconBadge(systemName: "person.2.fill", color: AppStyle.indigo, size: 28)
                Text("Chi cho ai")
            }
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    SelectableChip(title: "Tất cả", isSelected: isAll, showsCheckmark: true) {
                        selectedMembers = Set(members)
                    }
                    ForEach(members, id: \.self) { member in
                        SelectableChip(title: member, isSelected: selectedMembers.contains(member), showsCheckmark: true) {
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
}

#Preview {
    @Previewable @State var selected: Set<String> = ["An", "Bình"]
    return Form {
        MemberShareField(members: ["An", "Bình", "Chi"], selectedMembers: $selected)
    }
}

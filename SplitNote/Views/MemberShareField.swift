//
//  MemberShareField.swift
//  SplitNote
//

import SwiftUI

/// "Chi cho ai" multi-select — 1 hàng giống `Picker` ("Ai chi"): nhãn bên
/// trái, bên phải là nút tóm tắt ("Tất cả" hoặc tên đã chọn) mở popover
/// checklist. Dùng `.popover` thay vì `Menu` vì `Menu` tự đóng sau mỗi lần
/// chọn — không chọn được nhiều người trong 1 lần mở. Never lets
/// `selectedMembers` end up empty — an empty set has no meaningful "chia
/// đều" denominator.
struct MemberShareField: View {
    let members: [String]
    @Binding var selectedMembers: Set<String>
    @State private var isShowingPicker = false

    private var isAll: Bool { selectedMembers.count == members.count }

    private var summaryLabel: String {
        isAll ? "Tất cả" : members.filter(selectedMembers.contains).joined(separator: ", ")
    }

    var body: some View {
        HStack {
            Text("Chi cho ai")
            Spacer()
            Button {
                isShowingPicker = true
            } label: {
                HStack(spacing: 4) {
                    Text(summaryLabel)
                        .lineLimit(1)
                        .foregroundStyle(.secondary)
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .buttonStyle(.plain)
            .popover(isPresented: $isShowingPicker) {
                checklist
            }
        }
    }

    private var checklist: some View {
        VStack(alignment: .leading, spacing: 0) {
            checklistRow("Tất cả", isOn: isAll) {
                selectedMembers = Set(members)
            }
            Divider()
            ForEach(members, id: \.self) { member in
                checklistRow(member, isOn: selectedMembers.contains(member)) {
                    toggle(member)
                }
            }
        }
        .padding(8)
        .frame(minWidth: 220)
    }

    private func checklistRow(_ title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: "checkmark")
                    .opacity(isOn ? 1 : 0)
                    .frame(width: 16)
                Text(title)
                Spacer()
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func toggle(_ member: String) {
        if selectedMembers.contains(member) {
            // Không cho bỏ chọn nốt người cuối cùng.
            guard selectedMembers.count > 1 else { return }
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

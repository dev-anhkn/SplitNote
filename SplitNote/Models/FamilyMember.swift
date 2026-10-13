//
//  FamilyMember.swift
//  SplitNote
//

import Foundation

/// Thành viên workspace gia đình; tách `email` (quyền Drive) khỏi `name` để đổi tên không đụng tới quyền.
struct FamilyMember: Identifiable, Hashable {
    let id: UUID
    var name: String
    var email: String?

    init(id: UUID = UUID(), name: String, email: String? = nil) {
        self.id = id
        self.name = name
        self.email = email
    }
}

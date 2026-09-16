//
//  FamilyMember.swift
//  SplitNote
//

import Foundation

/// One member of a `.family` workspace. `name` is what "Ai chi"/"Chi cho ai"
/// and the balance table actually use; `email`, if set, is who Drive access
/// was granted to — kept separate so renaming `name` never re-triggers a
/// share/revoke or changes which Google account can open the sheet.
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

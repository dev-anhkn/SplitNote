//
//  Binding+IsPresent.swift
//  SplitNote
//

import SwiftUI

extension Binding where Value == Bool {
    /// Bật khi `value` khác nil; tắt (đóng dialog) thì gán `value` về nil.
    init<Wrapped>(isPresent value: Binding<Wrapped?>) {
        self.init(
            get: { value.wrappedValue != nil },
            set: { isPresented in
                guard !isPresented else { return }
                value.wrappedValue = nil
            }
        )
    }
}

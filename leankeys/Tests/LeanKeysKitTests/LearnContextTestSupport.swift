import Foundation
@testable import LeanKeysKit

extension LearnContext {
    /// The key-thread half of this context. The pid stands for the field: `secureFieldPid` when `secureField`, so the
    /// queue half (`isTestSecureField`) answers from what was captured at key time, never from a later context.
    var probe: LearnContextProbe {
        LearnContextProbe(bundleID: bundleID, pid: secureField ? LearnContext.secureFieldPid : 2,
                          secureInput: secureInput, now: now)
    }

    static let secureFieldPid: pid_t = 1

    /// The queue half for a probe made by `probe`.
    static func isTestSecureField(_ probe: LearnContextProbe) -> Bool {
        probe.secureInput || probe.pid == secureFieldPid
    }
}

extension UndoLearning {
    /// A learner whose context comes from `context`, split as the app splits it: the key-thread half from
    /// `LearnContext.probe`, the secure-field answer from the same snapshot.
    convenience init(book: UndoRuleBook, defaults: UserDefaults, context: @escaping () -> LearnContext,
                     names: LearnedNames = UndoLearning.memoryNames(),
                     onRecordQueue: ((@escaping () -> Void) -> Void)? = nil) {
        self.init(book: book, defaults: defaults, probe: { context().probe },
                  secureField: LearnContext.isTestSecureField, names: names, onRecordQueue: onRecordQueue)
    }
}

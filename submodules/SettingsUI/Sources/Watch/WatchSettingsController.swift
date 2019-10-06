import Foundation
import UIKit
import Display
import SwiftSignalKit
import Postbox
import TelegramCore
import TelegramPresentationData
import TelegramUIPreferences
import ItemListUI
import AccountContext

private final class WatchSettingsControllerArguments {
    let updatePreset: (String, String) -> Void
    
    init(updatePreset: @escaping (String, String) -> Void) {
        self.updatePreset = updatePreset
    }
}

private enum WatchSettingsSection: Int32 {
    case replyPresets
}

private enum WatchSettingsControllerEntry: ItemListNodeEntry {
    case replyPresetsHeader(PresentationTheme, String)
    case replyPreset(PresentationTheme, PresentationStrings, String, String, String, Int32)
    case replyPresetsInfo(PresentationTheme, String)
    
    var section: ItemListSectionId {
        switch self {
            case .replyPresetsHeader, .replyPreset, .replyPresetsInfo:
                return WatchSettingsSection.replyPresets.rawValue
        }
    }
    
    var stableId: Int32 {
        switch self {
            case .replyPresetsHeader:
                return 0
            case let .replyPreset(_, _, _, _, _, index):
                return 1 + index
            case .replyPresetsInfo:
                return 100
        }
    }
    
    static func ==(lhs: WatchSettingsControllerEntry, rhs: WatchSettingsControllerEntry) -> Bool {
        switch lhs {
            case let .replyPresetsHeader(lhsTheme, lhsText):
                if case let .replyPresetsHeader(rhsTheme, rhsText) = rhs, lhsTheme === rhsTheme, lhsText == rhsText {
                    return true
                } else {
                    return false
                }
            
            case let .replyPreset(lhsTheme, lhsStrings, lhsIdentifier, lhsPlaceholder, lhsValue, lhsIndex):
                if case let .replyPreset(rhsTheme, rhsStrings, rhsIdentifier, rhsPlaceholder, rhsValue, rhsIndex) = rhs, lhsTheme === rhsTheme, lhsStrings === rhsStrings, lhsIdentifier == rhsIdentifier, lhsPlaceholder == rhsPlaceholder, lhsValue == rhsValue, lhsIndex == rhsIndex {
                    return true
                } else {
                    return false
                }
            
            case let .replyPresetsInfo(lhsTheme, lhsText):
                if case let .replyPresetsInfo(rhsTheme, rhsText) = rhs, lhsTheme === rhsTheme, lhsText == rhsText {
                    return true
                } else {
                    return false
                }
        }
    }
        
    static func <(lhs: WatchSettingsControllerEntry, rhs: WatchSettingsControllerEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }
    
    func item(_ arguments: Any) -> ListViewItem {
        let arguments = arguments as! WatchSettingsControllerArguments
        switch self {
            case let .replyPresetsHeader(theme, text):
                return ItemListSectionHeaderItem(theme: theme, text: text, sectionId: self.section)
            case let .replyPreset(theme, strings, identifier, placeholder, value, _):
                return ItemListSingleLineInputItem(theme: theme, strings: strings, title: NSAttributedString(string: ""), text: value, placeholder: placeholder, type: .regular(capitalization: true, autocorrection: true), spacing: 0.0, sectionId: self.section, textUpdated: { updatedText in
                    arguments.updatePreset(identifier, updatedText.trimmingCharacters(in: .whitespacesAndNewlines))
                }, action: {})
            case let .replyPresetsInfo(theme, text):
                return ItemListTextItem(theme: theme, text: .plain(text), sectionId: self.section)
        }
    }
}

private func watchSettingsControllerEntries(presentationData: PresentationData, customPresets: [String : String]) -> [WatchSettingsControllerEntry] {
    var entries: [WatchSettingsControllerEntry] = []
    
    let defaultSuggestions: [(Int32, String, String)] = [
        (0, "OK", presentationData.strings.Watch_Suggestion_OK),
        (1, "Thanks", presentationData.strings.Watch_Suggestion_Thanks),
        (2, "WhatsUp", presentationData.strings.Watch_Suggestion_WhatsUp),
        (3, "TalkLater", presentationData.strings.Watch_Suggestion_TalkLater),
        (4, "CantTalk", presentationData.strings.Watch_Suggestion_CantTalk),
        (5, "HoldOn", presentationData.strings.Watch_Suggestion_HoldOn),
        (6, "BRB", presentationData.strings.Watch_Suggestion_BRB),
        (7, "OnMyWay", presentationData.strings.Watch_Suggestion_OnMyWay)
    ]
    
    entries.append(.replyPresetsHeader(presentationData.theme, presentationData.strings.AppleWatch_ReplyPresets))
    for (index, identifier, placeholder) in defaultSuggestions {
        entries.append(.replyPreset(presentationData.theme, presentationData.strings, identifier, placeholder, customPresets[identifier] ?? "", index))
    }
    entries.append(.replyPresetsInfo(presentationData.theme, presentationData.strings.AppleWatch_ReplyPresetsHelp))
    
    return entries
}

public func watchSettingsController(context: AccountContext) -> ViewController {
    var pushControllerImpl: ((ViewController) -> Void)?
    var presentControllerImpl: ((ViewController) -> Void)?
    
    let updateDisposable = MetaDisposable()
    let arguments = WatchSettingsControllerArguments(updatePreset: { identifier, text in
        updateDisposable.set((.complete() |> delay(1.0, queue: Queue.mainQueue()) |> then(updateWatchPresetSettingsInteractively(accountManager: context.sharedContext.accountManager, { current in
            var updatedPresets = current.customPresets
            if !text.isEmpty {
                updatedPresets[identifier] = text
            } else {
                updatedPresets.removeValue(forKey: identifier)
            }
            return WatchPresetSettings(presets: updatedPresets)
        }))).start())
    })
    
    let signal = combineLatest(context.sharedContext.presentationData, context.sharedContext.accountManager.sharedData(keys: [ApplicationSpecificSharedDataKeys.watchPresetSettings]))
    |> deliverOnMainQueue
    |> map { presentationData, sharedData -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let settings = (sharedData.entries[ApplicationSpecificSharedDataKeys.watchPresetSettings] as? WatchPresetSettings) ?? WatchPresetSettings.defaultSettings
        
        let controllerState = ItemListControllerState(theme: presentationData.theme, title: .text(presentationData.strings.AppleWatch_Title), leftNavigationButton: nil, rightNavigationButton: nil, backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back))
        let listState = ItemListNodeState(entries: watchSettingsControllerEntries(presentationData: presentationData, customPresets: settings.customPresets), style: .blocks, animateChanges: false)
        
        return (controllerState, (listState, arguments))
    }
    
    let controller = ItemListController(context: context, state: signal)
    pushControllerImpl = { [weak controller] c in
        (controller?.navigationController as? NavigationController)?.pushViewController(c)
    }
    presentControllerImpl = { [weak controller] c in
        controller?.present(c, in: .window(.root))
    }
    return controller
}


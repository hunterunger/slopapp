import AppKit
import PaperCore
import SlopKit

/// The whole menu bar, built in code. Every document action lives in a menu with its shortcut.
@MainActor
enum MainMenu {
    typealias W = PaperWindowController

    static func build() -> NSMenu {
        let main = NSMenu()
        main.addItem(submenu(appMenu()))
        main.addItem(submenu(fileMenu()))
        main.addItem(submenu(editMenu()))
        main.addItem(submenu(viewMenu()))
        main.addItem(submenu(goMenu()))
        main.addItem(submenu(toolsMenu()))
        main.addItem(submenu(pagesMenu()))
        let window = windowMenu()
        main.addItem(submenu(window))
        NSApp.windowsMenu = window
        let help = helpMenu()
        main.addItem(submenu(help))
        NSApp.helpMenu = help
        return main
    }

    private static func submenu(_ menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: menu.title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }

    @discardableResult
    private static func add(_ menu: NSMenu, _ title: String, _ action: Selector?, _ key: String = "",
                            _ modifiers: NSEvent.ModifierFlags = .command, object: Any? = nil, target: AnyObject? = nil) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.keyEquivalentModifierMask = key.isEmpty ? [] : modifiers
        item.representedObject = object
        item.target = target
        menu.addItem(item)
        return item
    }

    private static func appMenu() -> NSMenu {
        let name = ProcessInfo.processInfo.processName
        let menu = NSMenu(title: name)
        let delegate = NSApp.delegate as AnyObject?
        add(menu, "About \(name)", #selector(PaperAppDelegate.showAbout(_:)), target: delegate)
        menu.addItem(.separator())
        add(menu, "Settings…", #selector(PaperAppDelegate.showSettings(_:)), ",", target: delegate)
        menu.addItem(.separator())
        let services = NSMenuItem(title: "Services", action: nil, keyEquivalent: "")
        services.submenu = NSMenu(title: "Services")
        NSApp.servicesMenu = services.submenu
        menu.addItem(services)
        menu.addItem(.separator())
        add(menu, "Hide \(name)", #selector(NSApplication.hide(_:)), "h")
        add(menu, "Hide Others", #selector(NSApplication.hideOtherApplications(_:)), "h", [.command, .option])
        add(menu, "Show All", #selector(NSApplication.unhideAllApplications(_:)))
        menu.addItem(.separator())
        add(menu, "Quit \(name)", #selector(NSApplication.terminate(_:)), "q")
        return menu
    }

    private static func fileMenu() -> NSMenu {
        let menu = NSMenu(title: "File")
        add(menu, "Open…", #selector(NSDocumentController.openDocument(_:)), "o")
        // AppKit adds File > Open Recent itself, right after Open…, for document-based apps.
        add(menu, "Combine Files…", #selector(PaperAppDelegate.showCombine(_:)), target: NSApp.delegate as AnyObject?)
        add(menu, "Compare With…", #selector(W.compareDocuments(_:)), "k", [.command, .option])
        menu.addItem(.separator())
        add(menu, "Close", #selector(NSWindow.performClose(_:)), "w")
        add(menu, "Save", #selector(NSDocument.save(_:)), "s")
        add(menu, "Duplicate", #selector(NSDocument.duplicate(_:)), "s", [.command, .shift])
        add(menu, "Rename…", #selector(NSDocument.rename(_:)))
        add(menu, "Move To…", #selector(NSDocument.move(_:)))
        let revert = add(menu, "Revert To", nil)
        let revertMenu = NSMenu(title: "Revert To")
        add(revertMenu, "Last Saved Version", #selector(NSDocument.revertToSaved(_:)))
        add(revertMenu, "Browse All Versions…", #selector(NSDocument.browseVersions(_:)))
        revert.submenu = revertMenu
        menu.addItem(.separator())
        add(menu, "Export Flattened Copy…", #selector(W.exportFlattened(_:)))
        add(menu, "Export as Images…", #selector(W.exportImages(_:)))
        add(menu, "Export as Word Document…", #selector(W.exportWord(_:)))
        add(menu, "Export Text…", #selector(W.exportText(_:)))
        add(menu, "Save Protected Copy…", #selector(W.saveProtectedCopy(_:)))
        menu.addItem(.separator())
        let share = add(menu, "Share", nil)
        let shareMenu = NSMenu(title: "Share")
        add(shareMenu, "Share…", #selector(W.shareDocument(_:)))
        add(shareMenu, "Share Flattened Copy…", #selector(W.shareFlattenedCopy(_:)))
        share.submenu = shareMenu
        menu.addItem(.separator())
        add(menu, "Page Setup…", #selector(NSDocument.runPageLayout(_:)), "p", [.command, .shift])
        add(menu, "Print…", #selector(NSDocument.printDocument(_:)), "p")
        return menu
    }

    private static func editMenu() -> NSMenu {
        let menu = NSMenu(title: "Edit")
        add(menu, "Undo", Selector(("undo:")), "z")
        add(menu, "Redo", Selector(("redo:")), "z", [.command, .shift])
        menu.addItem(.separator())
        add(menu, "Cut", #selector(NSText.cut(_:)), "x")
        add(menu, "Copy", #selector(NSText.copy(_:)), "c")
        add(menu, "Paste", #selector(NSText.paste(_:)), "v")
        add(menu, "Delete", #selector(W.delete(_:)))
        add(menu, "Select All", #selector(NSText.selectAll(_:)), "a")
        menu.addItem(.separator())
        let find = add(menu, "Find", nil)
        let findMenu = NSMenu(title: "Find")
        add(findMenu, "Find…", #selector(W.focusSearch(_:)), "f")
        add(findMenu, "Find Next", #selector(W.findNext(_:)), "g")
        add(findMenu, "Find Previous", #selector(W.findPrevious(_:)), "g", [.command, .shift])
        add(findMenu, "Use Selection for Find", #selector(W.useSelectionForFind(_:)), "e")
        findMenu.addItem(.separator())
        add(findMenu, "Find and Highlight…", #selector(W.findAndHighlight(_:)), "f", [.command, .option, .shift])
        add(findMenu, "Find and Redact…", #selector(W.showFindAndRedact(_:)), "f", [.command, .shift])
        findMenu.addItem(.separator())
        add(findMenu, "Highlight All Results", #selector(W.highlightSearchResults(_:)))
        find.submenu = findMenu
        menu.addItem(.separator())
        add(menu, "Copy Text from Page", #selector(W.copyTextFromPage(_:)))
        add(menu, "Copy Highlights & Notes", #selector(W.copyNotes(_:)), "c", [.command, .option, .shift])
        add(menu, "Remove Markup from Selection", #selector(W.removeMarkupFromSelection(_:)), "0", [.command, .option, .shift])
        menu.addItem(.separator())
        add(menu, "Recognize Text…", #selector(W.recognizeText(_:)))
        add(menu, "Clear Form…", #selector(W.resetForm(_:)))
        return menu
    }

    private static func viewMenu() -> NSMenu {
        let menu = NSMenu(title: "View")
        add(menu, "Single Page", #selector(W.displaySinglePage(_:)))
        add(menu, "Continuous Scroll", #selector(W.displayContinuous(_:)))
        add(menu, "Two Pages", #selector(W.displayTwoPages(_:)))
        add(menu, "Show Cover Page Alone", #selector(W.toggleBookMode(_:)))
        menu.addItem(.separator())
        add(menu, "Actual Size", #selector(W.zoomActualSize(_:)), "0")
        add(menu, "Zoom In", #selector(W.paperZoomIn(_:)), "+")
        add(menu, "Zoom Out", #selector(W.paperZoomOut(_:)), "-")
        add(menu, "Zoom to Fit", #selector(W.zoomToFit(_:)), "0", [.command, .option])
        add(menu, "Zoom to Width", #selector(W.zoomToWidth(_:)), "9", [.command, .option])
        menu.addItem(.separator())
        add(menu, "Hide Sidebar", #selector(W.hideSidebar(_:)), "1", [.command, .option])
        add(menu, "Thumbnails", #selector(W.showSidebarMode(_:)), "2", [.command, .option], object: SidebarMode.thumbnails.rawValue)
        add(menu, "Outline", #selector(W.showSidebarMode(_:)), "3", [.command, .option], object: SidebarMode.outline.rawValue)
        add(menu, "Notes", #selector(W.showSidebarMode(_:)), "4", [.command, .option], object: SidebarMode.annotations.rawValue)
        add(menu, "Fields", #selector(W.showSidebarMode(_:)), "5", [.command, .option], object: SidebarMode.fields.rawValue)
        menu.addItem(.separator())
        add(menu, "Highlight Form Fields", #selector(W.toggleFieldHighlight(_:)))
        menu.addItem(.separator())
        add(menu, "Hide Editing Bar", #selector(W.toggleEditingBar(_:)), "e", [.command, .shift])
        add(menu, "Show Inspector", #selector(W.paperToggleInspector(_:)), "i", [.command, .option])
        add(menu, "Document Info", #selector(W.showDocumentInspector(_:)))
        add(menu, "Security", #selector(W.showSecurityInspector(_:)))
        add(menu, "Selection Details", #selector(W.showSelectionInspector(_:)))
        menu.addItem(.separator())
        add(menu, "Show Toolbar", #selector(NSWindow.toggleToolbarShown(_:)), "t", [.command, .option])
        add(menu, "Customize Toolbar…", #selector(NSWindow.runToolbarCustomizationPalette(_:)))
        add(menu, "Enter Full Screen", #selector(NSWindow.toggleFullScreen(_:)), "f", [.command, .control])
        return menu
    }

    private static func goMenu() -> NSMenu {
        let menu = NSMenu(title: "Go")
        add(menu, "Next Page", #selector(W.nextPage(_:)), String(UnicodeScalar(NSDownArrowFunctionKey)!), [.command, .option, .shift])
        add(menu, "Previous Page", #selector(W.previousPage(_:)), String(UnicodeScalar(NSUpArrowFunctionKey)!), [.command, .option, .shift])
        add(menu, "First Page", #selector(W.firstPage(_:)), String(UnicodeScalar(NSHomeFunctionKey)!), [])
        add(menu, "Last Page", #selector(W.lastPage(_:)), String(UnicodeScalar(NSEndFunctionKey)!), [])
        menu.addItem(.separator())
        add(menu, "Go to Page…", #selector(W.goToPageField(_:)), "g", [.command, .option])
        menu.addItem(.separator())
        add(menu, "Back", #selector(W.paperGoBack(_:)), "[")
        add(menu, "Forward", #selector(W.paperGoForward(_:)), "]")
        return menu
    }

    private static func toolsMenu() -> NSMenu {
        let menu = NSMenu(title: "Tools")
        for tool in Tool.allCases {
            add(menu, tool.title, #selector(W.chooseTool(_:)), tool.shortcut, object: tool.rawValue)
        }
        menu.addItem(.separator())
        let style = add(menu, "Text Markup", nil)
        let styleMenu = NSMenu(title: "Text Markup")
        for markup in MarkupStyle.allCases {
            add(styleMenu, markup.title, #selector(W.chooseMarkupStyle(_:)), object: markup.rawValue)
        }
        style.submenu = styleMenu
        let color = add(menu, "Highlight Color", nil)
        let colorMenu = NSMenu(title: "Highlight Color")
        for ink in InkColor.highlighters {
            add(colorMenu, ink.title, #selector(W.chooseHighlightColor(_:)), object: ink.rawValue).image = ColorSwatch.image(ink.nsColor)
        }
        color.submenu = colorMenu
        let forms = add(menu, "Form Field", nil)
        let formMenu = NSMenu(title: "Form Field")
        for kind in FormFieldKind.allCases {
            add(formMenu, kind.title, #selector(W.chooseFormKind(_:)), object: kind.rawValue)
        }
        forms.submenu = formMenu
        let shapes = add(menu, "Shape", nil)
        let shapeMenu = NSMenu(title: "Shape")
        for kind in ShapeKind.allCases {
            add(shapeMenu, kind.title, #selector(W.chooseShape(_:)), object: kind.rawValue)
        }
        shapes.submenu = shapeMenu
        menu.addItem(.separator())
        add(menu, "New Signature…", #selector(W.newSignature(_:)))
        add(menu, "New Signature from Image…", #selector(W.newSignatureFromImage(_:)))
        add(menu, "Sign with Certificate…", #selector(W.signWithCertificate(_:)))
        add(menu, "Add Today's Date", #selector(W.insertTodaysDate(_:)))
        menu.addItem(.separator())
        add(menu, "Edit Text or Note", #selector(W.editSelectedAnnotation(_:)), "'")
        add(menu, "Add Image…", #selector(W.addImageToPage(_:)))
        return menu
    }

    private static func pagesMenu() -> NSMenu {
        let menu = NSMenu(title: "Pages")
        add(menu, "Rotate Left", #selector(W.rotateLeft(_:)), "l")
        add(menu, "Rotate Right", #selector(W.rotateRight(_:)), "r")
        add(menu, "Delete Pages", #selector(W.deletePages(_:)), String(UnicodeScalar(NSBackspaceCharacter)!))
        menu.addItem(.separator())
        add(menu, "Move Up", #selector(W.movePagesUp(_:)), String(UnicodeScalar(NSUpArrowFunctionKey)!), [.command, .option])
        add(menu, "Move Down", #selector(W.movePagesDown(_:)), String(UnicodeScalar(NSDownArrowFunctionKey)!), [.command, .option])
        add(menu, "Reverse Order", #selector(W.reversePages(_:)))
        menu.addItem(.separator())
        add(menu, "Insert from File…", #selector(W.insertFromFile(_:)), "i", [.command, .shift])
        add(menu, "Insert Blank Page", #selector(W.insertBlankPage(_:)), "b", [.command, .option])
        add(menu, "Headers & Footers…", #selector(W.addHeadersFooters(_:)))
        add(menu, "Crop Pages", #selector(W.chooseTool(_:)), object: Tool.crop.rawValue)
        add(menu, "Remove Crop", #selector(W.removeCrop(_:)))
        menu.addItem(.separator())
        add(menu, "Extract Selected Pages…", #selector(W.extractPages(_:)), "e", [.command, .option])
        add(menu, "Split Document…", #selector(W.splitDocument(_:)))
        add(menu, "Combine Files…", #selector(PaperAppDelegate.showCombine(_:)), target: NSApp.delegate as AnyObject?)
        menu.addItem(.separator())
        add(menu, "Apply Redactions…", #selector(W.applyRedactions(_:)))
        add(menu, "Remove All Redaction Marks", #selector(W.removeAllMarks(_:)))
        return menu
    }

    private static func windowMenu() -> NSMenu {
        let menu = NSMenu(title: "Window")
        add(menu, "Minimize", #selector(NSWindow.performMiniaturize(_:)), "m")
        add(menu, "Zoom", #selector(NSWindow.performZoom(_:)))
        menu.addItem(.separator())
        add(menu, "Bring All to Front", #selector(NSApplication.arrangeInFront(_:)))
        return menu
    }

    private static func helpMenu() -> NSMenu {
        let menu = NSMenu(title: "Help")
        let delegate = NSApp.delegate as AnyObject?
        add(menu, "Paper Help", #selector(PaperAppDelegate.showHelp(_:)), "?", target: delegate)
        menu.addItem(.separator())
        add(menu, IssueReport.Kind.problem.title, #selector(PaperAppDelegate.reportProblem(_:)), target: delegate)
        add(menu, IssueReport.Kind.improvement.title, #selector(PaperAppDelegate.suggestImprovement(_:)), target: delegate)
        return menu
    }
}

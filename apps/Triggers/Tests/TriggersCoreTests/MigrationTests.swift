import Foundation
import Testing
@testable import TriggersCore

/// Files written by Triggers 0.1 (schema 1, one action per binding) must load unchanged.
@Suite struct MigrationTests {
    /// Exactly what 0.1's encoder wrote (pretty-printed, sorted keys), for three kinds of binding.
    static let version1File = """
    {
      "apps" : [
        {
          "bundleID" : "com.apple.finder",
          "name" : "Finder",
          "usesAllAppsTriggers" : true
        }
      ],
      "bindings" : [
        {
          "action" : {
            "click" : {
              "_0" : "middle"
            }
          },
          "id" : "6F9619FF-8B86-D011-B42D-00C04FC964FF",
          "isEnabled" : true,
          "scope" : {
            "allApps" : {

            }
          },
          "trigger" : {
            "gesture" : {
              "_0" : {
                "fingers" : 3,
                "kind" : "tap"
              },
              "modifiers" : 0
            }
          }
        },
        {
          "action" : {
            "pressKeys" : {
              "_0" : {
                "keyCode" : 33,
                "modifiers" : 8
              }
            }
          },
          "id" : "7F9619FF-8B86-D011-B42D-00C04FC964FF",
          "isEnabled" : false,
          "scope" : {
            "app" : {
              "bundleID" : "com.apple.finder"
            }
          },
          "trigger" : {
            "mouseButton" : {
              "_0" : 3,
              "modifiers" : 0
            }
          }
        },
        {
          "action" : {
            "window" : {
              "_0" : "leftHalf"
            }
          },
          "id" : "8F9619FF-8B86-D011-B42D-00C04FC964FF",
          "isEnabled" : true,
          "scope" : {
            "browsers" : {

            }
          },
          "trigger" : {
            "gesture" : {
              "_0" : {
                "direction" : "left",
                "fingers" : 4,
                "kind" : "swipe"
              },
              "modifiers" : 2
            }
          }
        }
      ],
      "schemaVersion" : 1
    }
    """

    @Test func version1FileLoadsWithEachActionAsTheOnlyStep() throws {
        let config = try ConfigCodec.decode(Data(Self.version1File.utf8))
        #expect(config.schemaVersion == Config.currentSchema)
        #expect(config.bindings.count == 3)
        let tap = config.bindings[0]
        #expect(tap.trigger == .gesture(.tap(3), modifiers: []))
        #expect(tap.stepKinds == [.action(.click(.middle))])
        #expect(tap.conditions == .always)
        #expect(tap.scope == .allApps && tap.isEnabled)
        let button = config.bindings[1]
        #expect(button.trigger == .mouseButton(3, modifiers: []))
        #expect(button.firstAction == .pressKeys(KeyCombo(keyCode: 33, modifiers: .command)))
        #expect(!button.isEnabled && button.scope == .app(bundleID: "com.apple.finder"))
        let swipe = config.bindings[2]
        #expect(swipe.trigger == .gesture(.swipe(4, .left), modifiers: .option))
        #expect(swipe.isSingleAction)
        #expect(config.apps == [AppEntry(bundleID: "com.apple.finder", name: "Finder")])
    }

    @Test func migratedFileSavesAsVersion2AndRoundTrips() throws {
        let migrated = try ConfigCodec.decode(Data(Self.version1File.utf8))
        let data = try ConfigCodec.encode(migrated)
        let text = String(decoding: data, as: UTF8.self)
        #expect(text.contains("\"schemaVersion\" : 2"))
        #expect(text.contains("\"steps\""))
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        let bindings = json?["bindings"] as? [[String: Any]] ?? []
        #expect(bindings.count == 3 && bindings.allSatisfy { $0["action"] == nil && $0["steps"] != nil },
                "bindings store steps; the old single-action key isn't written any more")
        #expect(try ConfigCodec.decode(data) == migrated)
    }

    @Test func everythingNewRoundTrips() throws {
        let binding = TriggerBinding(
            trigger: .keySequence(.doubleTap(.command)),
            steps: [.action(.open(.app(bundleID: "com.apple.Notes", name: "Notes"))),
                    .waitUntil(.frontApp(bundleID: "com.apple.Notes", name: "Notes", isFront: true), timeout: 3),
                    .delay(0.25),
                    .action(.pressKeys(KeyCombo(keyCode: 45, modifiers: .command))),
                    .action(.typeText("Hello")),
                    .action(.media(.playPause)),
                    .action(.system(.toggleDarkMode)),
                    .action(.script(.shell, "echo hi")),
                    .action(.windowArea(UnitRect(x: 0.1, y: 0, width: 0.8, height: 1)))],
            conditions: ConditionSet(match: .any, [.power(.battery), .time(from: 22 * 60, to: 6 * 60), .days([1, 7]),
                                                   .display(.named("Studio Display")), .network(.wifi),
                                                   .modifiersHeld([.option]), .appearance(dark: true),
                                                   .appRunning(bundleID: "com.apple.Music", name: "Music", running: false)]),
            scope: .allApps)
        let gestures = Gesture.supported.map { TriggerBinding(trigger: .gesture($0, modifiers: []), action: .click(.middle), scope: .allApps) }
        let config = Config(bindings: [binding] + gestures)
        #expect(try ConfigCodec.decode(ConfigCodec.encode(config)) == config)
    }

    @Test func aFileFromANewerVersionIsRefused() {
        let newer = Data("{\"schemaVersion\": 3, \"bindings\": [], \"apps\": []}".utf8)
        #expect(throws: ConfigCodec.Failure.newerVersion(3)) { try ConfigCodec.decode(newer) }
    }

    @Test func importSkipsExactDuplicatesIncludingSteps() throws {
        let existing = TriggerBinding(trigger: .gesture(.tap(3), modifiers: []), action: .click(.middle), scope: .allApps)
        var config = Config(bindings: [existing])
        let sameSteps = TriggerBinding(trigger: existing.trigger, action: .click(.middle), scope: .allApps) // new step ids
        let withCondition = TriggerBinding(trigger: existing.trigger, action: .click(.middle), conditions: ConditionSet([.power(.battery)]), scope: .allApps)
        let merged = ConfigCodec.merge(Config(bindings: [sameSteps, withCondition]), into: config)
        #expect(merged.added == 1, "same input, steps and conditions is a duplicate; a different condition isn't")
        config = merged.config
        #expect(config.bindings.count == 2)
    }
}

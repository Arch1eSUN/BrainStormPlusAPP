//
//  Brainstorm_Tests.swift
//  Brainstorm+Tests
//
//  Created by Archie Sun on 4/14/26.
//

import Testing
import Foundation
@testable import Brainstorm_

struct Brainstorm_Tests {

    @Test func example() async throws {
        // Write your test here and use APIs like `#expect(...)` to check expected conditions.
        // Swift Testing Documentation
        // https://developer.apple.com/documentation/testing
    }

}

/// Sprint 3.0 RBAC parity verification — mirrors devprompt §4 checklist.
/// Pins the Web `src/lib/capabilities.ts` counts + legacy migration semantics +
/// excluded_capabilities subtraction so a silent drift in either side breaks CI.
struct RBAC_Sprint30_Tests {

    @Test func defaultCapabilitiesAdminCount() async throws {
        let caps = RBACManager.shared.defaultCapabilities[.admin] ?? []
        #expect(caps.count == 18)
    }

    @Test func defaultCapabilitiesSuperadminCount() async throws {
        let caps = RBACManager.shared.defaultCapabilities[.superadmin] ?? []
        #expect(caps.count == 30)
    }

    @Test func migrateLegacyChairpersonFoldsToSuperadmin() async throws {
        let result = RBACManager.shared.migrateLegacyRole("chairperson")
        #expect(result.primaryRole == .superadmin)
    }

    @Test func migrateLegacyHrDerivesCapabilities() async throws {
        let result = RBACManager.shared.migrateLegacyRole("hr")
        #expect(result.primaryRole == .employee)
        #expect(result.capabilities.contains(.hr_ops))
        #expect(result.capabilities.contains(.ai_resume_screening))
    }

    @Test func profileDecodesExcludedCapabilities() async throws {
        let json = """
        {
            "id": "11111111-1111-1111-1111-111111111111",
            "role": "admin",
            "excluded_capabilities": ["holiday_admin"]
        }
        """.data(using: .utf8)!
        let decoder = JSONDecoder()
        let profile = try decoder.decode(Profile.self, from: json)
        #expect(profile.excludedCapabilities == ["holiday_admin"])
    }

    @Test func effectiveCapabilitiesSubtractsExcluded() async throws {
        let json = """
        {
            "id": "22222222-2222-2222-2222-222222222222",
            "role": "admin",
            "excluded_capabilities": ["holiday_admin"]
        }
        """.data(using: .utf8)!
        let profile = try JSONDecoder().decode(Profile.self, from: json)
        let caps = RBACManager.shared.getEffectiveCapabilities(for: profile)
        #expect(!caps.contains(.holiday_admin))
        #expect(caps.contains(.hr_ops))
    }

    @Test func riskActionsGateMirrorsDbRls() async throws {
        #expect(RBACManager.shared.canManageRiskActions(rawRole: "admin") == true)
        #expect(RBACManager.shared.canManageRiskActions(rawRole: "hr_admin") == true)
        #expect(RBACManager.shared.canManageRiskActions(rawRole: "manager") == true)
        #expect(RBACManager.shared.canManageRiskActions(rawRole: "superadmin") == true)
        #expect(RBACManager.shared.canManageRiskActions(rawRole: "super_admin") == true)
        #expect(RBACManager.shared.canManageRiskActions(rawRole: "employee") == false)
        #expect(RBACManager.shared.canManageRiskActions(rawRole: nil) == false)
    }
}

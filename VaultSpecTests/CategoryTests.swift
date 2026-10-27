import Foundation
import Testing
@testable import VaultSpec

struct CategoryTests {
    private func settings() -> AppSettings {
        let suite = "categories-\(UUID().uuidString)"
        return AppSettings(defaults: UserDefaults(suiteName: suite)!)
    }

    @Test func customCategoriesAreSavedAndReused() {
        let defaults = UserDefaults(suiteName: "categories-\(UUID().uuidString)")!
        let first = AppSettings(defaults: defaults)
        #expect(first.addCategory("  Finance ") == "Finance")
        #expect(first.addCategory("finance") == "Finance")
        #expect(first.addCategory("work") == "Work")
        #expect(AppSettings(defaults: defaults).customCategories == ["Finance"])
    }

    @Test func allIsAFilterNotACategory() {
        let s = settings()
        #expect(s.addCategory("All") == nil)
        #expect(s.addCategory("   ") == nil)
        #expect(s.customCategories.isEmpty)
    }

    @Test func categoriesIncludeOnesThatOnlyExistOnAccounts() {
        let s = settings()
        s.addCategory("Finance")
        let restored = Account(issuer: "Bank", name: "me", secret: "JBSWY3DPEHPK3PXP", category: "Banking")
        #expect(s.categories(for: [restored]) == ["All", "Personal", "Work", "Social", "Finance", "Banking"])
    }

    @Test func longNamesAreShortened() {
        let s = settings()
        #expect(s.addCategory(String(repeating: "x", count: 40))?.count == AppSettings.maxCategoryLength)
    }
}

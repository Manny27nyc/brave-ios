// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import XCTest
import CoreData
import BraveShared
@testable import Data

class DomainTests: CoreDataTestCase {
    let fetchRequest = NSFetchRequest<Domain>(entityName: String(describing: Domain.self))
    
    // Should match but with different schemes
    let url = URL(string: "http://example.com")!
    let urlHTTPS = URL(string: "https://example.com")!
    
    let url2 = URL(string: "http://brave.com")!
    let url2HTTPS = URL(string: "https://brave.com")!
    
    private func entity(for context: NSManagedObjectContext) -> NSEntityDescription {
        return NSEntityDescription.entity(forEntityName: String(describing: Domain.self), in: context)!
    }
    
    func testGetOrCreate() {
        XCTAssertNotNil(Domain.getOrCreate(forUrl: url, persistent: true))
        XCTAssertEqual(try! DataController.viewContext.count(for: fetchRequest), 1)
        
        // Try to add the same domain again, verify no new object is created
        XCTAssertNotNil(Domain.getOrCreate(forUrl: url, persistent: true))
        XCTAssertEqual(try! DataController.viewContext.count(for: fetchRequest), 1)
        
        // Add another domain, verify that second object is created
        XCTAssertNotNil(Domain.getOrCreate(forUrl: url2, persistent: true))
        XCTAssertEqual(try! DataController.viewContext.count(for: fetchRequest), 2)
    }
    
    func testGetOrCreateURLs() {
        // This also validates that the schemes are being correctly saved
        XCTAssertEqual(url.absoluteString, Domain.getOrCreate(forUrl: url, persistent: true).url)
        XCTAssertEqual(url2.absoluteString, Domain.getOrCreate(forUrl: url2, persistent: true).url)
        
        let url3 = URL(string: "https://brave.com")!
        let url4 = URL(string: "data://brave.com")!
        XCTAssertEqual(url3.absoluteString, Domain.getOrCreate(forUrl: url3, persistent: true).url)
        XCTAssertEqual(url4.absoluteString, Domain.getOrCreate(forUrl: url4, persistent: true).url)
        XCTAssertEqual(try! DataController.viewContext.count(for: fetchRequest), 4)
    }
    
    func testDefaultShieldSettings() {
        
        let domain = Domain.getOrCreate(forUrl: url, persistent: true)
        XCTAssertTrue(domain.isShieldExpected(BraveShield.AdblockAndTp, considerAllShieldsOption: true))
        XCTAssertTrue(domain.isShieldExpected(BraveShield.SafeBrowsing, considerAllShieldsOption: true))
        XCTAssertFalse(domain.isShieldExpected(BraveShield.AllOff, considerAllShieldsOption: true))
        XCTAssertFalse(domain.isShieldExpected(BraveShield.NoScript, considerAllShieldsOption: true))
        XCTAssertFalse(domain.isShieldExpected(BraveShield.FpProtection, considerAllShieldsOption: true))
        
        XCTAssertEqual(domain.bookmarks?.count, 0)
        XCTAssertEqual(domain.historyItems?.count, 0)
        XCTAssertEqual(domain.url, url.domainURL.absoluteString)
    }
    
    func testAllShieldsOff() {
        let domain = Domain.getOrCreate(forUrl: url, persistent: true)
        
        backgroundSaveAndWaitForExpectation {
            Domain.setBraveShield(forUrl: url, shield: .AllOff, isOn: true, isPrivateBrowsing: false)
        }
        
        XCTAssertFalse(domain.isShieldExpected(BraveShield.AdblockAndTp, considerAllShieldsOption: true))
        XCTAssertTrue(domain.isShieldExpected(BraveShield.SafeBrowsing, considerAllShieldsOption: false))
        XCTAssertFalse(domain.isShieldExpected(BraveShield.AllOff, considerAllShieldsOption: true))
        XCTAssertFalse(domain.isShieldExpected(BraveShield.NoScript, considerAllShieldsOption: true))
        XCTAssertFalse(domain.isShieldExpected(BraveShield.FpProtection, considerAllShieldsOption: true))
        
        backgroundSaveAndWaitForExpectation {
            Domain.setBraveShield(forUrl: url, shield: .AllOff, isOn: false, isPrivateBrowsing: false)
        }
        
        XCTAssertTrue(domain.isShieldExpected(BraveShield.AdblockAndTp, considerAllShieldsOption: true))
        XCTAssertTrue(domain.isShieldExpected(BraveShield.SafeBrowsing, considerAllShieldsOption: true))
        XCTAssertFalse(domain.isShieldExpected(BraveShield.AllOff, considerAllShieldsOption: true))
        XCTAssertFalse(domain.isShieldExpected(BraveShield.NoScript, considerAllShieldsOption: true))
        XCTAssertFalse(domain.isShieldExpected(BraveShield.FpProtection, considerAllShieldsOption: true))
    }
    
    /// Tests non-HTTPSE shields
    func testNormalShieldSettings() {
        
        backgroundSaveAndWaitForExpectation {
            Domain.setBraveShield(forUrl: url2HTTPS, shield: .SafeBrowsing, isOn: true, isPrivateBrowsing: false)
        }
        
        backgroundSaveAndWaitForExpectation {
            Domain.setBraveShield(forUrl: url2HTTPS, shield: .AdblockAndTp, isOn: false, isPrivateBrowsing: false)
        }
        let domain = Domain.getOrCreate(forUrl: url2HTTPS, persistent: true)
        XCTAssertTrue(domain.isShieldExpected(BraveShield.SafeBrowsing, considerAllShieldsOption: true))
        
        // These should be the same in this situation
        XCTAssertFalse(domain.isShieldExpected(BraveShield.AdblockAndTp, considerAllShieldsOption: true))
        
        // Setting to "new" values
        // Setting to same value
        backgroundSaveAndWaitForExpectation {
            Domain.setBraveShield(forUrl: url2HTTPS, shield: .SafeBrowsing, isOn: true, isPrivateBrowsing: false)
        }
        
        backgroundSaveAndWaitForExpectation {
            Domain.setBraveShield(forUrl: url2HTTPS, shield: .AdblockAndTp, isOn: true, isPrivateBrowsing: false)
        }
        
        domain.managedObjectContext?.refreshAllObjects()
        XCTAssertTrue(domain.isShieldExpected(BraveShield.SafeBrowsing, considerAllShieldsOption: true))
        XCTAssertTrue(domain.isShieldExpected(BraveShield.AdblockAndTp, considerAllShieldsOption: true))
    }
}

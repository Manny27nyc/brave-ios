// This Source Code Form is subject to the terms of the Mozilla Public
// License, v. 2.0. If a copy of the MPL was not distributed with this
// file, You can obtain one at http://mozilla.org/MPL/2.0/.

import Foundation
import GCDWebServers
import Shared

struct SafeBrowsingHandler {
    static func register(_ webServer: WebServer) {
        webServer.registerMainBundleResource("SafeBrowsingError.html", module: "\(InternalURL.Path.errorpage)")
    }
}

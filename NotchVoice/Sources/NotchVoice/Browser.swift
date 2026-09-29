import AppKit

/// Page-level control of the front browser tab via AppleScript (+ JavaScript for clicks and page text).
/// Chrome-family: View → Developer → Allow JavaScript from Apple Events. Safari: Develop → Allow JavaScript from Apple Events.
enum Browser {
    static let chromium = ["com.google.Chrome": "Google Chrome", "com.brave.Browser": "Brave Browser",
                           "com.microsoft.edgemac": "Microsoft Edge", "company.thebrowser.Browser": "Arc",
                           "com.vivaldi.Vivaldi": "Vivaldi"]
    static let safari = "com.apple.Safari"

    struct Failure: Error { let message: String }

    /// The browser the user is in, if any.
    static var front: String? {
        guard let id = Actions.targetApp?.bundleIdentifier, chromium[id] != nil || id == safari else { return nil }
        return id
    }

    static func navigate(_ url: URL) {
        guard let id = front else { NSWorkspace.shared.open(url); return }  // default browser
        let u = quote(url.absoluteString)
        _ = try? run(id == safari
            ? "tell application \"Safari\" to set URL of current tab of front window to \(u)"
            : "tell application \"\(chromium[id]!)\" to set URL of active tab of front window to \(u)")
    }

    /// Runs JavaScript in the front tab and returns its string result.
    static func js(_ code: String) throws -> String {
        guard let id = front else { throw Failure(message: "no browser") }
        return try run(id == safari
            ? "tell application \"Safari\" to do JavaScript \(quote(code)) in current tab of front window"
            : "tell application \"\(chromium[id]!)\" to execute active tab of front window javascript \(quote(code))")
    }

    /// Clicks the n-th result/link (n = -1 for last). Returns its text.
    static func openNth(_ n: Int) throws -> String {
        try js(#"""
        (function(n){
          var h = location.hostname, sel;
          if (/(^|\.)google\./.test(h) && location.pathname == '/search') sel = '#search a:has(h3)';
          else if (/youtube\.com$/.test(h)) sel = 'a#video-title, a#video-title-link';
          else if (/duckduckgo\.com$/.test(h)) sel = 'a[data-testid=result-title-a]';
          else if (/bing\.com$/.test(h)) sel = '#b_results h2 a';
          var els = sel ? Array.from(document.querySelectorAll(sel)) : [];
          if (!els.length) els = Array.from(document.querySelectorAll('main a[href], article a[href], [role=main] a[href]'));
          if (!els.length) els = Array.from(document.querySelectorAll('a[href]')).filter(a => !a.closest('nav,header,footer,aside'));
          els = els.filter(a => a.offsetParent !== null && (a.innerText || a.getAttribute('aria-label') || '').trim().length > 1);
          var a = n < 0 ? els[els.length - 1] : els[n - 1];
          if (!a) return '';
          a.scrollIntoView({block: 'center'}); a.click();
          return (a.innerText || a.getAttribute('aria-label')).trim().slice(0, 80);
        })(\#(n))
        """#)
    }

    /// Clicks the link/button whose visible text best matches. Returns its text, "" if none.
    static func click(_ text: String) throws -> String {
        try js(#"""
        (function(t){
          var els = Array.from(document.querySelectorAll('a, button, [role=button], [role=link], [role=tab], [role=menuitem], input[type=submit], input[type=button], summary, label'))
            .filter(e => e.offsetParent !== null);
          var name = e => (e.innerText || e.value || e.getAttribute('aria-label') || e.title || '').trim().toLowerCase().replace(/\s+/g, ' ');
          var hit = els.find(e => name(e) == t) || els.find(e => name(e).startsWith(t)) || els.find(e => name(e).includes(t));
          if (!hit) return '';
          hit.scrollIntoView({block: 'center'}); hit.click();
          return name(hit).slice(0, 80);
        })(\#(quote(text)))
        """#)
    }

    /// Focuses the page's main text box (chat prompt, search box…) unless an editable element already has focus.
    static func focusInput() throws -> String {
        try js(#"""
        (function(){
          var ed = e => e && (e.isContentEditable || e.tagName == 'TEXTAREA' ||
                   (e.tagName == 'INPUT' && /^(text|search|email|url|)$/.test(e.type)));
          if (ed(document.activeElement)) return 'kept';
          var els = Array.from(document.querySelectorAll('textarea, [contenteditable=true], [contenteditable=""], [role=textbox], input[type=text], input[type=search], input:not([type])'))
            .filter(e => e.offsetParent !== null && !e.disabled && !e.readOnly);
          if (!els.length) return '';
          var label = e => [e.id, e.getAttribute('aria-label'), e.getAttribute('placeholder'), e.getAttribute('data-placeholder'), e.getAttribute('name')].join(' ');
          var area = e => { var r = e.getBoundingClientRect(); return r.width * r.height; };
          var t = els.find(e => /prompt|message|chat|ask|compose|reply|search|query/i.test(label(e))) ||
                  els.sort((x, y) => area(y) - area(x))[0];
          t.scrollIntoView({block: 'center'}); t.focus();
          if (t.isContentEditable) {  // caret at the end
            var r = document.createRange(); r.selectNodeContents(t); r.collapse(false);
            var s = getSelection(); s.removeAllRanges(); s.addRange(r);
          }
          return 'focused';
        })()
        """#)
    }

    static func pageText() throws -> (title: String, text: String) {
        let title = (try? js("document.title")) ?? "this page"
        return (title, try js("(document.querySelector('main,article,[role=main]') || document.body).innerText.slice(0, 60000)"))
    }

    /// "search for x" -> Google; "go to github.com" / "go to youtube" -> site.
    static func url(forSite s: String) -> URL? {
        // Words.normalize turned "github.com" into "github com": re-join a trailing TLD.
        var w = s.replacingOccurrences(of: " dot ", with: ".").split(separator: " ").map(String.init)
        if w.count > 1, ["com", "org", "net", "io", "dev", "ai", "in", "co", "app", "me"].contains(w.last!) {
            w = [w.dropLast().joined() + "." + w.last!]
        }
        let t = w.joined()
        guard !t.isEmpty else { return nil }
        // ponytail: bare names guess .com; add a site map if that guesses wrong for sites you use
        return URL(string: t.hasPrefix("http") ? t : "https://" + (t.contains(".") ? t : "www.\(t).com"))
    }

    static func searchURL(_ q: String) -> URL {
        var c = URLComponents(string: "https://www.google.com/search")!
        c.queryItems = [URLQueryItem(name: "q", value: q)]
        return c.url!
    }

    private static func quote(_ s: String) -> String {
        "\"" + s.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
    }

    private static func run(_ source: String) throws -> String {
        var err: NSDictionary?
        let out = NSAppleScript(source: source)?.executeAndReturnError(&err)
        if let err { throw Failure(message: err[NSAppleScript.errorMessage] as? String ?? "\(err)") }
        return out?.stringValue ?? ""
    }

    static func check() {
        assert(url(forSite: "github.com")?.absoluteString == "https://github.com")
        assert(url(forSite: "youtube")?.absoluteString == "https://www.youtube.com")
        assert(url(forSite: "news dot ycombinator dot com")?.absoluteString == "https://news.ycombinator.com")
        assert(url(forSite: "github com")?.absoluteString == "https://github.com")
        assert(searchURL("best running shoes").absoluteString == "https://www.google.com/search?q=best%20running%20shoes")
        print("Browser ok")
    }
}

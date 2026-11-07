import DevkitCore
import Foundation

/// Example inputs for each tool's Sample button. Our own text, nothing sensitive.
enum Samples {
    static let json = #"{"name":"Devkit","version":2,"offline":true,"tools":["JSON","JWT","Base64"],"limits":{"maxInput":"50 MB","bigNumber":12345678901234567890},"owner":null}"#

    static let jsonArray = #"[{"id":1,"name":"Ada Lovelace","email":"ada@example.com","address":{"city":"London","zip":"W1"}},{"id":2,"name":"Grace Hopper","email":"grace@example.com","address":{"city":"New York","zip":"10001"}}]"#

    static let yaml = """
    # Service settings
    service: devkit
    port: 8080
    debug: false
    country: no          # stays a string in YAML 1.2
    defaults: &defaults
      timeout: 30
      retries: 3
    production:
      <<: *defaults
      retries: 5
    hosts:
      - name: alpha
        ip: 10.0.0.1
      - name: beta
        ip: 10.0.0.2
    notes: |
      Multi-line text
      keeps its line breaks.
    """

    static let csv = """
    id,name,email,zip,active
    1,Ada Lovelace,ada@example.com,02134,true
    2,"Hopper, Grace",grace@example.com,10001,false
    3,Alan Turing,alan@example.com,,true
    """

    static let html = #"<!DOCTYPE html><html lang="en"><head><meta charset="utf-8"><title>Devkit</title><style>body{font:14px system-ui}</style></head><body><header><h1>Hello</h1><nav><a href="/">Home</a> | <a href="/docs">Docs</a></nav></header><main><p>Format <b>HTML</b>, <i>CSS</i> and more.</p><ul><li>Offline</li><li>Fast</li></ul><img src="logo.png" alt="Logo"></main></body></html>"#

    static let xml = #"<?xml version="1.0" encoding="UTF-8"?><catalog><book id="bk101"><author>Gambardella, Matthew</author><title>XML Developer's Guide</title><price currency="USD">44.95</price><tags><tag>xml</tag><tag>guide</tag></tags></book><book id="bk102"><author>Ralls, Kim</author><title>Midnight Rain</title><price currency="USD">5.95</price></book></catalog>"#

    static let css = "/* Buttons */ .button,.button:hover{color:#fff;background:linear-gradient(#36c,#147);padding:4px 12px;border-radius:6px}@media (prefers-color-scheme:dark){.button{color:#eee}}"

    static let sql = "select u.id, u.name, count(o.id) as orders, sum(o.total) as spent from users u left join orders o on o.user_id = u.id where u.active = true and o.created_at >= '2024-01-01' group by u.id, u.name having count(o.id) > 2 order by spent desc limit 20;"

    static let svg = """
    <svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24">
      <circle cx="12" cy="12" r="10" fill="#36c"/>
      <path d="M7 12l3 3 7-7" stroke="#fff" stroke-width="2" fill="none"/>
    </svg>
    """

    static let htmlText = "<p class=\"note\">Tom & Jerry's café — “quotes” © 2024</p>"

    static let escapeText = "Line one\n\tIndented \"quoted\" text with a back\\slash and an emoji 😀"

    static let lines = """
    banana
    Apple
    cherry
    banana
    apple
    10 items
    2 items

    cherry
    """

    static let url = "https://user@example.com:8443/search/results?q=offline+dev+tools&lang=en&tag=json&tag=jwt#top"

    static let inspector = "Café crème, naïve résumé 👨‍👩‍👧 — Straße 2024!\nSecond line with a tab\there."

    static let jwt = "eyJ0eXAiOiJKV1QiLA0KICJhbGciOiJIUzI1NiJ9.eyJpc3MiOiJqb2UiLA0KICJleHAiOjEzMDA4MTkzODAsDQogImh0dHA6Ly9leGFtcGxlLmNvbS9pc19yb290Ijp0cnVlfQ.dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk"

    /// Let's Encrypt's public ISRG Root X2 certificate.
    static let certificate = """
    -----BEGIN CERTIFICATE-----
    MIICGzCCAaGgAwIBAgIQQdKd0XLq7qeAwSxs6S+HUjAKBggqhkjOPQQDAzBPMQsw
    CQYDVQQGEwJVUzEpMCcGA1UEChMgSW50ZXJuZXQgU2VjdXJpdHkgUmVzZWFyY2gg
    R3JvdXAxFTATBgNVBAMTDElTUkcgUm9vdCBYMjAeFw0yMDA5MDQwMDAwMDBaFw00
    MDA5MTcxNjAwMDBaME8xCzAJBgNVBAYTAlVTMSkwJwYDVQQKEyBJbnRlcm5ldCBT
    ZWN1cml0eSBSZXNlYXJjaCBHcm91cDEVMBMGA1UEAxMMSVNSRyBSb290IFgyMHYw
    EAYHKoZIzj0CAQYFK4EEACIDYgAEzZvVn4CDCuwJSvMWSj5cz3es3mcFDR0HttwW
    +1qLFNvicWDEukWVEYmO6gbf9yoWHKS5xcUy4APgHoIYOIvXRdgKam7mAHf7AlF9
    ItgKbppbd9/w+kHsOdx1ymgHDB/qo0IwQDAOBgNVHQ8BAf8EBAMCAQYwDwYDVR0T
    AQH/BAUwAwEB/zAdBgNVHQ4EFgQUfEKWrt5LSDv6kviejM9ti6lyN5UwCgYIKoZI
    zj0EAwMDaAAwZQIwe3lORlCEwkSHRhtFcP9Ymd70/aTSVaYgLXTWNLxBo1BfASdW
    tL4ndQavEi51mI38AjEAi/V3bNTIZargCyzuFJ0nN6T5U6VR5CmD1/iQMVtCnwr1
    /q4AaOeMSQ+2b1tbFfLn
    -----END CERTIFICATE-----
    """

    static let regexPattern = #"(?<user>[\w.]+)@(?<domain>[\w-]+\.\w+)"#
    static let regexText = "Write to ada@example.com or grace.hopper@navy.mil.\nNot an address: @handle"
    static let diffOriginal = "name: Devkit\nversion: 1\ntools: 12\noffline: yes\n"
    static let diffChanged = "name: Devkit\nversion: 2\ntools: 33\noffline: yes\nmenu bar: optional\n"
}

// Samples for the tools from the first release.
extension JSONToolModel { var sampleInput: String? { Samples.json } }
extension JWTToolModel { var sampleInput: String? { Samples.jwt } }
extension Base64ToolModel { var sampleInput: String? { mode == .encode ? "Hello, Devkit! ✓" : "SGVsbG8sIERldmtpdCEg4pyT" } }
extension URLToolModel { var sampleInput: String? { mode == .encode ? "name=Ada Lovelace & co/2024?" : "name%3DAda%20Lovelace%20%26%20co%2F2024%3F" } }
extension TimestampToolModel { var sampleInput: String? { "1730592000" } }
extension HashToolModel { var sampleInput: String? { "The quick brown fox jumps over the lazy dog" } }
extension ColorToolModel { var sampleInput: String? { "#3366CC" } }
extension NumberBaseToolModel { var sampleInput: String? { "0xFF_FF" } }
extension CaseToolModel { var sampleInput: String? { "user account id\nHTTPRequestHandler" } }
extension UUIDToolModel { var sampleInput: String? { "01932c07-209c-7c8a-9f3d-b4c7a8e6a1f2" } }

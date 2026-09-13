import Foundation
@testable import money_

/// Rows copied from a real Trade Republic `Transaktionsexport`, with counterparty names
/// and IBANs replaced. Merchant names are left alone — they are what the categorizer will
/// have to work with.
enum CSVFixtures {
    static let header = #""datetime","date","account_type","category","type","asset_class","name","symbol","shares","price","amount","fee","tax","currency","original_amount","original_currency","fx_rate","description","transaction_id","counterparty_name","counterparty_iban","payment_reference","mcc_code""#

    static let export = header + "\n" + #"""
    "2026-08-01T07:21:40.507672Z","2026-08-01","DEFAULT","CASH","INTEREST_PAYMENT","","","","","","1.940000","","","EUR","","","","Interest payment for payout collection 019fbb6c-638e-7234-9a5f-8bb246bf79e9","019fbc33-359b-71e8-b5dc-4cd8f8498cad","","","",""
    "2026-08-03T06:59:18.008124Z","2026-08-03","DEFAULT","CASH","TRANSFER_INBOUND","","PayPal Europe S.a.r.l. et Cie S.C.A","","","","39.210000","","","EUR","","","","Incoming transfer from PayPal Europe S.a.r.l. et Cie S.C.A","019fc66b-7178-7680-91b4-2ef2a4d516cf","PayPal Europe S.a.r.l. et Cie S.C.A","LU00000000000000000E","",""
    "2026-08-03T08:02:42.210468Z","2026-08-03","DEFAULT","CASH","CARD_TRANSACTION","","I love leo sagt Danke","","","","-7.000000","","","EUR","","","","I love leo sagt Danke","019fc6a5-7da2-76ca-9205-27c13fd779c6","","","","5814"
    "2026-08-03T15:17:41.750Z","2026-08-03","DEFAULT","TRADING","BUY","STOCK","NVIDIA","US67066G1040","0.0836220000","178.4200000000","-14.92","","","EUR","","","","Savings plan execution US67066G1040 NVIDIA CORP.      DL-,001, quantity: 0.083622","f04cafb6-b491-46e3-9324-c5c280c37faa","","","",""
    "2026-08-04T06:51:37.494483Z","2026-08-04","DEFAULT","CASH","TRANSFER_DIRECT_DEBIT_INBOUND","","Redacted Person","","","","-12.570000","","","EUR","","","","Sepa Direct Debit transfer","019fcb8a-c696-7cf2-ab11-2ecef4d45c41","Redacted Person","DE00000000000000000000","",""
    "2026-08-04T12:05:45.598945Z","2026-08-04","DEFAULT","CASH","CARD_TRANSACTION","","EDEKA Muenchen. Impler","","","","-36.750000","","","EUR","","","","EDEKA MUENCHEN. IMPLER","019fccaa-5ffe-74ba-abbb-969255669474","","","","5411"
    "2026-08-06T10:15:11.315554Z","2026-08-06","DEFAULT","CASH","CARD_TRANSACTION","","ALTE UTTING","","","","2.000000","","","EUR","","","","Alte Utting","019fd691-dcd3-7b6c-ac2d-b9e132e7e50d","","","","5812"
    "2026-08-13T08:26:20.389471Z","2026-08-13","DEFAULT","CASH","DIVIDEND","STOCK","Apple","US0378331005","0.0828000000","","0.020000","","","EUR","0.02","USD","0.866176","Cash Dividend for ISIN US0378331005","019ffa3a-b965-7251-a889-d17969640b62","","","",""
    "2026-08-14T06:19:49.666Z","2026-08-14","DEFAULT","TRADING","SELL","STOCK","Apple","US0378331005","-0.0828000000","264.9000000000","21.93","-1.00","","EUR","","","","Sell trade US0378331005 APPLE INC., quantity: 0.0828","c747c2e6-d65b-48c7-8d91-3bf4e13882cb","","","",""
    "2025-08-20T15:00:04.759491Z","2025-08-20","DEFAULT","CASH","CARD_TRANSACTION_INTERNATIONAL","","UBUDPASAR ADLDPS","","","","-53.060000","-1.00","","EUR","-999246.70","IDR","0.000053","UBUDPASAR ADLDPS, 1.018.846,59 IDR, exchange rate: 0,0000531, ECB rate: 0,0000527158, markup: 0,72881375 %","bc82b0be-fa09-4fea-a274-a259124c6e94","","","","6011"
    "2024-05-15T12:15:59.231683Z","2024-05-15","DEFAULT","CASH","CARD_ORDERING_FEE","","","","","","0.000000","-5.00","","EUR","","","","Trade Republic Card","b3dd87a9-7c92-49f2-8242-defc1fd43740","","","",""
    """#

    static let rowCount = 11

    /// Builds a CSV by placing values under their header names, so tests never depend on
    /// column order either.
    static func csv(header: String = CSVFixtures.header, rows: [[CSVColumn: String]]) -> String {
        let names = header.split(separator: ",").map {
            $0.trimmingCharacters(in: CharacterSet(charactersIn: "\" "))
        }
        let lines = rows.map { row -> String in
            names.map { name in
                let value = CSVColumn(rawValue: name).flatMap { row[$0] } ?? ""
                return "\"\(value)\""
            }
            .joined(separator: ",")
        }
        return ([header] + lines).joined(separator: "\n")
    }

    /// A minimal row that parses, for tests that only care about one field.
    static let baseRow: [CSVColumn: String] = [
        .datetime: "2026-08-04T12:05:45.598945Z",
        .date: "2026-08-04",
        .accountType: "DEFAULT",
        .category: "CASH",
        .type: "CARD_TRANSACTION",
        .name: "EDEKA",
        .amount: "-10.000000",
        .currency: "EUR",
        .description: "EDEKA",
        .transactionID: "019fccaa-5ffe-74ba-abbb-969255669474",
        .mccCode: "5411",
    ]

    static func row(_ overrides: [CSVColumn: String]) -> [CSVColumn: String] {
        baseRow.merging(overrides) { _, new in new }
    }
}

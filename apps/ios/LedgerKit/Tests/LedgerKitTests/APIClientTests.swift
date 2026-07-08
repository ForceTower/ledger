import Foundation
import Testing

@testable import LedgerKit

struct APIClientTests {
    @Test
    func endpointDefaultsToHTTPSHonorsSchemesAndJoinsPaths() {
        #expect(
            APIClient.endpoint(address: "nfce.meucasa.app", path: "scan", query: [])?.absoluteString
                == "https://nfce.meucasa.app/scan"
        )
        #expect(
            APIClient.endpoint(address: "http://192.168.0.10:3000", path: "purchases/abc", query: [])?
                .absoluteString == "http://192.168.0.10:3000/purchases/abc"
        )
        #expect(
            APIClient.endpoint(
                address: " nfce.meucasa.app/api/ ",
                path: "purchases",
                query: [URLQueryItem(name: "page", value: "2")]
            )?.absoluteString == "https://nfce.meucasa.app/api/purchases?page=2"
        )
        #expect(APIClient.endpoint(address: "", path: "scan", query: []) == nil)
    }

    @Test
    func scanResponseDecodesTheWirePayload() throws {
        let json = """
            {
              "status": "saved",
              "purchase": {
                "id": "2026-07-01_atacadao_teste_01",
                "date": "2026-07-01",
                "time": "14:44:08",
                "source": "nfce",
                "store": {
                  "name": "Atacadão Teste",
                  "legalName": "ATACADAO S.A.",
                  "cnpj": "75315333000109",
                  "address": "Av. Teste, 100"
                },
                "receipt": {
                  "number": 123456,
                  "series": 1,
                  "accessKey": "29260326000000000000650010000000001000000001"
                },
                "items": [
                  {
                    "seq": 1,
                    "description": "Bacon Fatiado Seara",
                    "code": "123",
                    "barcode": "7894904571708",
                    "quantity": 1,
                    "unit": "un",
                    "unitPrice": 23.9,
                    "total": 23.9,
                    "category": "meat"
                  },
                  {
                    "seq": 2,
                    "description": "Arroz Branco 5kg",
                    "code": "456",
                    "barcode": null,
                    "quantity": 2,
                    "unit": "un",
                    "unitPrice": 25,
                    "total": 50,
                    "category": "grocery"
                  }
                ],
                "totals": { "itemCount": 3, "gross": 73.9, "discount": 0, "totalPaid": 73.9 },
                "payments": [{ "code": 3, "method": "Cartão de Crédito", "amount": 73.9 }],
                "taxesTotal": 12.34
              },
              "warnings": ["A soma dos itens não bate com o total"]
            }
            """

        let response = try JSONDecoder().decode(ScanResponse.self, from: Data(json.utf8))
        #expect(response.status == .saved)
        #expect(response.purchase.id == "2026-07-01_atacadao_teste_01")
        #expect(response.purchase.store.name == "Atacadão Teste")
        #expect(response.purchase.items.count == 2)
        #expect(response.purchase.items[1].barcode == nil)
        #expect(response.purchase.totals.totalPaid == 73.9)
        #expect(response.purchase.payments.first?.change == nil)
        #expect(response.warnings.count == 1)
    }
}

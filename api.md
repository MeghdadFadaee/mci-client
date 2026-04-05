# Authenticate

## Create session

### request

```bash
curl 'https://my.mci.ir/api/idm/v1/auth' \
  -X POST \
  -H 'Content-Type: application/json' \
  --data-raw '{"username":"9123456789","credential":"xxxx","credential_type":"PASSWORD"}'
```

### response

```json
{
  "access_token": "eyJhbG...",
  "expires_in": 1800,
  "refresh_token": "eyJhbG...",
  "refresh_expires_in": 2522000,
  "session_state": "111_222_333"
}
```

---

## Refresh session

### request

```bash
curl 'https://my.mci.ir/api/idm/v1/auth' \
  -X POST \
  -H 'Authorization: Bearer eyJhbG...' \
  -H 'Content-Type: application/json' \
  --data-raw '{"username":"9123456789","credential_type":"REFRESH_TOKEN","credential":"eyJhbG..."}'
```

### response

```json
{
  "access_token": "eyJhbG...",
  "expires_in": 1800,
  "refresh_token": "eyJhbG...",
  "refresh_expires_in": 2522000,
  "session_state": "111_222_333"
}
```

---

# Packages

## Refresh session

### request

```bash
curl 'https://my.mci.ir/api/unit/v1/packages/details' \
  -H 'Authorization: Bearer eyJhbG...'
```

### response

```json
{
  "packageItems": [
    {
      "type": "internet",
      "formattedExpireTime": "۱۵:۵۵:۱۳ - ۱۴۰۵/۰۵/۰۴",
      "expireTime": "2026-07-26T15:55:13",
      "effectiveTime": "2026-03-28T15:55:13",
      "formattedEffectiveTime": "۱۵:۵۵:۱۳ - ۱۴۰۵/۰۱/۰۸",
      "remainingDays": "111 روز باقی‌مانده",
      "totalInitValue": 100.06,
      "totalUnusedValue": 12.71,
      "totalUnitName": "گیگ",
      "unUsedUnitName": "گیگ",
      "packageStatus": "active",
      "packageStatusText": "فعال",
      "offerName": "بسته اینترنت 120 روزه 100 گیگابایت",
      "remainingText": "باقی مانده از",
      "offeringId": "501460",
      "itemDetails": [
        {
          "colourCodeUnused": "#00AECD",
          "colourCodeUsed": "#F1F5F9",
          "colourCodeUsedDark": "#101214",
          "shortName": "12.71 گیگ عادی",
          "initAmount": 107437096960,
          "unusedAmount": 13651190514,
          "freeUnitType": "C_5007",
          "offeringId": "501460",
          "internalItemDetails": [
            "معادل 34.36 گیگ ترافیک داخلی",
            "معادل 50.85 گیگ پیام رسان داخلی"
          ]
        }
      ],
      "freeUnit": true,
      "autoRenewal": false,
      "isFreeUnit": true,
      "isAutoRenewal": false
    }
  ],
  "totalInitBytes": 100.06,
  "totalUnusedBytes": 12.71,
  "bytesInitUnit": "گیگ",
  "bytesUnit": "گیگ",
  "bytesUnusedUnit": "گیگ",
  "totalInitMessages": 0.0,
  "totalUnusedMessages": 0.0,
  "messagesUnit": "عدد",
  "totalInitCall": 0.0,
  "totalUnusedCall": 0.0,
  "showableTextCall": "باقی مانده از",
  "showableTextBytes": "باقی مانده از",
  "showableTextMessage": "باقی مانده از"
}
```

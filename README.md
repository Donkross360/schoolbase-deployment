# SchoolBase Mobile

Flutter companion app for SchoolBase attendance.

## Current attendance flow

Teachers sign in on an NFC capable Android phone, select an assigned class in the active academic session, and scan a student's card. The app confirms attendance only after the backend records it. A repeated scan shows that the student was already marked present. An internet connection is required; a failed request is not counted as attendance.

Admins can link a student's existing card by scanning it in Card Management. An NDEF text record is used as the card ID when present; otherwise the hardware UID is used. Web generated `NFC-...` IDs must be written as NDEF text to the physical tag before use. Existing IDs restored from the database remain valid when the tag contains the same text.

The earlier gate attendance screen is unavailable because `/attendance/gate` is absent from the current backend. Face and fingerprint identification are not enabled.

The school policy endpoint controls which methods appear to teachers. NFC is the
only available method until a face recognition provider and a reader capture
provider are integrated. `FingerprintCapture` is the replaceable mobile reader
interface; its default provider ID is `secugen`. The SecuGen channel currently
reports unavailable because the vendor Android SDK is not bundled.

## Run

Install Flutter and an Android device with NFC, then run:

```bash
flutter pub get
flutter run --dart-define=SCHOOLBASE_API_BASE=https://your-school.example/api/v1
```

The default backend URL is `https://demo.schoolbase.africa/api/v1`. Apply the backend NFC attendance migration before using this app. A real device test is needed to verify NFC tag compatibility and the full check-in flow.

This project is private and not licensed for public use.

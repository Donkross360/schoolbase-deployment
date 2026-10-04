# Face attendance setup

Face attendance uses the teacher's Android camera and a self-hosted CompreFace **Face Verification** service. The backend sends the fresh camera image and one admin-approved student photo for a one-to-one comparison. CompreFace does not need a collection of student face embeddings for this integration.

1. Deploy [CompreFace](https://github.com/exadel-inc/CompreFace/blob/master/docs/Installation-options.md) on a server reachable **from the SchoolBase backend**. Its default deployment runs several containers and requires an x86 CPU with AVX support. Keep the CompreFace API private to the school network.
2. In the CompreFace dashboard, create a **Face Verification** service and copy its API key. The recognition and detection service keys are different and will not work for the verification endpoint.
3. Configure the SchoolBase backend environment:

   ```text
   FACE_VERIFY_URL=http://compreface:8000
   FACE_VERIFY_API_KEY=<face-verification-service-key>
   FACE_MATCH_THRESHOLD=0.8
   ```

   `FACE_VERIFY_URL` is the CompreFace base URL. The backend appends `/api/v1/verification/verify`. Keep the URL and key on the backend; never put the key in the Android APK or browser. Choose a similarity threshold after testing with the school's cameras, lighting and student photos. A higher value rejects more legitimate check-ins but reduces false matches. The default is 0.8.
4. Deploy the new combined image and restart the backend. In Admin Settings, enable **Face** alongside or instead of NFC. Face is unavailable if the URL or key is missing.
5. Each student takes a new photo in their portal settings. When using a separate phone, they can scan the short-lived QR code shown beside the capture link. On the admin's student page, visually review and approve the photo. Replacing the photo automatically removes approval.
6. Teachers can select an approved student from their assigned class in the Android app or the teacher web portal. The Android app asks the student to perform one randomly chosen movement (blink, open mouth, nod, or turn left/right), observes the movement and return to neutral, then takes a fresh photo for verification. The web portal supports a camera on a phone, tablet, or laptop, but relies on the teacher to supervise the student rather than checking a movement automatically.

The movement prompt is a basic on-device presence check; it is not certified liveness detection and a replayed video or altered app may defeat it. Keep the teacher present and do not use this flow as unattended or high-security identity proof. Failed comparisons do not mark attendance; use the school's normal correction process when a legitimate student cannot be verified. The backend does not save the check-in camera image; it stores the attendance result and match score. See [CompreFace's verification API](https://github.com/exadel-inc/CompreFace/blob/master/docs/Rest-API-description.md#face-verification-service) for the provider contract.

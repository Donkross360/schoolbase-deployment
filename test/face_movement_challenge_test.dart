import 'package:flutter_test/flutter_test.dart';
import 'package:school_base/services/face_movement_challenge.dart';

void main() {
  test('a blink needs an open, closed, then open sequence', () {
    final challenge = FaceMovementChallenge(movement: FaceMovement.blink);
    const open = FaceObservation(leftEyeOpen: 0.9, rightEyeOpen: 0.9);
    const closed = FaceObservation(leftEyeOpen: 0.1, rightEyeOpen: 0.1);

    expect(challenge.observe(closed), isFalse);
    expect(challenge.stage, ChallengeStage.neutral);
    challenge.observe(open);
    challenge.observe(open);
    expect(challenge.stage, ChallengeStage.action);
    challenge.observe(closed);
    challenge.observe(closed);
    expect(challenge.stage, ChallengeStage.returnToNeutral);
    expect(challenge.observe(open), isFalse);
    expect(challenge.observe(open), isTrue);
  });

  test('turning cannot complete after a face tracking reset', () {
    final challenge = FaceMovementChallenge(movement: FaceMovement.turnLeft);
    const straight = FaceObservation(yaw: 0);
    const left = FaceObservation(yaw: 25);
    challenge.observe(straight);
    challenge.observe(straight);
    challenge.observe(left);
    challenge.reset();
    expect(challenge.observe(straight), isFalse);
    expect(challenge.stage, ChallengeStage.neutral);
  });

  test('mouth opening and nodding require a return to neutral', () {
    final examples = [
      (
        FaceMovement.openMouth,
        const FaceObservation(mouthGap: 0.005),
        const FaceObservation(mouthGap: 0.07),
      ),
      (
        FaceMovement.nod,
        const FaceObservation(pitch: 1),
        const FaceObservation(pitch: 23),
      ),
    ];
    for (final (movement, neutral, action) in examples) {
      final challenge = FaceMovementChallenge(movement: movement);
      challenge.observe(neutral);
      challenge.observe(neutral);
      challenge.observe(action);
      challenge.observe(action);
      expect(challenge.stage, ChallengeStage.returnToNeutral);
      expect(challenge.observe(action), isFalse);
      challenge.observe(neutral);
      expect(challenge.observe(neutral), isTrue);
    }
  });
}

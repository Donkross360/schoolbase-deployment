import 'dart:math';

enum FaceMovement { blink, openMouth, nod, turnLeft, turnRight }

enum ChallengeStage { neutral, action, returnToNeutral, complete }

class FaceObservation {
  final double? leftEyeOpen;
  final double? rightEyeOpen;
  final double? mouthGap;
  final double? pitch;
  final double? yaw;

  const FaceObservation({
    this.leftEyeOpen,
    this.rightEyeOpen,
    this.mouthGap,
    this.pitch,
    this.yaw,
  });
}

class FaceMovementChallenge {
  FaceMovementChallenge({FaceMovement? movement})
    : movement = movement ?? FaceMovement.values[Random.secure().nextInt(5)];

  final FaceMovement movement;
  ChallengeStage stage = ChallengeStage.neutral;
  int _consecutive = 0;

  String get instruction => switch (movement) {
    FaceMovement.blink => 'Blink both eyes',
    FaceMovement.openMouth => 'Open your mouth',
    FaceMovement.nod => 'Nod your head up or down',
    FaceMovement.turnLeft => 'Turn your head to your left',
    FaceMovement.turnRight => 'Turn your head to your right',
  };

  String get prompt => switch (stage) {
    ChallengeStage.neutral => 'Look straight at the camera with your eyes open',
    ChallengeStage.action => instruction,
    ChallengeStage.returnToNeutral => 'Look straight at the camera again',
    ChallengeStage.complete => 'Movement confirmed',
  };

  void reset() {
    stage = ChallengeStage.neutral;
    _consecutive = 0;
  }

  bool observe(FaceObservation observation) {
    if (stage == ChallengeStage.complete) return true;
    final matched = switch (stage) {
      ChallengeStage.neutral ||
      ChallengeStage.returnToNeutral => _isNeutral(observation),
      ChallengeStage.action => _isAction(observation),
      ChallengeStage.complete => true,
    };
    _consecutive = matched ? _consecutive + 1 : 0;
    if (_consecutive < 2) return false;
    _consecutive = 0;
    stage = switch (stage) {
      ChallengeStage.neutral => ChallengeStage.action,
      ChallengeStage.action => ChallengeStage.returnToNeutral,
      ChallengeStage.returnToNeutral ||
      ChallengeStage.complete => ChallengeStage.complete,
    };
    return stage == ChallengeStage.complete;
  }

  bool _isNeutral(FaceObservation face) => switch (movement) {
    FaceMovement.blink =>
      (face.leftEyeOpen ?? 0) > 0.7 && (face.rightEyeOpen ?? 0) > 0.7,
    FaceMovement.openMouth => face.mouthGap != null && face.mouthGap! < 0.018,
    FaceMovement.nod => face.pitch != null && face.pitch!.abs() < 10,
    FaceMovement.turnLeft ||
    FaceMovement.turnRight => face.yaw != null && face.yaw!.abs() < 10,
  };

  bool _isAction(FaceObservation face) => switch (movement) {
    FaceMovement.blink =>
      (face.leftEyeOpen ?? 1) < 0.35 && (face.rightEyeOpen ?? 1) < 0.35,
    FaceMovement.openMouth => face.mouthGap != null && face.mouthGap! > 0.045,
    FaceMovement.nod => face.pitch != null && face.pitch!.abs() > 16,
    // The back camera faces the student: its image directions are mirrored
    // relative to the student's own left and right.
    FaceMovement.turnLeft => face.yaw != null && face.yaw! > 20,
    FaceMovement.turnRight => face.yaw != null && face.yaw! < -20,
  };
}

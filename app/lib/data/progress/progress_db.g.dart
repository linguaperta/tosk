// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'progress_db.dart';

// ignore_for_file: type=lint
class $ReviewLogEntriesTable extends ReviewLogEntries
    with TableInfo<$ReviewLogEntriesTable, ReviewLogRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ReviewLogEntriesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _facetIdMeta = const VerificationMeta(
    'facetId',
  );
  @override
  late final GeneratedColumn<String> facetId = GeneratedColumn<String>(
    'facet_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _atMeta = const VerificationMeta('at');
  @override
  late final GeneratedColumn<int> at = GeneratedColumn<int>(
    'at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _ratingMeta = const VerificationMeta('rating');
  @override
  late final GeneratedColumn<int> rating = GeneratedColumn<int>(
    'rating',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _exerciseTypeMeta = const VerificationMeta(
    'exerciseType',
  );
  @override
  late final GeneratedColumn<String> exerciseType = GeneratedColumn<String>(
    'exercise_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _inputModeMeta = const VerificationMeta(
    'inputMode',
  );
  @override
  late final GeneratedColumn<String> inputMode = GeneratedColumn<String>(
    'input_mode',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _responseMsMeta = const VerificationMeta(
    'responseMs',
  );
  @override
  late final GeneratedColumn<int> responseMs = GeneratedColumn<int>(
    'response_ms',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _correctMeta = const VerificationMeta(
    'correct',
  );
  @override
  late final GeneratedColumn<bool> correct = GeneratedColumn<bool>(
    'correct',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("correct" IN (0, 1))',
    ),
  );
  static const VerificationMeta _answerMeta = const VerificationMeta('answer');
  @override
  late final GeneratedColumn<String> answer = GeneratedColumn<String>(
    'answer',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sessionIdMeta = const VerificationMeta(
    'sessionId',
  );
  @override
  late final GeneratedColumn<String> sessionId = GeneratedColumn<String>(
    'session_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _modeMeta = const VerificationMeta('mode');
  @override
  late final GeneratedColumn<String> mode = GeneratedColumn<String>(
    'mode',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    facetId,
    at,
    rating,
    exerciseType,
    inputMode,
    responseMs,
    correct,
    answer,
    sessionId,
    mode,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'review_log';
  @override
  VerificationContext validateIntegrity(
    Insertable<ReviewLogRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('facet_id')) {
      context.handle(
        _facetIdMeta,
        facetId.isAcceptableOrUnknown(data['facet_id']!, _facetIdMeta),
      );
    } else if (isInserting) {
      context.missing(_facetIdMeta);
    }
    if (data.containsKey('at')) {
      context.handle(_atMeta, at.isAcceptableOrUnknown(data['at']!, _atMeta));
    } else if (isInserting) {
      context.missing(_atMeta);
    }
    if (data.containsKey('rating')) {
      context.handle(
        _ratingMeta,
        rating.isAcceptableOrUnknown(data['rating']!, _ratingMeta),
      );
    } else if (isInserting) {
      context.missing(_ratingMeta);
    }
    if (data.containsKey('exercise_type')) {
      context.handle(
        _exerciseTypeMeta,
        exerciseType.isAcceptableOrUnknown(
          data['exercise_type']!,
          _exerciseTypeMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_exerciseTypeMeta);
    }
    if (data.containsKey('input_mode')) {
      context.handle(
        _inputModeMeta,
        inputMode.isAcceptableOrUnknown(data['input_mode']!, _inputModeMeta),
      );
    } else if (isInserting) {
      context.missing(_inputModeMeta);
    }
    if (data.containsKey('response_ms')) {
      context.handle(
        _responseMsMeta,
        responseMs.isAcceptableOrUnknown(data['response_ms']!, _responseMsMeta),
      );
    } else if (isInserting) {
      context.missing(_responseMsMeta);
    }
    if (data.containsKey('correct')) {
      context.handle(
        _correctMeta,
        correct.isAcceptableOrUnknown(data['correct']!, _correctMeta),
      );
    } else if (isInserting) {
      context.missing(_correctMeta);
    }
    if (data.containsKey('answer')) {
      context.handle(
        _answerMeta,
        answer.isAcceptableOrUnknown(data['answer']!, _answerMeta),
      );
    }
    if (data.containsKey('session_id')) {
      context.handle(
        _sessionIdMeta,
        sessionId.isAcceptableOrUnknown(data['session_id']!, _sessionIdMeta),
      );
    }
    if (data.containsKey('mode')) {
      context.handle(
        _modeMeta,
        mode.isAcceptableOrUnknown(data['mode']!, _modeMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ReviewLogRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ReviewLogRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      facetId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}facet_id'],
      )!,
      at: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}at'],
      )!,
      rating: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}rating'],
      )!,
      exerciseType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}exercise_type'],
      )!,
      inputMode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}input_mode'],
      )!,
      responseMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}response_ms'],
      )!,
      correct: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}correct'],
      )!,
      answer: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}answer'],
      ),
      sessionId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}session_id'],
      ),
      mode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}mode'],
      ),
    );
  }

  @override
  $ReviewLogEntriesTable createAlias(String alias) {
    return $ReviewLogEntriesTable(attachedDatabase, alias);
  }
}

class ReviewLogRow extends DataClass implements Insertable<ReviewLogRow> {
  final String id;
  final String facetId;
  final int at;
  final int rating;
  final String exerciseType;
  final String inputMode;
  final int responseMs;
  final bool correct;
  final String? answer;
  final String? sessionId;
  final String? mode;
  const ReviewLogRow({
    required this.id,
    required this.facetId,
    required this.at,
    required this.rating,
    required this.exerciseType,
    required this.inputMode,
    required this.responseMs,
    required this.correct,
    this.answer,
    this.sessionId,
    this.mode,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['facet_id'] = Variable<String>(facetId);
    map['at'] = Variable<int>(at);
    map['rating'] = Variable<int>(rating);
    map['exercise_type'] = Variable<String>(exerciseType);
    map['input_mode'] = Variable<String>(inputMode);
    map['response_ms'] = Variable<int>(responseMs);
    map['correct'] = Variable<bool>(correct);
    if (!nullToAbsent || answer != null) {
      map['answer'] = Variable<String>(answer);
    }
    if (!nullToAbsent || sessionId != null) {
      map['session_id'] = Variable<String>(sessionId);
    }
    if (!nullToAbsent || mode != null) {
      map['mode'] = Variable<String>(mode);
    }
    return map;
  }

  ReviewLogEntriesCompanion toCompanion(bool nullToAbsent) {
    return ReviewLogEntriesCompanion(
      id: Value(id),
      facetId: Value(facetId),
      at: Value(at),
      rating: Value(rating),
      exerciseType: Value(exerciseType),
      inputMode: Value(inputMode),
      responseMs: Value(responseMs),
      correct: Value(correct),
      answer: answer == null && nullToAbsent
          ? const Value.absent()
          : Value(answer),
      sessionId: sessionId == null && nullToAbsent
          ? const Value.absent()
          : Value(sessionId),
      mode: mode == null && nullToAbsent ? const Value.absent() : Value(mode),
    );
  }

  factory ReviewLogRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ReviewLogRow(
      id: serializer.fromJson<String>(json['id']),
      facetId: serializer.fromJson<String>(json['facetId']),
      at: serializer.fromJson<int>(json['at']),
      rating: serializer.fromJson<int>(json['rating']),
      exerciseType: serializer.fromJson<String>(json['exerciseType']),
      inputMode: serializer.fromJson<String>(json['inputMode']),
      responseMs: serializer.fromJson<int>(json['responseMs']),
      correct: serializer.fromJson<bool>(json['correct']),
      answer: serializer.fromJson<String?>(json['answer']),
      sessionId: serializer.fromJson<String?>(json['sessionId']),
      mode: serializer.fromJson<String?>(json['mode']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'facetId': serializer.toJson<String>(facetId),
      'at': serializer.toJson<int>(at),
      'rating': serializer.toJson<int>(rating),
      'exerciseType': serializer.toJson<String>(exerciseType),
      'inputMode': serializer.toJson<String>(inputMode),
      'responseMs': serializer.toJson<int>(responseMs),
      'correct': serializer.toJson<bool>(correct),
      'answer': serializer.toJson<String?>(answer),
      'sessionId': serializer.toJson<String?>(sessionId),
      'mode': serializer.toJson<String?>(mode),
    };
  }

  ReviewLogRow copyWith({
    String? id,
    String? facetId,
    int? at,
    int? rating,
    String? exerciseType,
    String? inputMode,
    int? responseMs,
    bool? correct,
    Value<String?> answer = const Value.absent(),
    Value<String?> sessionId = const Value.absent(),
    Value<String?> mode = const Value.absent(),
  }) => ReviewLogRow(
    id: id ?? this.id,
    facetId: facetId ?? this.facetId,
    at: at ?? this.at,
    rating: rating ?? this.rating,
    exerciseType: exerciseType ?? this.exerciseType,
    inputMode: inputMode ?? this.inputMode,
    responseMs: responseMs ?? this.responseMs,
    correct: correct ?? this.correct,
    answer: answer.present ? answer.value : this.answer,
    sessionId: sessionId.present ? sessionId.value : this.sessionId,
    mode: mode.present ? mode.value : this.mode,
  );
  ReviewLogRow copyWithCompanion(ReviewLogEntriesCompanion data) {
    return ReviewLogRow(
      id: data.id.present ? data.id.value : this.id,
      facetId: data.facetId.present ? data.facetId.value : this.facetId,
      at: data.at.present ? data.at.value : this.at,
      rating: data.rating.present ? data.rating.value : this.rating,
      exerciseType: data.exerciseType.present
          ? data.exerciseType.value
          : this.exerciseType,
      inputMode: data.inputMode.present ? data.inputMode.value : this.inputMode,
      responseMs: data.responseMs.present
          ? data.responseMs.value
          : this.responseMs,
      correct: data.correct.present ? data.correct.value : this.correct,
      answer: data.answer.present ? data.answer.value : this.answer,
      sessionId: data.sessionId.present ? data.sessionId.value : this.sessionId,
      mode: data.mode.present ? data.mode.value : this.mode,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ReviewLogRow(')
          ..write('id: $id, ')
          ..write('facetId: $facetId, ')
          ..write('at: $at, ')
          ..write('rating: $rating, ')
          ..write('exerciseType: $exerciseType, ')
          ..write('inputMode: $inputMode, ')
          ..write('responseMs: $responseMs, ')
          ..write('correct: $correct, ')
          ..write('answer: $answer, ')
          ..write('sessionId: $sessionId, ')
          ..write('mode: $mode')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    facetId,
    at,
    rating,
    exerciseType,
    inputMode,
    responseMs,
    correct,
    answer,
    sessionId,
    mode,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ReviewLogRow &&
          other.id == this.id &&
          other.facetId == this.facetId &&
          other.at == this.at &&
          other.rating == this.rating &&
          other.exerciseType == this.exerciseType &&
          other.inputMode == this.inputMode &&
          other.responseMs == this.responseMs &&
          other.correct == this.correct &&
          other.answer == this.answer &&
          other.sessionId == this.sessionId &&
          other.mode == this.mode);
}

class ReviewLogEntriesCompanion extends UpdateCompanion<ReviewLogRow> {
  final Value<String> id;
  final Value<String> facetId;
  final Value<int> at;
  final Value<int> rating;
  final Value<String> exerciseType;
  final Value<String> inputMode;
  final Value<int> responseMs;
  final Value<bool> correct;
  final Value<String?> answer;
  final Value<String?> sessionId;
  final Value<String?> mode;
  final Value<int> rowid;
  const ReviewLogEntriesCompanion({
    this.id = const Value.absent(),
    this.facetId = const Value.absent(),
    this.at = const Value.absent(),
    this.rating = const Value.absent(),
    this.exerciseType = const Value.absent(),
    this.inputMode = const Value.absent(),
    this.responseMs = const Value.absent(),
    this.correct = const Value.absent(),
    this.answer = const Value.absent(),
    this.sessionId = const Value.absent(),
    this.mode = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ReviewLogEntriesCompanion.insert({
    required String id,
    required String facetId,
    required int at,
    required int rating,
    required String exerciseType,
    required String inputMode,
    required int responseMs,
    required bool correct,
    this.answer = const Value.absent(),
    this.sessionId = const Value.absent(),
    this.mode = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       facetId = Value(facetId),
       at = Value(at),
       rating = Value(rating),
       exerciseType = Value(exerciseType),
       inputMode = Value(inputMode),
       responseMs = Value(responseMs),
       correct = Value(correct);
  static Insertable<ReviewLogRow> custom({
    Expression<String>? id,
    Expression<String>? facetId,
    Expression<int>? at,
    Expression<int>? rating,
    Expression<String>? exerciseType,
    Expression<String>? inputMode,
    Expression<int>? responseMs,
    Expression<bool>? correct,
    Expression<String>? answer,
    Expression<String>? sessionId,
    Expression<String>? mode,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (facetId != null) 'facet_id': facetId,
      if (at != null) 'at': at,
      if (rating != null) 'rating': rating,
      if (exerciseType != null) 'exercise_type': exerciseType,
      if (inputMode != null) 'input_mode': inputMode,
      if (responseMs != null) 'response_ms': responseMs,
      if (correct != null) 'correct': correct,
      if (answer != null) 'answer': answer,
      if (sessionId != null) 'session_id': sessionId,
      if (mode != null) 'mode': mode,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ReviewLogEntriesCompanion copyWith({
    Value<String>? id,
    Value<String>? facetId,
    Value<int>? at,
    Value<int>? rating,
    Value<String>? exerciseType,
    Value<String>? inputMode,
    Value<int>? responseMs,
    Value<bool>? correct,
    Value<String?>? answer,
    Value<String?>? sessionId,
    Value<String?>? mode,
    Value<int>? rowid,
  }) {
    return ReviewLogEntriesCompanion(
      id: id ?? this.id,
      facetId: facetId ?? this.facetId,
      at: at ?? this.at,
      rating: rating ?? this.rating,
      exerciseType: exerciseType ?? this.exerciseType,
      inputMode: inputMode ?? this.inputMode,
      responseMs: responseMs ?? this.responseMs,
      correct: correct ?? this.correct,
      answer: answer ?? this.answer,
      sessionId: sessionId ?? this.sessionId,
      mode: mode ?? this.mode,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (facetId.present) {
      map['facet_id'] = Variable<String>(facetId.value);
    }
    if (at.present) {
      map['at'] = Variable<int>(at.value);
    }
    if (rating.present) {
      map['rating'] = Variable<int>(rating.value);
    }
    if (exerciseType.present) {
      map['exercise_type'] = Variable<String>(exerciseType.value);
    }
    if (inputMode.present) {
      map['input_mode'] = Variable<String>(inputMode.value);
    }
    if (responseMs.present) {
      map['response_ms'] = Variable<int>(responseMs.value);
    }
    if (correct.present) {
      map['correct'] = Variable<bool>(correct.value);
    }
    if (answer.present) {
      map['answer'] = Variable<String>(answer.value);
    }
    if (sessionId.present) {
      map['session_id'] = Variable<String>(sessionId.value);
    }
    if (mode.present) {
      map['mode'] = Variable<String>(mode.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ReviewLogEntriesCompanion(')
          ..write('id: $id, ')
          ..write('facetId: $facetId, ')
          ..write('at: $at, ')
          ..write('rating: $rating, ')
          ..write('exerciseType: $exerciseType, ')
          ..write('inputMode: $inputMode, ')
          ..write('responseMs: $responseMs, ')
          ..write('correct: $correct, ')
          ..write('answer: $answer, ')
          ..write('sessionId: $sessionId, ')
          ..write('mode: $mode, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $FacetStatesTable extends FacetStates
    with TableInfo<$FacetStatesTable, FacetStateRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $FacetStatesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _facetIdMeta = const VerificationMeta(
    'facetId',
  );
  @override
  late final GeneratedColumn<String> facetId = GeneratedColumn<String>(
    'facet_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _stabilityMeta = const VerificationMeta(
    'stability',
  );
  @override
  late final GeneratedColumn<double> stability = GeneratedColumn<double>(
    'stability',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _difficultyMeta = const VerificationMeta(
    'difficulty',
  );
  @override
  late final GeneratedColumn<double> difficulty = GeneratedColumn<double>(
    'difficulty',
    aliasedName,
    false,
    type: DriftSqlType.double,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _dueMeta = const VerificationMeta('due');
  @override
  late final GeneratedColumn<int> due = GeneratedColumn<int>(
    'due',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lastReviewMeta = const VerificationMeta(
    'lastReview',
  );
  @override
  late final GeneratedColumn<int> lastReview = GeneratedColumn<int>(
    'last_review',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _repsMeta = const VerificationMeta('reps');
  @override
  late final GeneratedColumn<int> reps = GeneratedColumn<int>(
    'reps',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _lapsesMeta = const VerificationMeta('lapses');
  @override
  late final GeneratedColumn<int> lapses = GeneratedColumn<int>(
    'lapses',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _phaseMeta = const VerificationMeta('phase');
  @override
  late final GeneratedColumn<String> phase = GeneratedColumn<String>(
    'phase',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _stepMeta = const VerificationMeta('step');
  @override
  late final GeneratedColumn<int> step = GeneratedColumn<int>(
    'step',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    facetId,
    stability,
    difficulty,
    due,
    lastReview,
    reps,
    lapses,
    phase,
    step,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'facet_state';
  @override
  VerificationContext validateIntegrity(
    Insertable<FacetStateRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('facet_id')) {
      context.handle(
        _facetIdMeta,
        facetId.isAcceptableOrUnknown(data['facet_id']!, _facetIdMeta),
      );
    } else if (isInserting) {
      context.missing(_facetIdMeta);
    }
    if (data.containsKey('stability')) {
      context.handle(
        _stabilityMeta,
        stability.isAcceptableOrUnknown(data['stability']!, _stabilityMeta),
      );
    } else if (isInserting) {
      context.missing(_stabilityMeta);
    }
    if (data.containsKey('difficulty')) {
      context.handle(
        _difficultyMeta,
        difficulty.isAcceptableOrUnknown(data['difficulty']!, _difficultyMeta),
      );
    } else if (isInserting) {
      context.missing(_difficultyMeta);
    }
    if (data.containsKey('due')) {
      context.handle(
        _dueMeta,
        due.isAcceptableOrUnknown(data['due']!, _dueMeta),
      );
    } else if (isInserting) {
      context.missing(_dueMeta);
    }
    if (data.containsKey('last_review')) {
      context.handle(
        _lastReviewMeta,
        lastReview.isAcceptableOrUnknown(data['last_review']!, _lastReviewMeta),
      );
    } else if (isInserting) {
      context.missing(_lastReviewMeta);
    }
    if (data.containsKey('reps')) {
      context.handle(
        _repsMeta,
        reps.isAcceptableOrUnknown(data['reps']!, _repsMeta),
      );
    } else if (isInserting) {
      context.missing(_repsMeta);
    }
    if (data.containsKey('lapses')) {
      context.handle(
        _lapsesMeta,
        lapses.isAcceptableOrUnknown(data['lapses']!, _lapsesMeta),
      );
    } else if (isInserting) {
      context.missing(_lapsesMeta);
    }
    if (data.containsKey('phase')) {
      context.handle(
        _phaseMeta,
        phase.isAcceptableOrUnknown(data['phase']!, _phaseMeta),
      );
    } else if (isInserting) {
      context.missing(_phaseMeta);
    }
    if (data.containsKey('step')) {
      context.handle(
        _stepMeta,
        step.isAcceptableOrUnknown(data['step']!, _stepMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {facetId};
  @override
  FacetStateRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return FacetStateRow(
      facetId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}facet_id'],
      )!,
      stability: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}stability'],
      )!,
      difficulty: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}difficulty'],
      )!,
      due: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}due'],
      )!,
      lastReview: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_review'],
      )!,
      reps: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}reps'],
      )!,
      lapses: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}lapses'],
      )!,
      phase: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}phase'],
      )!,
      step: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}step'],
      ),
    );
  }

  @override
  $FacetStatesTable createAlias(String alias) {
    return $FacetStatesTable(attachedDatabase, alias);
  }
}

class FacetStateRow extends DataClass implements Insertable<FacetStateRow> {
  final String facetId;
  final double stability;
  final double difficulty;
  final int due;
  final int lastReview;
  final int reps;
  final int lapses;
  final String phase;
  final int? step;
  const FacetStateRow({
    required this.facetId,
    required this.stability,
    required this.difficulty,
    required this.due,
    required this.lastReview,
    required this.reps,
    required this.lapses,
    required this.phase,
    this.step,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['facet_id'] = Variable<String>(facetId);
    map['stability'] = Variable<double>(stability);
    map['difficulty'] = Variable<double>(difficulty);
    map['due'] = Variable<int>(due);
    map['last_review'] = Variable<int>(lastReview);
    map['reps'] = Variable<int>(reps);
    map['lapses'] = Variable<int>(lapses);
    map['phase'] = Variable<String>(phase);
    if (!nullToAbsent || step != null) {
      map['step'] = Variable<int>(step);
    }
    return map;
  }

  FacetStatesCompanion toCompanion(bool nullToAbsent) {
    return FacetStatesCompanion(
      facetId: Value(facetId),
      stability: Value(stability),
      difficulty: Value(difficulty),
      due: Value(due),
      lastReview: Value(lastReview),
      reps: Value(reps),
      lapses: Value(lapses),
      phase: Value(phase),
      step: step == null && nullToAbsent ? const Value.absent() : Value(step),
    );
  }

  factory FacetStateRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return FacetStateRow(
      facetId: serializer.fromJson<String>(json['facetId']),
      stability: serializer.fromJson<double>(json['stability']),
      difficulty: serializer.fromJson<double>(json['difficulty']),
      due: serializer.fromJson<int>(json['due']),
      lastReview: serializer.fromJson<int>(json['lastReview']),
      reps: serializer.fromJson<int>(json['reps']),
      lapses: serializer.fromJson<int>(json['lapses']),
      phase: serializer.fromJson<String>(json['phase']),
      step: serializer.fromJson<int?>(json['step']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'facetId': serializer.toJson<String>(facetId),
      'stability': serializer.toJson<double>(stability),
      'difficulty': serializer.toJson<double>(difficulty),
      'due': serializer.toJson<int>(due),
      'lastReview': serializer.toJson<int>(lastReview),
      'reps': serializer.toJson<int>(reps),
      'lapses': serializer.toJson<int>(lapses),
      'phase': serializer.toJson<String>(phase),
      'step': serializer.toJson<int?>(step),
    };
  }

  FacetStateRow copyWith({
    String? facetId,
    double? stability,
    double? difficulty,
    int? due,
    int? lastReview,
    int? reps,
    int? lapses,
    String? phase,
    Value<int?> step = const Value.absent(),
  }) => FacetStateRow(
    facetId: facetId ?? this.facetId,
    stability: stability ?? this.stability,
    difficulty: difficulty ?? this.difficulty,
    due: due ?? this.due,
    lastReview: lastReview ?? this.lastReview,
    reps: reps ?? this.reps,
    lapses: lapses ?? this.lapses,
    phase: phase ?? this.phase,
    step: step.present ? step.value : this.step,
  );
  FacetStateRow copyWithCompanion(FacetStatesCompanion data) {
    return FacetStateRow(
      facetId: data.facetId.present ? data.facetId.value : this.facetId,
      stability: data.stability.present ? data.stability.value : this.stability,
      difficulty: data.difficulty.present
          ? data.difficulty.value
          : this.difficulty,
      due: data.due.present ? data.due.value : this.due,
      lastReview: data.lastReview.present
          ? data.lastReview.value
          : this.lastReview,
      reps: data.reps.present ? data.reps.value : this.reps,
      lapses: data.lapses.present ? data.lapses.value : this.lapses,
      phase: data.phase.present ? data.phase.value : this.phase,
      step: data.step.present ? data.step.value : this.step,
    );
  }

  @override
  String toString() {
    return (StringBuffer('FacetStateRow(')
          ..write('facetId: $facetId, ')
          ..write('stability: $stability, ')
          ..write('difficulty: $difficulty, ')
          ..write('due: $due, ')
          ..write('lastReview: $lastReview, ')
          ..write('reps: $reps, ')
          ..write('lapses: $lapses, ')
          ..write('phase: $phase, ')
          ..write('step: $step')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    facetId,
    stability,
    difficulty,
    due,
    lastReview,
    reps,
    lapses,
    phase,
    step,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is FacetStateRow &&
          other.facetId == this.facetId &&
          other.stability == this.stability &&
          other.difficulty == this.difficulty &&
          other.due == this.due &&
          other.lastReview == this.lastReview &&
          other.reps == this.reps &&
          other.lapses == this.lapses &&
          other.phase == this.phase &&
          other.step == this.step);
}

class FacetStatesCompanion extends UpdateCompanion<FacetStateRow> {
  final Value<String> facetId;
  final Value<double> stability;
  final Value<double> difficulty;
  final Value<int> due;
  final Value<int> lastReview;
  final Value<int> reps;
  final Value<int> lapses;
  final Value<String> phase;
  final Value<int?> step;
  final Value<int> rowid;
  const FacetStatesCompanion({
    this.facetId = const Value.absent(),
    this.stability = const Value.absent(),
    this.difficulty = const Value.absent(),
    this.due = const Value.absent(),
    this.lastReview = const Value.absent(),
    this.reps = const Value.absent(),
    this.lapses = const Value.absent(),
    this.phase = const Value.absent(),
    this.step = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  FacetStatesCompanion.insert({
    required String facetId,
    required double stability,
    required double difficulty,
    required int due,
    required int lastReview,
    required int reps,
    required int lapses,
    required String phase,
    this.step = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : facetId = Value(facetId),
       stability = Value(stability),
       difficulty = Value(difficulty),
       due = Value(due),
       lastReview = Value(lastReview),
       reps = Value(reps),
       lapses = Value(lapses),
       phase = Value(phase);
  static Insertable<FacetStateRow> custom({
    Expression<String>? facetId,
    Expression<double>? stability,
    Expression<double>? difficulty,
    Expression<int>? due,
    Expression<int>? lastReview,
    Expression<int>? reps,
    Expression<int>? lapses,
    Expression<String>? phase,
    Expression<int>? step,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (facetId != null) 'facet_id': facetId,
      if (stability != null) 'stability': stability,
      if (difficulty != null) 'difficulty': difficulty,
      if (due != null) 'due': due,
      if (lastReview != null) 'last_review': lastReview,
      if (reps != null) 'reps': reps,
      if (lapses != null) 'lapses': lapses,
      if (phase != null) 'phase': phase,
      if (step != null) 'step': step,
      if (rowid != null) 'rowid': rowid,
    });
  }

  FacetStatesCompanion copyWith({
    Value<String>? facetId,
    Value<double>? stability,
    Value<double>? difficulty,
    Value<int>? due,
    Value<int>? lastReview,
    Value<int>? reps,
    Value<int>? lapses,
    Value<String>? phase,
    Value<int?>? step,
    Value<int>? rowid,
  }) {
    return FacetStatesCompanion(
      facetId: facetId ?? this.facetId,
      stability: stability ?? this.stability,
      difficulty: difficulty ?? this.difficulty,
      due: due ?? this.due,
      lastReview: lastReview ?? this.lastReview,
      reps: reps ?? this.reps,
      lapses: lapses ?? this.lapses,
      phase: phase ?? this.phase,
      step: step ?? this.step,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (facetId.present) {
      map['facet_id'] = Variable<String>(facetId.value);
    }
    if (stability.present) {
      map['stability'] = Variable<double>(stability.value);
    }
    if (difficulty.present) {
      map['difficulty'] = Variable<double>(difficulty.value);
    }
    if (due.present) {
      map['due'] = Variable<int>(due.value);
    }
    if (lastReview.present) {
      map['last_review'] = Variable<int>(lastReview.value);
    }
    if (reps.present) {
      map['reps'] = Variable<int>(reps.value);
    }
    if (lapses.present) {
      map['lapses'] = Variable<int>(lapses.value);
    }
    if (phase.present) {
      map['phase'] = Variable<String>(phase.value);
    }
    if (step.present) {
      map['step'] = Variable<int>(step.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('FacetStatesCompanion(')
          ..write('facetId: $facetId, ')
          ..write('stability: $stability, ')
          ..write('difficulty: $difficulty, ')
          ..write('due: $due, ')
          ..write('lastReview: $lastReview, ')
          ..write('reps: $reps, ')
          ..write('lapses: $lapses, ')
          ..write('phase: $phase, ')
          ..write('step: $step, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $MistakesTable extends Mistakes
    with TableInfo<$MistakesTable, MistakeRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MistakesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _facetIdMeta = const VerificationMeta(
    'facetId',
  );
  @override
  late final GeneratedColumn<String> facetId = GeneratedColumn<String>(
    'facet_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _atMeta = const VerificationMeta('at');
  @override
  late final GeneratedColumn<int> at = GeneratedColumn<int>(
    'at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _exerciseTypeMeta = const VerificationMeta(
    'exerciseType',
  );
  @override
  late final GeneratedColumn<String> exerciseType = GeneratedColumn<String>(
    'exercise_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _promptMeta = const VerificationMeta('prompt');
  @override
  late final GeneratedColumn<String> prompt = GeneratedColumn<String>(
    'prompt',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _expectedMeta = const VerificationMeta(
    'expected',
  );
  @override
  late final GeneratedColumn<String> expected = GeneratedColumn<String>(
    'expected',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _givenMeta = const VerificationMeta('given');
  @override
  late final GeneratedColumn<String> given = GeneratedColumn<String>(
    'given',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _skillIdMeta = const VerificationMeta(
    'skillId',
  );
  @override
  late final GeneratedColumn<String> skillId = GeneratedColumn<String>(
    'skill_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _noteMeta = const VerificationMeta('note');
  @override
  late final GeneratedColumn<String> note = GeneratedColumn<String>(
    'note',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _explanationMeta = const VerificationMeta(
    'explanation',
  );
  @override
  late final GeneratedColumn<String> explanation = GeneratedColumn<String>(
    'explanation',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    facetId,
    at,
    exerciseType,
    prompt,
    expected,
    given,
    skillId,
    note,
    explanation,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'mistakes';
  @override
  VerificationContext validateIntegrity(
    Insertable<MistakeRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('facet_id')) {
      context.handle(
        _facetIdMeta,
        facetId.isAcceptableOrUnknown(data['facet_id']!, _facetIdMeta),
      );
    } else if (isInserting) {
      context.missing(_facetIdMeta);
    }
    if (data.containsKey('at')) {
      context.handle(_atMeta, at.isAcceptableOrUnknown(data['at']!, _atMeta));
    } else if (isInserting) {
      context.missing(_atMeta);
    }
    if (data.containsKey('exercise_type')) {
      context.handle(
        _exerciseTypeMeta,
        exerciseType.isAcceptableOrUnknown(
          data['exercise_type']!,
          _exerciseTypeMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_exerciseTypeMeta);
    }
    if (data.containsKey('prompt')) {
      context.handle(
        _promptMeta,
        prompt.isAcceptableOrUnknown(data['prompt']!, _promptMeta),
      );
    } else if (isInserting) {
      context.missing(_promptMeta);
    }
    if (data.containsKey('expected')) {
      context.handle(
        _expectedMeta,
        expected.isAcceptableOrUnknown(data['expected']!, _expectedMeta),
      );
    } else if (isInserting) {
      context.missing(_expectedMeta);
    }
    if (data.containsKey('given')) {
      context.handle(
        _givenMeta,
        given.isAcceptableOrUnknown(data['given']!, _givenMeta),
      );
    } else if (isInserting) {
      context.missing(_givenMeta);
    }
    if (data.containsKey('skill_id')) {
      context.handle(
        _skillIdMeta,
        skillId.isAcceptableOrUnknown(data['skill_id']!, _skillIdMeta),
      );
    }
    if (data.containsKey('note')) {
      context.handle(
        _noteMeta,
        note.isAcceptableOrUnknown(data['note']!, _noteMeta),
      );
    }
    if (data.containsKey('explanation')) {
      context.handle(
        _explanationMeta,
        explanation.isAcceptableOrUnknown(
          data['explanation']!,
          _explanationMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  MistakeRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MistakeRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      facetId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}facet_id'],
      )!,
      at: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}at'],
      )!,
      exerciseType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}exercise_type'],
      )!,
      prompt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}prompt'],
      )!,
      expected: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}expected'],
      )!,
      given: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}given'],
      )!,
      skillId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}skill_id'],
      ),
      note: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}note'],
      ),
      explanation: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}explanation'],
      ),
    );
  }

  @override
  $MistakesTable createAlias(String alias) {
    return $MistakesTable(attachedDatabase, alias);
  }
}

class MistakeRow extends DataClass implements Insertable<MistakeRow> {
  final String id;
  final String facetId;
  final int at;
  final String exerciseType;
  final String prompt;
  final String expected;
  final String given;
  final String? skillId;
  final String? note;
  final String? explanation;
  const MistakeRow({
    required this.id,
    required this.facetId,
    required this.at,
    required this.exerciseType,
    required this.prompt,
    required this.expected,
    required this.given,
    this.skillId,
    this.note,
    this.explanation,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['facet_id'] = Variable<String>(facetId);
    map['at'] = Variable<int>(at);
    map['exercise_type'] = Variable<String>(exerciseType);
    map['prompt'] = Variable<String>(prompt);
    map['expected'] = Variable<String>(expected);
    map['given'] = Variable<String>(given);
    if (!nullToAbsent || skillId != null) {
      map['skill_id'] = Variable<String>(skillId);
    }
    if (!nullToAbsent || note != null) {
      map['note'] = Variable<String>(note);
    }
    if (!nullToAbsent || explanation != null) {
      map['explanation'] = Variable<String>(explanation);
    }
    return map;
  }

  MistakesCompanion toCompanion(bool nullToAbsent) {
    return MistakesCompanion(
      id: Value(id),
      facetId: Value(facetId),
      at: Value(at),
      exerciseType: Value(exerciseType),
      prompt: Value(prompt),
      expected: Value(expected),
      given: Value(given),
      skillId: skillId == null && nullToAbsent
          ? const Value.absent()
          : Value(skillId),
      note: note == null && nullToAbsent ? const Value.absent() : Value(note),
      explanation: explanation == null && nullToAbsent
          ? const Value.absent()
          : Value(explanation),
    );
  }

  factory MistakeRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MistakeRow(
      id: serializer.fromJson<String>(json['id']),
      facetId: serializer.fromJson<String>(json['facetId']),
      at: serializer.fromJson<int>(json['at']),
      exerciseType: serializer.fromJson<String>(json['exerciseType']),
      prompt: serializer.fromJson<String>(json['prompt']),
      expected: serializer.fromJson<String>(json['expected']),
      given: serializer.fromJson<String>(json['given']),
      skillId: serializer.fromJson<String?>(json['skillId']),
      note: serializer.fromJson<String?>(json['note']),
      explanation: serializer.fromJson<String?>(json['explanation']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'facetId': serializer.toJson<String>(facetId),
      'at': serializer.toJson<int>(at),
      'exerciseType': serializer.toJson<String>(exerciseType),
      'prompt': serializer.toJson<String>(prompt),
      'expected': serializer.toJson<String>(expected),
      'given': serializer.toJson<String>(given),
      'skillId': serializer.toJson<String?>(skillId),
      'note': serializer.toJson<String?>(note),
      'explanation': serializer.toJson<String?>(explanation),
    };
  }

  MistakeRow copyWith({
    String? id,
    String? facetId,
    int? at,
    String? exerciseType,
    String? prompt,
    String? expected,
    String? given,
    Value<String?> skillId = const Value.absent(),
    Value<String?> note = const Value.absent(),
    Value<String?> explanation = const Value.absent(),
  }) => MistakeRow(
    id: id ?? this.id,
    facetId: facetId ?? this.facetId,
    at: at ?? this.at,
    exerciseType: exerciseType ?? this.exerciseType,
    prompt: prompt ?? this.prompt,
    expected: expected ?? this.expected,
    given: given ?? this.given,
    skillId: skillId.present ? skillId.value : this.skillId,
    note: note.present ? note.value : this.note,
    explanation: explanation.present ? explanation.value : this.explanation,
  );
  MistakeRow copyWithCompanion(MistakesCompanion data) {
    return MistakeRow(
      id: data.id.present ? data.id.value : this.id,
      facetId: data.facetId.present ? data.facetId.value : this.facetId,
      at: data.at.present ? data.at.value : this.at,
      exerciseType: data.exerciseType.present
          ? data.exerciseType.value
          : this.exerciseType,
      prompt: data.prompt.present ? data.prompt.value : this.prompt,
      expected: data.expected.present ? data.expected.value : this.expected,
      given: data.given.present ? data.given.value : this.given,
      skillId: data.skillId.present ? data.skillId.value : this.skillId,
      note: data.note.present ? data.note.value : this.note,
      explanation: data.explanation.present
          ? data.explanation.value
          : this.explanation,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MistakeRow(')
          ..write('id: $id, ')
          ..write('facetId: $facetId, ')
          ..write('at: $at, ')
          ..write('exerciseType: $exerciseType, ')
          ..write('prompt: $prompt, ')
          ..write('expected: $expected, ')
          ..write('given: $given, ')
          ..write('skillId: $skillId, ')
          ..write('note: $note, ')
          ..write('explanation: $explanation')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    facetId,
    at,
    exerciseType,
    prompt,
    expected,
    given,
    skillId,
    note,
    explanation,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MistakeRow &&
          other.id == this.id &&
          other.facetId == this.facetId &&
          other.at == this.at &&
          other.exerciseType == this.exerciseType &&
          other.prompt == this.prompt &&
          other.expected == this.expected &&
          other.given == this.given &&
          other.skillId == this.skillId &&
          other.note == this.note &&
          other.explanation == this.explanation);
}

class MistakesCompanion extends UpdateCompanion<MistakeRow> {
  final Value<String> id;
  final Value<String> facetId;
  final Value<int> at;
  final Value<String> exerciseType;
  final Value<String> prompt;
  final Value<String> expected;
  final Value<String> given;
  final Value<String?> skillId;
  final Value<String?> note;
  final Value<String?> explanation;
  final Value<int> rowid;
  const MistakesCompanion({
    this.id = const Value.absent(),
    this.facetId = const Value.absent(),
    this.at = const Value.absent(),
    this.exerciseType = const Value.absent(),
    this.prompt = const Value.absent(),
    this.expected = const Value.absent(),
    this.given = const Value.absent(),
    this.skillId = const Value.absent(),
    this.note = const Value.absent(),
    this.explanation = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MistakesCompanion.insert({
    required String id,
    required String facetId,
    required int at,
    required String exerciseType,
    required String prompt,
    required String expected,
    required String given,
    this.skillId = const Value.absent(),
    this.note = const Value.absent(),
    this.explanation = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       facetId = Value(facetId),
       at = Value(at),
       exerciseType = Value(exerciseType),
       prompt = Value(prompt),
       expected = Value(expected),
       given = Value(given);
  static Insertable<MistakeRow> custom({
    Expression<String>? id,
    Expression<String>? facetId,
    Expression<int>? at,
    Expression<String>? exerciseType,
    Expression<String>? prompt,
    Expression<String>? expected,
    Expression<String>? given,
    Expression<String>? skillId,
    Expression<String>? note,
    Expression<String>? explanation,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (facetId != null) 'facet_id': facetId,
      if (at != null) 'at': at,
      if (exerciseType != null) 'exercise_type': exerciseType,
      if (prompt != null) 'prompt': prompt,
      if (expected != null) 'expected': expected,
      if (given != null) 'given': given,
      if (skillId != null) 'skill_id': skillId,
      if (note != null) 'note': note,
      if (explanation != null) 'explanation': explanation,
      if (rowid != null) 'rowid': rowid,
    });
  }

  MistakesCompanion copyWith({
    Value<String>? id,
    Value<String>? facetId,
    Value<int>? at,
    Value<String>? exerciseType,
    Value<String>? prompt,
    Value<String>? expected,
    Value<String>? given,
    Value<String?>? skillId,
    Value<String?>? note,
    Value<String?>? explanation,
    Value<int>? rowid,
  }) {
    return MistakesCompanion(
      id: id ?? this.id,
      facetId: facetId ?? this.facetId,
      at: at ?? this.at,
      exerciseType: exerciseType ?? this.exerciseType,
      prompt: prompt ?? this.prompt,
      expected: expected ?? this.expected,
      given: given ?? this.given,
      skillId: skillId ?? this.skillId,
      note: note ?? this.note,
      explanation: explanation ?? this.explanation,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (facetId.present) {
      map['facet_id'] = Variable<String>(facetId.value);
    }
    if (at.present) {
      map['at'] = Variable<int>(at.value);
    }
    if (exerciseType.present) {
      map['exercise_type'] = Variable<String>(exerciseType.value);
    }
    if (prompt.present) {
      map['prompt'] = Variable<String>(prompt.value);
    }
    if (expected.present) {
      map['expected'] = Variable<String>(expected.value);
    }
    if (given.present) {
      map['given'] = Variable<String>(given.value);
    }
    if (skillId.present) {
      map['skill_id'] = Variable<String>(skillId.value);
    }
    if (note.present) {
      map['note'] = Variable<String>(note.value);
    }
    if (explanation.present) {
      map['explanation'] = Variable<String>(explanation.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MistakesCompanion(')
          ..write('id: $id, ')
          ..write('facetId: $facetId, ')
          ..write('at: $at, ')
          ..write('exerciseType: $exerciseType, ')
          ..write('prompt: $prompt, ')
          ..write('expected: $expected, ')
          ..write('given: $given, ')
          ..write('skillId: $skillId, ')
          ..write('note: $note, ')
          ..write('explanation: $explanation, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SettingsTable extends Settings
    with TableInfo<$SettingsTable, SettingRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SettingsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [key, value];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'settings';
  @override
  VerificationContext validateIntegrity(
    Insertable<SettingRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  SettingRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SettingRow(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value'],
      )!,
    );
  }

  @override
  $SettingsTable createAlias(String alias) {
    return $SettingsTable(attachedDatabase, alias);
  }
}

class SettingRow extends DataClass implements Insertable<SettingRow> {
  final String key;
  final String value;
  const SettingRow({required this.key, required this.value});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    return map;
  }

  SettingsCompanion toCompanion(bool nullToAbsent) {
    return SettingsCompanion(key: Value(key), value: Value(value));
  }

  factory SettingRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SettingRow(
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String>(json['value']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String>(value),
    };
  }

  SettingRow copyWith({String? key, String? value}) =>
      SettingRow(key: key ?? this.key, value: value ?? this.value);
  SettingRow copyWithCompanion(SettingsCompanion data) {
    return SettingRow(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SettingRow(')
          ..write('key: $key, ')
          ..write('value: $value')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, value);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SettingRow &&
          other.key == this.key &&
          other.value == this.value);
}

class SettingsCompanion extends UpdateCompanion<SettingRow> {
  final Value<String> key;
  final Value<String> value;
  final Value<int> rowid;
  const SettingsCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SettingsCompanion.insert({
    required String key,
    required String value,
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       value = Value(value);
  static Insertable<SettingRow> custom({
    Expression<String>? key,
    Expression<String>? value,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SettingsCompanion copyWith({
    Value<String>? key,
    Value<String>? value,
    Value<int>? rowid,
  }) {
    return SettingsCompanion(
      key: key ?? this.key,
      value: value ?? this.value,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SettingsCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$ProgressDb extends GeneratedDatabase {
  _$ProgressDb(QueryExecutor e) : super(e);
  $ProgressDbManager get managers => $ProgressDbManager(this);
  late final $ReviewLogEntriesTable reviewLogEntries = $ReviewLogEntriesTable(
    this,
  );
  late final $FacetStatesTable facetStates = $FacetStatesTable(this);
  late final $MistakesTable mistakes = $MistakesTable(this);
  late final $SettingsTable settings = $SettingsTable(this);
  late final Index reviewLogFacetAt = Index(
    'review_log_facet_at',
    'CREATE INDEX review_log_facet_at ON review_log (facet_id, at)',
  );
  late final Index reviewLogAt = Index(
    'review_log_at',
    'CREATE INDEX review_log_at ON review_log (at)',
  );
  late final Index facetStateDue = Index(
    'facet_state_due',
    'CREATE INDEX facet_state_due ON facet_state (due)',
  );
  late final Index mistakesAt = Index(
    'mistakes_at',
    'CREATE INDEX mistakes_at ON mistakes (at)',
  );
  late final Index mistakesFacet = Index(
    'mistakes_facet',
    'CREATE INDEX mistakes_facet ON mistakes (facet_id)',
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    reviewLogEntries,
    facetStates,
    mistakes,
    settings,
    reviewLogFacetAt,
    reviewLogAt,
    facetStateDue,
    mistakesAt,
    mistakesFacet,
  ];
}

typedef $$ReviewLogEntriesTableCreateCompanionBuilder =
    ReviewLogEntriesCompanion Function({
      required String id,
      required String facetId,
      required int at,
      required int rating,
      required String exerciseType,
      required String inputMode,
      required int responseMs,
      required bool correct,
      Value<String?> answer,
      Value<String?> sessionId,
      Value<String?> mode,
      Value<int> rowid,
    });
typedef $$ReviewLogEntriesTableUpdateCompanionBuilder =
    ReviewLogEntriesCompanion Function({
      Value<String> id,
      Value<String> facetId,
      Value<int> at,
      Value<int> rating,
      Value<String> exerciseType,
      Value<String> inputMode,
      Value<int> responseMs,
      Value<bool> correct,
      Value<String?> answer,
      Value<String?> sessionId,
      Value<String?> mode,
      Value<int> rowid,
    });

class $$ReviewLogEntriesTableFilterComposer
    extends Composer<_$ProgressDb, $ReviewLogEntriesTable> {
  $$ReviewLogEntriesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get facetId => $composableBuilder(
    column: $table.facetId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get at => $composableBuilder(
    column: $table.at,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get rating => $composableBuilder(
    column: $table.rating,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get exerciseType => $composableBuilder(
    column: $table.exerciseType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get inputMode => $composableBuilder(
    column: $table.inputMode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get responseMs => $composableBuilder(
    column: $table.responseMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get correct => $composableBuilder(
    column: $table.correct,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get answer => $composableBuilder(
    column: $table.answer,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sessionId => $composableBuilder(
    column: $table.sessionId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mode => $composableBuilder(
    column: $table.mode,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ReviewLogEntriesTableOrderingComposer
    extends Composer<_$ProgressDb, $ReviewLogEntriesTable> {
  $$ReviewLogEntriesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get facetId => $composableBuilder(
    column: $table.facetId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get at => $composableBuilder(
    column: $table.at,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get rating => $composableBuilder(
    column: $table.rating,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get exerciseType => $composableBuilder(
    column: $table.exerciseType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get inputMode => $composableBuilder(
    column: $table.inputMode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get responseMs => $composableBuilder(
    column: $table.responseMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get correct => $composableBuilder(
    column: $table.correct,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get answer => $composableBuilder(
    column: $table.answer,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sessionId => $composableBuilder(
    column: $table.sessionId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mode => $composableBuilder(
    column: $table.mode,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ReviewLogEntriesTableAnnotationComposer
    extends Composer<_$ProgressDb, $ReviewLogEntriesTable> {
  $$ReviewLogEntriesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get facetId =>
      $composableBuilder(column: $table.facetId, builder: (column) => column);

  GeneratedColumn<int> get at =>
      $composableBuilder(column: $table.at, builder: (column) => column);

  GeneratedColumn<int> get rating =>
      $composableBuilder(column: $table.rating, builder: (column) => column);

  GeneratedColumn<String> get exerciseType => $composableBuilder(
    column: $table.exerciseType,
    builder: (column) => column,
  );

  GeneratedColumn<String> get inputMode =>
      $composableBuilder(column: $table.inputMode, builder: (column) => column);

  GeneratedColumn<int> get responseMs => $composableBuilder(
    column: $table.responseMs,
    builder: (column) => column,
  );

  GeneratedColumn<bool> get correct =>
      $composableBuilder(column: $table.correct, builder: (column) => column);

  GeneratedColumn<String> get answer =>
      $composableBuilder(column: $table.answer, builder: (column) => column);

  GeneratedColumn<String> get sessionId =>
      $composableBuilder(column: $table.sessionId, builder: (column) => column);

  GeneratedColumn<String> get mode =>
      $composableBuilder(column: $table.mode, builder: (column) => column);
}

class $$ReviewLogEntriesTableTableManager
    extends
        RootTableManager<
          _$ProgressDb,
          $ReviewLogEntriesTable,
          ReviewLogRow,
          $$ReviewLogEntriesTableFilterComposer,
          $$ReviewLogEntriesTableOrderingComposer,
          $$ReviewLogEntriesTableAnnotationComposer,
          $$ReviewLogEntriesTableCreateCompanionBuilder,
          $$ReviewLogEntriesTableUpdateCompanionBuilder,
          (
            ReviewLogRow,
            BaseReferences<_$ProgressDb, $ReviewLogEntriesTable, ReviewLogRow>,
          ),
          ReviewLogRow,
          PrefetchHooks Function()
        > {
  $$ReviewLogEntriesTableTableManager(
    _$ProgressDb db,
    $ReviewLogEntriesTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ReviewLogEntriesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ReviewLogEntriesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ReviewLogEntriesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> facetId = const Value.absent(),
                Value<int> at = const Value.absent(),
                Value<int> rating = const Value.absent(),
                Value<String> exerciseType = const Value.absent(),
                Value<String> inputMode = const Value.absent(),
                Value<int> responseMs = const Value.absent(),
                Value<bool> correct = const Value.absent(),
                Value<String?> answer = const Value.absent(),
                Value<String?> sessionId = const Value.absent(),
                Value<String?> mode = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ReviewLogEntriesCompanion(
                id: id,
                facetId: facetId,
                at: at,
                rating: rating,
                exerciseType: exerciseType,
                inputMode: inputMode,
                responseMs: responseMs,
                correct: correct,
                answer: answer,
                sessionId: sessionId,
                mode: mode,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String facetId,
                required int at,
                required int rating,
                required String exerciseType,
                required String inputMode,
                required int responseMs,
                required bool correct,
                Value<String?> answer = const Value.absent(),
                Value<String?> sessionId = const Value.absent(),
                Value<String?> mode = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ReviewLogEntriesCompanion.insert(
                id: id,
                facetId: facetId,
                at: at,
                rating: rating,
                exerciseType: exerciseType,
                inputMode: inputMode,
                responseMs: responseMs,
                correct: correct,
                answer: answer,
                sessionId: sessionId,
                mode: mode,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ReviewLogEntriesTable, ReviewLogRow>(table),
                  BaseReferences<
                    _$ProgressDb,
                    $ReviewLogEntriesTable,
                    ReviewLogRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ReviewLogEntriesTableProcessedTableManager =
    ProcessedTableManager<
      _$ProgressDb,
      $ReviewLogEntriesTable,
      ReviewLogRow,
      $$ReviewLogEntriesTableFilterComposer,
      $$ReviewLogEntriesTableOrderingComposer,
      $$ReviewLogEntriesTableAnnotationComposer,
      $$ReviewLogEntriesTableCreateCompanionBuilder,
      $$ReviewLogEntriesTableUpdateCompanionBuilder,
      (
        ReviewLogRow,
        BaseReferences<_$ProgressDb, $ReviewLogEntriesTable, ReviewLogRow>,
      ),
      ReviewLogRow,
      PrefetchHooks Function()
    >;
typedef $$FacetStatesTableCreateCompanionBuilder =
    FacetStatesCompanion Function({
      required String facetId,
      required double stability,
      required double difficulty,
      required int due,
      required int lastReview,
      required int reps,
      required int lapses,
      required String phase,
      Value<int?> step,
      Value<int> rowid,
    });
typedef $$FacetStatesTableUpdateCompanionBuilder =
    FacetStatesCompanion Function({
      Value<String> facetId,
      Value<double> stability,
      Value<double> difficulty,
      Value<int> due,
      Value<int> lastReview,
      Value<int> reps,
      Value<int> lapses,
      Value<String> phase,
      Value<int?> step,
      Value<int> rowid,
    });

class $$FacetStatesTableFilterComposer
    extends Composer<_$ProgressDb, $FacetStatesTable> {
  $$FacetStatesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get facetId => $composableBuilder(
    column: $table.facetId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get stability => $composableBuilder(
    column: $table.stability,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get difficulty => $composableBuilder(
    column: $table.difficulty,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get due => $composableBuilder(
    column: $table.due,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastReview => $composableBuilder(
    column: $table.lastReview,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get reps => $composableBuilder(
    column: $table.reps,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lapses => $composableBuilder(
    column: $table.lapses,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get phase => $composableBuilder(
    column: $table.phase,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get step => $composableBuilder(
    column: $table.step,
    builder: (column) => ColumnFilters(column),
  );
}

class $$FacetStatesTableOrderingComposer
    extends Composer<_$ProgressDb, $FacetStatesTable> {
  $$FacetStatesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get facetId => $composableBuilder(
    column: $table.facetId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get stability => $composableBuilder(
    column: $table.stability,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get difficulty => $composableBuilder(
    column: $table.difficulty,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get due => $composableBuilder(
    column: $table.due,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastReview => $composableBuilder(
    column: $table.lastReview,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get reps => $composableBuilder(
    column: $table.reps,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lapses => $composableBuilder(
    column: $table.lapses,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get phase => $composableBuilder(
    column: $table.phase,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get step => $composableBuilder(
    column: $table.step,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$FacetStatesTableAnnotationComposer
    extends Composer<_$ProgressDb, $FacetStatesTable> {
  $$FacetStatesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get facetId =>
      $composableBuilder(column: $table.facetId, builder: (column) => column);

  GeneratedColumn<double> get stability =>
      $composableBuilder(column: $table.stability, builder: (column) => column);

  GeneratedColumn<double> get difficulty => $composableBuilder(
    column: $table.difficulty,
    builder: (column) => column,
  );

  GeneratedColumn<int> get due =>
      $composableBuilder(column: $table.due, builder: (column) => column);

  GeneratedColumn<int> get lastReview => $composableBuilder(
    column: $table.lastReview,
    builder: (column) => column,
  );

  GeneratedColumn<int> get reps =>
      $composableBuilder(column: $table.reps, builder: (column) => column);

  GeneratedColumn<int> get lapses =>
      $composableBuilder(column: $table.lapses, builder: (column) => column);

  GeneratedColumn<String> get phase =>
      $composableBuilder(column: $table.phase, builder: (column) => column);

  GeneratedColumn<int> get step =>
      $composableBuilder(column: $table.step, builder: (column) => column);
}

class $$FacetStatesTableTableManager
    extends
        RootTableManager<
          _$ProgressDb,
          $FacetStatesTable,
          FacetStateRow,
          $$FacetStatesTableFilterComposer,
          $$FacetStatesTableOrderingComposer,
          $$FacetStatesTableAnnotationComposer,
          $$FacetStatesTableCreateCompanionBuilder,
          $$FacetStatesTableUpdateCompanionBuilder,
          (
            FacetStateRow,
            BaseReferences<_$ProgressDb, $FacetStatesTable, FacetStateRow>,
          ),
          FacetStateRow,
          PrefetchHooks Function()
        > {
  $$FacetStatesTableTableManager(_$ProgressDb db, $FacetStatesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$FacetStatesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$FacetStatesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$FacetStatesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> facetId = const Value.absent(),
                Value<double> stability = const Value.absent(),
                Value<double> difficulty = const Value.absent(),
                Value<int> due = const Value.absent(),
                Value<int> lastReview = const Value.absent(),
                Value<int> reps = const Value.absent(),
                Value<int> lapses = const Value.absent(),
                Value<String> phase = const Value.absent(),
                Value<int?> step = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => FacetStatesCompanion(
                facetId: facetId,
                stability: stability,
                difficulty: difficulty,
                due: due,
                lastReview: lastReview,
                reps: reps,
                lapses: lapses,
                phase: phase,
                step: step,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String facetId,
                required double stability,
                required double difficulty,
                required int due,
                required int lastReview,
                required int reps,
                required int lapses,
                required String phase,
                Value<int?> step = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => FacetStatesCompanion.insert(
                facetId: facetId,
                stability: stability,
                difficulty: difficulty,
                due: due,
                lastReview: lastReview,
                reps: reps,
                lapses: lapses,
                phase: phase,
                step: step,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$FacetStatesTable, FacetStateRow>(table),
                  BaseReferences<
                    _$ProgressDb,
                    $FacetStatesTable,
                    FacetStateRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$FacetStatesTableProcessedTableManager =
    ProcessedTableManager<
      _$ProgressDb,
      $FacetStatesTable,
      FacetStateRow,
      $$FacetStatesTableFilterComposer,
      $$FacetStatesTableOrderingComposer,
      $$FacetStatesTableAnnotationComposer,
      $$FacetStatesTableCreateCompanionBuilder,
      $$FacetStatesTableUpdateCompanionBuilder,
      (
        FacetStateRow,
        BaseReferences<_$ProgressDb, $FacetStatesTable, FacetStateRow>,
      ),
      FacetStateRow,
      PrefetchHooks Function()
    >;
typedef $$MistakesTableCreateCompanionBuilder = MistakesCompanion Function({
  required String id,
  required String facetId,
  required int at,
  required String exerciseType,
  required String prompt,
  required String expected,
  required String given,
  Value<String?> skillId,
  Value<String?> note,
  Value<String?> explanation,
  Value<int> rowid,
});
typedef $$MistakesTableUpdateCompanionBuilder = MistakesCompanion Function({
  Value<String> id,
  Value<String> facetId,
  Value<int> at,
  Value<String> exerciseType,
  Value<String> prompt,
  Value<String> expected,
  Value<String> given,
  Value<String?> skillId,
  Value<String?> note,
  Value<String?> explanation,
  Value<int> rowid,
});

class $$MistakesTableFilterComposer
    extends Composer<_$ProgressDb, $MistakesTable> {
  $$MistakesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get facetId => $composableBuilder(
    column: $table.facetId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get at => $composableBuilder(
    column: $table.at,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get exerciseType => $composableBuilder(
    column: $table.exerciseType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get prompt => $composableBuilder(
    column: $table.prompt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get expected => $composableBuilder(
    column: $table.expected,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get given => $composableBuilder(
    column: $table.given,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get skillId => $composableBuilder(
    column: $table.skillId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get explanation => $composableBuilder(
    column: $table.explanation,
    builder: (column) => ColumnFilters(column),
  );
}

class $$MistakesTableOrderingComposer
    extends Composer<_$ProgressDb, $MistakesTable> {
  $$MistakesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get facetId => $composableBuilder(
    column: $table.facetId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get at => $composableBuilder(
    column: $table.at,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get exerciseType => $composableBuilder(
    column: $table.exerciseType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get prompt => $composableBuilder(
    column: $table.prompt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get expected => $composableBuilder(
    column: $table.expected,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get given => $composableBuilder(
    column: $table.given,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get skillId => $composableBuilder(
    column: $table.skillId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get note => $composableBuilder(
    column: $table.note,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get explanation => $composableBuilder(
    column: $table.explanation,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$MistakesTableAnnotationComposer
    extends Composer<_$ProgressDb, $MistakesTable> {
  $$MistakesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get facetId =>
      $composableBuilder(column: $table.facetId, builder: (column) => column);

  GeneratedColumn<int> get at =>
      $composableBuilder(column: $table.at, builder: (column) => column);

  GeneratedColumn<String> get exerciseType => $composableBuilder(
    column: $table.exerciseType,
    builder: (column) => column,
  );

  GeneratedColumn<String> get prompt =>
      $composableBuilder(column: $table.prompt, builder: (column) => column);

  GeneratedColumn<String> get expected =>
      $composableBuilder(column: $table.expected, builder: (column) => column);

  GeneratedColumn<String> get given =>
      $composableBuilder(column: $table.given, builder: (column) => column);

  GeneratedColumn<String> get skillId =>
      $composableBuilder(column: $table.skillId, builder: (column) => column);

  GeneratedColumn<String> get note =>
      $composableBuilder(column: $table.note, builder: (column) => column);

  GeneratedColumn<String> get explanation => $composableBuilder(
    column: $table.explanation,
    builder: (column) => column,
  );
}

class $$MistakesTableTableManager
    extends
        RootTableManager<
          _$ProgressDb,
          $MistakesTable,
          MistakeRow,
          $$MistakesTableFilterComposer,
          $$MistakesTableOrderingComposer,
          $$MistakesTableAnnotationComposer,
          $$MistakesTableCreateCompanionBuilder,
          $$MistakesTableUpdateCompanionBuilder,
          (
            MistakeRow,
            BaseReferences<_$ProgressDb, $MistakesTable, MistakeRow>,
          ),
          MistakeRow,
          PrefetchHooks Function()
        > {
  $$MistakesTableTableManager(_$ProgressDb db, $MistakesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MistakesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MistakesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MistakesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> facetId = const Value.absent(),
                Value<int> at = const Value.absent(),
                Value<String> exerciseType = const Value.absent(),
                Value<String> prompt = const Value.absent(),
                Value<String> expected = const Value.absent(),
                Value<String> given = const Value.absent(),
                Value<String?> skillId = const Value.absent(),
                Value<String?> note = const Value.absent(),
                Value<String?> explanation = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MistakesCompanion(
                id: id,
                facetId: facetId,
                at: at,
                exerciseType: exerciseType,
                prompt: prompt,
                expected: expected,
                given: given,
                skillId: skillId,
                note: note,
                explanation: explanation,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String facetId,
                required int at,
                required String exerciseType,
                required String prompt,
                required String expected,
                required String given,
                Value<String?> skillId = const Value.absent(),
                Value<String?> note = const Value.absent(),
                Value<String?> explanation = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MistakesCompanion.insert(
                id: id,
                facetId: facetId,
                at: at,
                exerciseType: exerciseType,
                prompt: prompt,
                expected: expected,
                given: given,
                skillId: skillId,
                note: note,
                explanation: explanation,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$MistakesTable, MistakeRow>(table),
                  BaseReferences<_$ProgressDb, $MistakesTable, MistakeRow>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$MistakesTableProcessedTableManager =
    ProcessedTableManager<
      _$ProgressDb,
      $MistakesTable,
      MistakeRow,
      $$MistakesTableFilterComposer,
      $$MistakesTableOrderingComposer,
      $$MistakesTableAnnotationComposer,
      $$MistakesTableCreateCompanionBuilder,
      $$MistakesTableUpdateCompanionBuilder,
      (MistakeRow, BaseReferences<_$ProgressDb, $MistakesTable, MistakeRow>),
      MistakeRow,
      PrefetchHooks Function()
    >;
typedef $$SettingsTableCreateCompanionBuilder = SettingsCompanion Function({
  required String key,
  required String value,
  Value<int> rowid,
});
typedef $$SettingsTableUpdateCompanionBuilder = SettingsCompanion Function({
  Value<String> key,
  Value<String> value,
  Value<int> rowid,
});

class $$SettingsTableFilterComposer
    extends Composer<_$ProgressDb, $SettingsTable> {
  $$SettingsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SettingsTableOrderingComposer
    extends Composer<_$ProgressDb, $SettingsTable> {
  $$SettingsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SettingsTableAnnotationComposer
    extends Composer<_$ProgressDb, $SettingsTable> {
  $$SettingsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);
}

class $$SettingsTableTableManager
    extends
        RootTableManager<
          _$ProgressDb,
          $SettingsTable,
          SettingRow,
          $$SettingsTableFilterComposer,
          $$SettingsTableOrderingComposer,
          $$SettingsTableAnnotationComposer,
          $$SettingsTableCreateCompanionBuilder,
          $$SettingsTableUpdateCompanionBuilder,
          (
            SettingRow,
            BaseReferences<_$ProgressDb, $SettingsTable, SettingRow>,
          ),
          SettingRow,
          PrefetchHooks Function()
        > {
  $$SettingsTableTableManager(_$ProgressDb db, $SettingsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SettingsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SettingsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SettingsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> key = const Value.absent(),
            Value<String> value = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) => SettingsCompanion(key: key, value: value, rowid: rowid),
          createCompanionCallback: ({
            required String key,
            required String value,
            Value<int> rowid = const Value.absent(),
          }) => SettingsCompanion.insert(key: key, value: value, rowid: rowid),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$SettingsTable, SettingRow>(table),
                  BaseReferences<_$ProgressDb, $SettingsTable, SettingRow>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SettingsTableProcessedTableManager =
    ProcessedTableManager<
      _$ProgressDb,
      $SettingsTable,
      SettingRow,
      $$SettingsTableFilterComposer,
      $$SettingsTableOrderingComposer,
      $$SettingsTableAnnotationComposer,
      $$SettingsTableCreateCompanionBuilder,
      $$SettingsTableUpdateCompanionBuilder,
      (SettingRow, BaseReferences<_$ProgressDb, $SettingsTable, SettingRow>),
      SettingRow,
      PrefetchHooks Function()
    >;

class $ProgressDbManager {
  final _$ProgressDb _db;
  $ProgressDbManager(this._db);
  $$ReviewLogEntriesTableTableManager get reviewLogEntries =>
      $$ReviewLogEntriesTableTableManager(_db, _db.reviewLogEntries);
  $$FacetStatesTableTableManager get facetStates =>
      $$FacetStatesTableTableManager(_db, _db.facetStates);
  $$MistakesTableTableManager get mistakes =>
      $$MistakesTableTableManager(_db, _db.mistakes);
  $$SettingsTableTableManager get settings =>
      $$SettingsTableTableManager(_db, _db.settings);
}

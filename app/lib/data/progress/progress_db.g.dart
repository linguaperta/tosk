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

class $AiExplanationsTable extends AiExplanations
    with TableInfo<$AiExplanationsTable, AiExplanationRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AiExplanationsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _fingerprintMeta = const VerificationMeta(
    'fingerprint',
  );
  @override
  late final GeneratedColumn<String> fingerprint = GeneratedColumn<String>(
    'fingerprint',
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
  static const VerificationMeta _langMeta = const VerificationMeta('lang');
  @override
  late final GeneratedColumn<String> lang = GeneratedColumn<String>(
    'lang',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _bodyMeta = const VerificationMeta('body');
  @override
  late final GeneratedColumn<String> body = GeneratedColumn<String>(
    'body',
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
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _providerMeta = const VerificationMeta(
    'provider',
  );
  @override
  late final GeneratedColumn<String> provider = GeneratedColumn<String>(
    'provider',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _modelMeta = const VerificationMeta('model');
  @override
  late final GeneratedColumn<String> model = GeneratedColumn<String>(
    'model',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    fingerprint,
    given,
    lang,
    body,
    facetId,
    provider,
    model,
    createdAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'ai_explanations';
  @override
  VerificationContext validateIntegrity(
    Insertable<AiExplanationRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('fingerprint')) {
      context.handle(
        _fingerprintMeta,
        fingerprint.isAcceptableOrUnknown(
          data['fingerprint']!,
          _fingerprintMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_fingerprintMeta);
    }
    if (data.containsKey('given')) {
      context.handle(
        _givenMeta,
        given.isAcceptableOrUnknown(data['given']!, _givenMeta),
      );
    } else if (isInserting) {
      context.missing(_givenMeta);
    }
    if (data.containsKey('lang')) {
      context.handle(
        _langMeta,
        lang.isAcceptableOrUnknown(data['lang']!, _langMeta),
      );
    } else if (isInserting) {
      context.missing(_langMeta);
    }
    if (data.containsKey('body')) {
      context.handle(
        _bodyMeta,
        body.isAcceptableOrUnknown(data['body']!, _bodyMeta),
      );
    } else if (isInserting) {
      context.missing(_bodyMeta);
    }
    if (data.containsKey('facet_id')) {
      context.handle(
        _facetIdMeta,
        facetId.isAcceptableOrUnknown(data['facet_id']!, _facetIdMeta),
      );
    }
    if (data.containsKey('provider')) {
      context.handle(
        _providerMeta,
        provider.isAcceptableOrUnknown(data['provider']!, _providerMeta),
      );
    }
    if (data.containsKey('model')) {
      context.handle(
        _modelMeta,
        model.isAcceptableOrUnknown(data['model']!, _modelMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {fingerprint, given, lang};
  @override
  AiExplanationRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AiExplanationRow(
      fingerprint: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}fingerprint'],
      )!,
      given: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}given'],
      )!,
      lang: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}lang'],
      )!,
      body: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}body'],
      )!,
      facetId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}facet_id'],
      ),
      provider: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}provider'],
      ),
      model: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}model'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $AiExplanationsTable createAlias(String alias) {
    return $AiExplanationsTable(attachedDatabase, alias);
  }
}

class AiExplanationRow extends DataClass
    implements Insertable<AiExplanationRow> {
  final String fingerprint;
  final String given;
  final String lang;
  final String body;
  final String? facetId;
  final String? provider;
  final String? model;
  final int createdAt;
  const AiExplanationRow({
    required this.fingerprint,
    required this.given,
    required this.lang,
    required this.body,
    this.facetId,
    this.provider,
    this.model,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['fingerprint'] = Variable<String>(fingerprint);
    map['given'] = Variable<String>(given);
    map['lang'] = Variable<String>(lang);
    map['body'] = Variable<String>(body);
    if (!nullToAbsent || facetId != null) {
      map['facet_id'] = Variable<String>(facetId);
    }
    if (!nullToAbsent || provider != null) {
      map['provider'] = Variable<String>(provider);
    }
    if (!nullToAbsent || model != null) {
      map['model'] = Variable<String>(model);
    }
    map['created_at'] = Variable<int>(createdAt);
    return map;
  }

  AiExplanationsCompanion toCompanion(bool nullToAbsent) {
    return AiExplanationsCompanion(
      fingerprint: Value(fingerprint),
      given: Value(given),
      lang: Value(lang),
      body: Value(body),
      facetId: facetId == null && nullToAbsent
          ? const Value.absent()
          : Value(facetId),
      provider: provider == null && nullToAbsent
          ? const Value.absent()
          : Value(provider),
      model: model == null && nullToAbsent
          ? const Value.absent()
          : Value(model),
      createdAt: Value(createdAt),
    );
  }

  factory AiExplanationRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AiExplanationRow(
      fingerprint: serializer.fromJson<String>(json['fingerprint']),
      given: serializer.fromJson<String>(json['given']),
      lang: serializer.fromJson<String>(json['lang']),
      body: serializer.fromJson<String>(json['body']),
      facetId: serializer.fromJson<String?>(json['facetId']),
      provider: serializer.fromJson<String?>(json['provider']),
      model: serializer.fromJson<String?>(json['model']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'fingerprint': serializer.toJson<String>(fingerprint),
      'given': serializer.toJson<String>(given),
      'lang': serializer.toJson<String>(lang),
      'body': serializer.toJson<String>(body),
      'facetId': serializer.toJson<String?>(facetId),
      'provider': serializer.toJson<String?>(provider),
      'model': serializer.toJson<String?>(model),
      'createdAt': serializer.toJson<int>(createdAt),
    };
  }

  AiExplanationRow copyWith({
    String? fingerprint,
    String? given,
    String? lang,
    String? body,
    Value<String?> facetId = const Value.absent(),
    Value<String?> provider = const Value.absent(),
    Value<String?> model = const Value.absent(),
    int? createdAt,
  }) => AiExplanationRow(
    fingerprint: fingerprint ?? this.fingerprint,
    given: given ?? this.given,
    lang: lang ?? this.lang,
    body: body ?? this.body,
    facetId: facetId.present ? facetId.value : this.facetId,
    provider: provider.present ? provider.value : this.provider,
    model: model.present ? model.value : this.model,
    createdAt: createdAt ?? this.createdAt,
  );
  AiExplanationRow copyWithCompanion(AiExplanationsCompanion data) {
    return AiExplanationRow(
      fingerprint: data.fingerprint.present
          ? data.fingerprint.value
          : this.fingerprint,
      given: data.given.present ? data.given.value : this.given,
      lang: data.lang.present ? data.lang.value : this.lang,
      body: data.body.present ? data.body.value : this.body,
      facetId: data.facetId.present ? data.facetId.value : this.facetId,
      provider: data.provider.present ? data.provider.value : this.provider,
      model: data.model.present ? data.model.value : this.model,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AiExplanationRow(')
          ..write('fingerprint: $fingerprint, ')
          ..write('given: $given, ')
          ..write('lang: $lang, ')
          ..write('body: $body, ')
          ..write('facetId: $facetId, ')
          ..write('provider: $provider, ')
          ..write('model: $model, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    fingerprint,
    given,
    lang,
    body,
    facetId,
    provider,
    model,
    createdAt,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AiExplanationRow &&
          other.fingerprint == this.fingerprint &&
          other.given == this.given &&
          other.lang == this.lang &&
          other.body == this.body &&
          other.facetId == this.facetId &&
          other.provider == this.provider &&
          other.model == this.model &&
          other.createdAt == this.createdAt);
}

class AiExplanationsCompanion extends UpdateCompanion<AiExplanationRow> {
  final Value<String> fingerprint;
  final Value<String> given;
  final Value<String> lang;
  final Value<String> body;
  final Value<String?> facetId;
  final Value<String?> provider;
  final Value<String?> model;
  final Value<int> createdAt;
  final Value<int> rowid;
  const AiExplanationsCompanion({
    this.fingerprint = const Value.absent(),
    this.given = const Value.absent(),
    this.lang = const Value.absent(),
    this.body = const Value.absent(),
    this.facetId = const Value.absent(),
    this.provider = const Value.absent(),
    this.model = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AiExplanationsCompanion.insert({
    required String fingerprint,
    required String given,
    required String lang,
    required String body,
    this.facetId = const Value.absent(),
    this.provider = const Value.absent(),
    this.model = const Value.absent(),
    required int createdAt,
    this.rowid = const Value.absent(),
  }) : fingerprint = Value(fingerprint),
       given = Value(given),
       lang = Value(lang),
       body = Value(body),
       createdAt = Value(createdAt);
  static Insertable<AiExplanationRow> custom({
    Expression<String>? fingerprint,
    Expression<String>? given,
    Expression<String>? lang,
    Expression<String>? body,
    Expression<String>? facetId,
    Expression<String>? provider,
    Expression<String>? model,
    Expression<int>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (fingerprint != null) 'fingerprint': fingerprint,
      if (given != null) 'given': given,
      if (lang != null) 'lang': lang,
      if (body != null) 'body': body,
      if (facetId != null) 'facet_id': facetId,
      if (provider != null) 'provider': provider,
      if (model != null) 'model': model,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AiExplanationsCompanion copyWith({
    Value<String>? fingerprint,
    Value<String>? given,
    Value<String>? lang,
    Value<String>? body,
    Value<String?>? facetId,
    Value<String?>? provider,
    Value<String?>? model,
    Value<int>? createdAt,
    Value<int>? rowid,
  }) {
    return AiExplanationsCompanion(
      fingerprint: fingerprint ?? this.fingerprint,
      given: given ?? this.given,
      lang: lang ?? this.lang,
      body: body ?? this.body,
      facetId: facetId ?? this.facetId,
      provider: provider ?? this.provider,
      model: model ?? this.model,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (fingerprint.present) {
      map['fingerprint'] = Variable<String>(fingerprint.value);
    }
    if (given.present) {
      map['given'] = Variable<String>(given.value);
    }
    if (lang.present) {
      map['lang'] = Variable<String>(lang.value);
    }
    if (body.present) {
      map['body'] = Variable<String>(body.value);
    }
    if (facetId.present) {
      map['facet_id'] = Variable<String>(facetId.value);
    }
    if (provider.present) {
      map['provider'] = Variable<String>(provider.value);
    }
    if (model.present) {
      map['model'] = Variable<String>(model.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AiExplanationsCompanion(')
          ..write('fingerprint: $fingerprint, ')
          ..write('given: $given, ')
          ..write('lang: $lang, ')
          ..write('body: $body, ')
          ..write('facetId: $facetId, ')
          ..write('provider: $provider, ')
          ..write('model: $model, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $FlagsTable extends Flags with TableInfo<$FlagsTable, FlagRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $FlagsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _courseIdMeta = const VerificationMeta(
    'courseId',
  );
  @override
  late final GeneratedColumn<String> courseId = GeneratedColumn<String>(
    'course_id',
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
  static const VerificationMeta _exerciseJsonMeta = const VerificationMeta(
    'exerciseJson',
  );
  @override
  late final GeneratedColumn<String> exerciseJson = GeneratedColumn<String>(
    'exercise_json',
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
  static const VerificationMeta _reasonMeta = const VerificationMeta('reason');
  @override
  late final GeneratedColumn<String> reason = GeneratedColumn<String>(
    'reason',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _commentMeta = const VerificationMeta(
    'comment',
  );
  @override
  late final GeneratedColumn<String> comment = GeneratedColumn<String>(
    'comment',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _aiVerdictMeta = const VerificationMeta(
    'aiVerdict',
  );
  @override
  late final GeneratedColumn<String> aiVerdict = GeneratedColumn<String>(
    'ai_verdict',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _aiReasoningMeta = const VerificationMeta(
    'aiReasoning',
  );
  @override
  late final GeneratedColumn<String> aiReasoning = GeneratedColumn<String>(
    'ai_reasoning',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _appVersionMeta = const VerificationMeta(
    'appVersion',
  );
  @override
  late final GeneratedColumn<String> appVersion = GeneratedColumn<String>(
    'app_version',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _packVersionMeta = const VerificationMeta(
    'packVersion',
  );
  @override
  late final GeneratedColumn<String> packVersion = GeneratedColumn<String>(
    'pack_version',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sourceLangMeta = const VerificationMeta(
    'sourceLang',
  );
  @override
  late final GeneratedColumn<String> sourceLang = GeneratedColumn<String>(
    'source_lang',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    createdAt,
    courseId,
    skillId,
    facetId,
    exerciseType,
    exerciseJson,
    given,
    expected,
    correct,
    reason,
    comment,
    aiVerdict,
    aiReasoning,
    appVersion,
    packVersion,
    sourceLang,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'flags';
  @override
  VerificationContext validateIntegrity(
    Insertable<FlagRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('course_id')) {
      context.handle(
        _courseIdMeta,
        courseId.isAcceptableOrUnknown(data['course_id']!, _courseIdMeta),
      );
    } else if (isInserting) {
      context.missing(_courseIdMeta);
    }
    if (data.containsKey('skill_id')) {
      context.handle(
        _skillIdMeta,
        skillId.isAcceptableOrUnknown(data['skill_id']!, _skillIdMeta),
      );
    }
    if (data.containsKey('facet_id')) {
      context.handle(
        _facetIdMeta,
        facetId.isAcceptableOrUnknown(data['facet_id']!, _facetIdMeta),
      );
    } else if (isInserting) {
      context.missing(_facetIdMeta);
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
    if (data.containsKey('exercise_json')) {
      context.handle(
        _exerciseJsonMeta,
        exerciseJson.isAcceptableOrUnknown(
          data['exercise_json']!,
          _exerciseJsonMeta,
        ),
      );
    } else if (isInserting) {
      context.missing(_exerciseJsonMeta);
    }
    if (data.containsKey('given')) {
      context.handle(
        _givenMeta,
        given.isAcceptableOrUnknown(data['given']!, _givenMeta),
      );
    } else if (isInserting) {
      context.missing(_givenMeta);
    }
    if (data.containsKey('expected')) {
      context.handle(
        _expectedMeta,
        expected.isAcceptableOrUnknown(data['expected']!, _expectedMeta),
      );
    } else if (isInserting) {
      context.missing(_expectedMeta);
    }
    if (data.containsKey('correct')) {
      context.handle(
        _correctMeta,
        correct.isAcceptableOrUnknown(data['correct']!, _correctMeta),
      );
    } else if (isInserting) {
      context.missing(_correctMeta);
    }
    if (data.containsKey('reason')) {
      context.handle(
        _reasonMeta,
        reason.isAcceptableOrUnknown(data['reason']!, _reasonMeta),
      );
    } else if (isInserting) {
      context.missing(_reasonMeta);
    }
    if (data.containsKey('comment')) {
      context.handle(
        _commentMeta,
        comment.isAcceptableOrUnknown(data['comment']!, _commentMeta),
      );
    }
    if (data.containsKey('ai_verdict')) {
      context.handle(
        _aiVerdictMeta,
        aiVerdict.isAcceptableOrUnknown(data['ai_verdict']!, _aiVerdictMeta),
      );
    }
    if (data.containsKey('ai_reasoning')) {
      context.handle(
        _aiReasoningMeta,
        aiReasoning.isAcceptableOrUnknown(
          data['ai_reasoning']!,
          _aiReasoningMeta,
        ),
      );
    }
    if (data.containsKey('app_version')) {
      context.handle(
        _appVersionMeta,
        appVersion.isAcceptableOrUnknown(data['app_version']!, _appVersionMeta),
      );
    }
    if (data.containsKey('pack_version')) {
      context.handle(
        _packVersionMeta,
        packVersion.isAcceptableOrUnknown(
          data['pack_version']!,
          _packVersionMeta,
        ),
      );
    }
    if (data.containsKey('source_lang')) {
      context.handle(
        _sourceLangMeta,
        sourceLang.isAcceptableOrUnknown(data['source_lang']!, _sourceLangMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  FlagRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return FlagRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
      courseId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}course_id'],
      )!,
      skillId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}skill_id'],
      ),
      facetId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}facet_id'],
      )!,
      exerciseType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}exercise_type'],
      )!,
      exerciseJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}exercise_json'],
      )!,
      given: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}given'],
      )!,
      expected: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}expected'],
      )!,
      correct: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}correct'],
      )!,
      reason: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}reason'],
      )!,
      comment: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}comment'],
      )!,
      aiVerdict: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}ai_verdict'],
      ),
      aiReasoning: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}ai_reasoning'],
      ),
      appVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}app_version'],
      ),
      packVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}pack_version'],
      ),
      sourceLang: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_lang'],
      ),
    );
  }

  @override
  $FlagsTable createAlias(String alias) {
    return $FlagsTable(attachedDatabase, alias);
  }
}

class FlagRow extends DataClass implements Insertable<FlagRow> {
  final String id;
  final int createdAt;
  final String courseId;
  final String? skillId;
  final String facetId;
  final String exerciseType;
  final String exerciseJson;
  final String given;
  final String expected;
  final bool correct;
  final String reason;
  final String comment;
  final String? aiVerdict;
  final String? aiReasoning;
  final String? appVersion;
  final String? packVersion;
  final String? sourceLang;
  const FlagRow({
    required this.id,
    required this.createdAt,
    required this.courseId,
    this.skillId,
    required this.facetId,
    required this.exerciseType,
    required this.exerciseJson,
    required this.given,
    required this.expected,
    required this.correct,
    required this.reason,
    required this.comment,
    this.aiVerdict,
    this.aiReasoning,
    this.appVersion,
    this.packVersion,
    this.sourceLang,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['created_at'] = Variable<int>(createdAt);
    map['course_id'] = Variable<String>(courseId);
    if (!nullToAbsent || skillId != null) {
      map['skill_id'] = Variable<String>(skillId);
    }
    map['facet_id'] = Variable<String>(facetId);
    map['exercise_type'] = Variable<String>(exerciseType);
    map['exercise_json'] = Variable<String>(exerciseJson);
    map['given'] = Variable<String>(given);
    map['expected'] = Variable<String>(expected);
    map['correct'] = Variable<bool>(correct);
    map['reason'] = Variable<String>(reason);
    map['comment'] = Variable<String>(comment);
    if (!nullToAbsent || aiVerdict != null) {
      map['ai_verdict'] = Variable<String>(aiVerdict);
    }
    if (!nullToAbsent || aiReasoning != null) {
      map['ai_reasoning'] = Variable<String>(aiReasoning);
    }
    if (!nullToAbsent || appVersion != null) {
      map['app_version'] = Variable<String>(appVersion);
    }
    if (!nullToAbsent || packVersion != null) {
      map['pack_version'] = Variable<String>(packVersion);
    }
    if (!nullToAbsent || sourceLang != null) {
      map['source_lang'] = Variable<String>(sourceLang);
    }
    return map;
  }

  FlagsCompanion toCompanion(bool nullToAbsent) {
    return FlagsCompanion(
      id: Value(id),
      createdAt: Value(createdAt),
      courseId: Value(courseId),
      skillId: skillId == null && nullToAbsent
          ? const Value.absent()
          : Value(skillId),
      facetId: Value(facetId),
      exerciseType: Value(exerciseType),
      exerciseJson: Value(exerciseJson),
      given: Value(given),
      expected: Value(expected),
      correct: Value(correct),
      reason: Value(reason),
      comment: Value(comment),
      aiVerdict: aiVerdict == null && nullToAbsent
          ? const Value.absent()
          : Value(aiVerdict),
      aiReasoning: aiReasoning == null && nullToAbsent
          ? const Value.absent()
          : Value(aiReasoning),
      appVersion: appVersion == null && nullToAbsent
          ? const Value.absent()
          : Value(appVersion),
      packVersion: packVersion == null && nullToAbsent
          ? const Value.absent()
          : Value(packVersion),
      sourceLang: sourceLang == null && nullToAbsent
          ? const Value.absent()
          : Value(sourceLang),
    );
  }

  factory FlagRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return FlagRow(
      id: serializer.fromJson<String>(json['id']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      courseId: serializer.fromJson<String>(json['courseId']),
      skillId: serializer.fromJson<String?>(json['skillId']),
      facetId: serializer.fromJson<String>(json['facetId']),
      exerciseType: serializer.fromJson<String>(json['exerciseType']),
      exerciseJson: serializer.fromJson<String>(json['exerciseJson']),
      given: serializer.fromJson<String>(json['given']),
      expected: serializer.fromJson<String>(json['expected']),
      correct: serializer.fromJson<bool>(json['correct']),
      reason: serializer.fromJson<String>(json['reason']),
      comment: serializer.fromJson<String>(json['comment']),
      aiVerdict: serializer.fromJson<String?>(json['aiVerdict']),
      aiReasoning: serializer.fromJson<String?>(json['aiReasoning']),
      appVersion: serializer.fromJson<String?>(json['appVersion']),
      packVersion: serializer.fromJson<String?>(json['packVersion']),
      sourceLang: serializer.fromJson<String?>(json['sourceLang']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'createdAt': serializer.toJson<int>(createdAt),
      'courseId': serializer.toJson<String>(courseId),
      'skillId': serializer.toJson<String?>(skillId),
      'facetId': serializer.toJson<String>(facetId),
      'exerciseType': serializer.toJson<String>(exerciseType),
      'exerciseJson': serializer.toJson<String>(exerciseJson),
      'given': serializer.toJson<String>(given),
      'expected': serializer.toJson<String>(expected),
      'correct': serializer.toJson<bool>(correct),
      'reason': serializer.toJson<String>(reason),
      'comment': serializer.toJson<String>(comment),
      'aiVerdict': serializer.toJson<String?>(aiVerdict),
      'aiReasoning': serializer.toJson<String?>(aiReasoning),
      'appVersion': serializer.toJson<String?>(appVersion),
      'packVersion': serializer.toJson<String?>(packVersion),
      'sourceLang': serializer.toJson<String?>(sourceLang),
    };
  }

  FlagRow copyWith({
    String? id,
    int? createdAt,
    String? courseId,
    Value<String?> skillId = const Value.absent(),
    String? facetId,
    String? exerciseType,
    String? exerciseJson,
    String? given,
    String? expected,
    bool? correct,
    String? reason,
    String? comment,
    Value<String?> aiVerdict = const Value.absent(),
    Value<String?> aiReasoning = const Value.absent(),
    Value<String?> appVersion = const Value.absent(),
    Value<String?> packVersion = const Value.absent(),
    Value<String?> sourceLang = const Value.absent(),
  }) => FlagRow(
    id: id ?? this.id,
    createdAt: createdAt ?? this.createdAt,
    courseId: courseId ?? this.courseId,
    skillId: skillId.present ? skillId.value : this.skillId,
    facetId: facetId ?? this.facetId,
    exerciseType: exerciseType ?? this.exerciseType,
    exerciseJson: exerciseJson ?? this.exerciseJson,
    given: given ?? this.given,
    expected: expected ?? this.expected,
    correct: correct ?? this.correct,
    reason: reason ?? this.reason,
    comment: comment ?? this.comment,
    aiVerdict: aiVerdict.present ? aiVerdict.value : this.aiVerdict,
    aiReasoning: aiReasoning.present ? aiReasoning.value : this.aiReasoning,
    appVersion: appVersion.present ? appVersion.value : this.appVersion,
    packVersion: packVersion.present ? packVersion.value : this.packVersion,
    sourceLang: sourceLang.present ? sourceLang.value : this.sourceLang,
  );
  FlagRow copyWithCompanion(FlagsCompanion data) {
    return FlagRow(
      id: data.id.present ? data.id.value : this.id,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      courseId: data.courseId.present ? data.courseId.value : this.courseId,
      skillId: data.skillId.present ? data.skillId.value : this.skillId,
      facetId: data.facetId.present ? data.facetId.value : this.facetId,
      exerciseType: data.exerciseType.present
          ? data.exerciseType.value
          : this.exerciseType,
      exerciseJson: data.exerciseJson.present
          ? data.exerciseJson.value
          : this.exerciseJson,
      given: data.given.present ? data.given.value : this.given,
      expected: data.expected.present ? data.expected.value : this.expected,
      correct: data.correct.present ? data.correct.value : this.correct,
      reason: data.reason.present ? data.reason.value : this.reason,
      comment: data.comment.present ? data.comment.value : this.comment,
      aiVerdict: data.aiVerdict.present ? data.aiVerdict.value : this.aiVerdict,
      aiReasoning: data.aiReasoning.present
          ? data.aiReasoning.value
          : this.aiReasoning,
      appVersion: data.appVersion.present
          ? data.appVersion.value
          : this.appVersion,
      packVersion: data.packVersion.present
          ? data.packVersion.value
          : this.packVersion,
      sourceLang: data.sourceLang.present
          ? data.sourceLang.value
          : this.sourceLang,
    );
  }

  @override
  String toString() {
    return (StringBuffer('FlagRow(')
          ..write('id: $id, ')
          ..write('createdAt: $createdAt, ')
          ..write('courseId: $courseId, ')
          ..write('skillId: $skillId, ')
          ..write('facetId: $facetId, ')
          ..write('exerciseType: $exerciseType, ')
          ..write('exerciseJson: $exerciseJson, ')
          ..write('given: $given, ')
          ..write('expected: $expected, ')
          ..write('correct: $correct, ')
          ..write('reason: $reason, ')
          ..write('comment: $comment, ')
          ..write('aiVerdict: $aiVerdict, ')
          ..write('aiReasoning: $aiReasoning, ')
          ..write('appVersion: $appVersion, ')
          ..write('packVersion: $packVersion, ')
          ..write('sourceLang: $sourceLang')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    createdAt,
    courseId,
    skillId,
    facetId,
    exerciseType,
    exerciseJson,
    given,
    expected,
    correct,
    reason,
    comment,
    aiVerdict,
    aiReasoning,
    appVersion,
    packVersion,
    sourceLang,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is FlagRow &&
          other.id == this.id &&
          other.createdAt == this.createdAt &&
          other.courseId == this.courseId &&
          other.skillId == this.skillId &&
          other.facetId == this.facetId &&
          other.exerciseType == this.exerciseType &&
          other.exerciseJson == this.exerciseJson &&
          other.given == this.given &&
          other.expected == this.expected &&
          other.correct == this.correct &&
          other.reason == this.reason &&
          other.comment == this.comment &&
          other.aiVerdict == this.aiVerdict &&
          other.aiReasoning == this.aiReasoning &&
          other.appVersion == this.appVersion &&
          other.packVersion == this.packVersion &&
          other.sourceLang == this.sourceLang);
}

class FlagsCompanion extends UpdateCompanion<FlagRow> {
  final Value<String> id;
  final Value<int> createdAt;
  final Value<String> courseId;
  final Value<String?> skillId;
  final Value<String> facetId;
  final Value<String> exerciseType;
  final Value<String> exerciseJson;
  final Value<String> given;
  final Value<String> expected;
  final Value<bool> correct;
  final Value<String> reason;
  final Value<String> comment;
  final Value<String?> aiVerdict;
  final Value<String?> aiReasoning;
  final Value<String?> appVersion;
  final Value<String?> packVersion;
  final Value<String?> sourceLang;
  final Value<int> rowid;
  const FlagsCompanion({
    this.id = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.courseId = const Value.absent(),
    this.skillId = const Value.absent(),
    this.facetId = const Value.absent(),
    this.exerciseType = const Value.absent(),
    this.exerciseJson = const Value.absent(),
    this.given = const Value.absent(),
    this.expected = const Value.absent(),
    this.correct = const Value.absent(),
    this.reason = const Value.absent(),
    this.comment = const Value.absent(),
    this.aiVerdict = const Value.absent(),
    this.aiReasoning = const Value.absent(),
    this.appVersion = const Value.absent(),
    this.packVersion = const Value.absent(),
    this.sourceLang = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  FlagsCompanion.insert({
    required String id,
    required int createdAt,
    required String courseId,
    this.skillId = const Value.absent(),
    required String facetId,
    required String exerciseType,
    required String exerciseJson,
    required String given,
    required String expected,
    required bool correct,
    required String reason,
    this.comment = const Value.absent(),
    this.aiVerdict = const Value.absent(),
    this.aiReasoning = const Value.absent(),
    this.appVersion = const Value.absent(),
    this.packVersion = const Value.absent(),
    this.sourceLang = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       createdAt = Value(createdAt),
       courseId = Value(courseId),
       facetId = Value(facetId),
       exerciseType = Value(exerciseType),
       exerciseJson = Value(exerciseJson),
       given = Value(given),
       expected = Value(expected),
       correct = Value(correct),
       reason = Value(reason);
  static Insertable<FlagRow> custom({
    Expression<String>? id,
    Expression<int>? createdAt,
    Expression<String>? courseId,
    Expression<String>? skillId,
    Expression<String>? facetId,
    Expression<String>? exerciseType,
    Expression<String>? exerciseJson,
    Expression<String>? given,
    Expression<String>? expected,
    Expression<bool>? correct,
    Expression<String>? reason,
    Expression<String>? comment,
    Expression<String>? aiVerdict,
    Expression<String>? aiReasoning,
    Expression<String>? appVersion,
    Expression<String>? packVersion,
    Expression<String>? sourceLang,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (createdAt != null) 'created_at': createdAt,
      if (courseId != null) 'course_id': courseId,
      if (skillId != null) 'skill_id': skillId,
      if (facetId != null) 'facet_id': facetId,
      if (exerciseType != null) 'exercise_type': exerciseType,
      if (exerciseJson != null) 'exercise_json': exerciseJson,
      if (given != null) 'given': given,
      if (expected != null) 'expected': expected,
      if (correct != null) 'correct': correct,
      if (reason != null) 'reason': reason,
      if (comment != null) 'comment': comment,
      if (aiVerdict != null) 'ai_verdict': aiVerdict,
      if (aiReasoning != null) 'ai_reasoning': aiReasoning,
      if (appVersion != null) 'app_version': appVersion,
      if (packVersion != null) 'pack_version': packVersion,
      if (sourceLang != null) 'source_lang': sourceLang,
      if (rowid != null) 'rowid': rowid,
    });
  }

  FlagsCompanion copyWith({
    Value<String>? id,
    Value<int>? createdAt,
    Value<String>? courseId,
    Value<String?>? skillId,
    Value<String>? facetId,
    Value<String>? exerciseType,
    Value<String>? exerciseJson,
    Value<String>? given,
    Value<String>? expected,
    Value<bool>? correct,
    Value<String>? reason,
    Value<String>? comment,
    Value<String?>? aiVerdict,
    Value<String?>? aiReasoning,
    Value<String?>? appVersion,
    Value<String?>? packVersion,
    Value<String?>? sourceLang,
    Value<int>? rowid,
  }) {
    return FlagsCompanion(
      id: id ?? this.id,
      createdAt: createdAt ?? this.createdAt,
      courseId: courseId ?? this.courseId,
      skillId: skillId ?? this.skillId,
      facetId: facetId ?? this.facetId,
      exerciseType: exerciseType ?? this.exerciseType,
      exerciseJson: exerciseJson ?? this.exerciseJson,
      given: given ?? this.given,
      expected: expected ?? this.expected,
      correct: correct ?? this.correct,
      reason: reason ?? this.reason,
      comment: comment ?? this.comment,
      aiVerdict: aiVerdict ?? this.aiVerdict,
      aiReasoning: aiReasoning ?? this.aiReasoning,
      appVersion: appVersion ?? this.appVersion,
      packVersion: packVersion ?? this.packVersion,
      sourceLang: sourceLang ?? this.sourceLang,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (courseId.present) {
      map['course_id'] = Variable<String>(courseId.value);
    }
    if (skillId.present) {
      map['skill_id'] = Variable<String>(skillId.value);
    }
    if (facetId.present) {
      map['facet_id'] = Variable<String>(facetId.value);
    }
    if (exerciseType.present) {
      map['exercise_type'] = Variable<String>(exerciseType.value);
    }
    if (exerciseJson.present) {
      map['exercise_json'] = Variable<String>(exerciseJson.value);
    }
    if (given.present) {
      map['given'] = Variable<String>(given.value);
    }
    if (expected.present) {
      map['expected'] = Variable<String>(expected.value);
    }
    if (correct.present) {
      map['correct'] = Variable<bool>(correct.value);
    }
    if (reason.present) {
      map['reason'] = Variable<String>(reason.value);
    }
    if (comment.present) {
      map['comment'] = Variable<String>(comment.value);
    }
    if (aiVerdict.present) {
      map['ai_verdict'] = Variable<String>(aiVerdict.value);
    }
    if (aiReasoning.present) {
      map['ai_reasoning'] = Variable<String>(aiReasoning.value);
    }
    if (appVersion.present) {
      map['app_version'] = Variable<String>(appVersion.value);
    }
    if (packVersion.present) {
      map['pack_version'] = Variable<String>(packVersion.value);
    }
    if (sourceLang.present) {
      map['source_lang'] = Variable<String>(sourceLang.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('FlagsCompanion(')
          ..write('id: $id, ')
          ..write('createdAt: $createdAt, ')
          ..write('courseId: $courseId, ')
          ..write('skillId: $skillId, ')
          ..write('facetId: $facetId, ')
          ..write('exerciseType: $exerciseType, ')
          ..write('exerciseJson: $exerciseJson, ')
          ..write('given: $given, ')
          ..write('expected: $expected, ')
          ..write('correct: $correct, ')
          ..write('reason: $reason, ')
          ..write('comment: $comment, ')
          ..write('aiVerdict: $aiVerdict, ')
          ..write('aiReasoning: $aiReasoning, ')
          ..write('appVersion: $appVersion, ')
          ..write('packVersion: $packVersion, ')
          ..write('sourceLang: $sourceLang, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $BookmarksTable extends Bookmarks
    with TableInfo<$BookmarksTable, BookmarkRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $BookmarksTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _courseIdMeta = const VerificationMeta(
    'courseId',
  );
  @override
  late final GeneratedColumn<String> courseId = GeneratedColumn<String>(
    'course_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _kindMeta = const VerificationMeta('kind');
  @override
  late final GeneratedColumn<String> kind = GeneratedColumn<String>(
    'kind',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _refIdMeta = const VerificationMeta('refId');
  @override
  late final GeneratedColumn<String> refId = GeneratedColumn<String>(
    'ref_id',
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
  static const VerificationMeta _removedMeta = const VerificationMeta(
    'removed',
  );
  @override
  late final GeneratedColumn<bool> removed = GeneratedColumn<bool>(
    'removed',
    aliasedName,
    false,
    type: DriftSqlType.bool,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'CHECK ("removed" IN (0, 1))',
    ),
    defaultValue: const Constant(false),
  );
  static const VerificationMeta _labelMeta = const VerificationMeta('label');
  @override
  late final GeneratedColumn<String> label = GeneratedColumn<String>(
    'label',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _detailMeta = const VerificationMeta('detail');
  @override
  late final GeneratedColumn<String> detail = GeneratedColumn<String>(
    'detail',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _facetIdMeta = const VerificationMeta(
    'facetId',
  );
  @override
  late final GeneratedColumn<String> facetId = GeneratedColumn<String>(
    'facet_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _exerciseJsonMeta = const VerificationMeta(
    'exerciseJson',
  );
  @override
  late final GeneratedColumn<String> exerciseJson = GeneratedColumn<String>(
    'exercise_json',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    courseId,
    kind,
    refId,
    at,
    removed,
    label,
    detail,
    facetId,
    exerciseJson,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'bookmarks';
  @override
  VerificationContext validateIntegrity(
    Insertable<BookmarkRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('course_id')) {
      context.handle(
        _courseIdMeta,
        courseId.isAcceptableOrUnknown(data['course_id']!, _courseIdMeta),
      );
    } else if (isInserting) {
      context.missing(_courseIdMeta);
    }
    if (data.containsKey('kind')) {
      context.handle(
        _kindMeta,
        kind.isAcceptableOrUnknown(data['kind']!, _kindMeta),
      );
    } else if (isInserting) {
      context.missing(_kindMeta);
    }
    if (data.containsKey('ref_id')) {
      context.handle(
        _refIdMeta,
        refId.isAcceptableOrUnknown(data['ref_id']!, _refIdMeta),
      );
    } else if (isInserting) {
      context.missing(_refIdMeta);
    }
    if (data.containsKey('at')) {
      context.handle(_atMeta, at.isAcceptableOrUnknown(data['at']!, _atMeta));
    } else if (isInserting) {
      context.missing(_atMeta);
    }
    if (data.containsKey('removed')) {
      context.handle(
        _removedMeta,
        removed.isAcceptableOrUnknown(data['removed']!, _removedMeta),
      );
    }
    if (data.containsKey('label')) {
      context.handle(
        _labelMeta,
        label.isAcceptableOrUnknown(data['label']!, _labelMeta),
      );
    }
    if (data.containsKey('detail')) {
      context.handle(
        _detailMeta,
        detail.isAcceptableOrUnknown(data['detail']!, _detailMeta),
      );
    }
    if (data.containsKey('facet_id')) {
      context.handle(
        _facetIdMeta,
        facetId.isAcceptableOrUnknown(data['facet_id']!, _facetIdMeta),
      );
    }
    if (data.containsKey('exercise_json')) {
      context.handle(
        _exerciseJsonMeta,
        exerciseJson.isAcceptableOrUnknown(
          data['exercise_json']!,
          _exerciseJsonMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {courseId, kind, refId};
  @override
  BookmarkRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return BookmarkRow(
      courseId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}course_id'],
      )!,
      kind: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}kind'],
      )!,
      refId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}ref_id'],
      )!,
      at: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}at'],
      )!,
      removed: attachedDatabase.typeMapping.read(
        DriftSqlType.bool,
        data['${effectivePrefix}removed'],
      )!,
      label: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}label'],
      )!,
      detail: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}detail'],
      ),
      facetId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}facet_id'],
      ),
      exerciseJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}exercise_json'],
      ),
    );
  }

  @override
  $BookmarksTable createAlias(String alias) {
    return $BookmarksTable(attachedDatabase, alias);
  }
}

class BookmarkRow extends DataClass implements Insertable<BookmarkRow> {
  final String courseId;
  final String kind;
  final String refId;
  final int at;
  final bool removed;
  final String label;
  final String? detail;
  final String? facetId;
  final String? exerciseJson;
  const BookmarkRow({
    required this.courseId,
    required this.kind,
    required this.refId,
    required this.at,
    required this.removed,
    required this.label,
    this.detail,
    this.facetId,
    this.exerciseJson,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['course_id'] = Variable<String>(courseId);
    map['kind'] = Variable<String>(kind);
    map['ref_id'] = Variable<String>(refId);
    map['at'] = Variable<int>(at);
    map['removed'] = Variable<bool>(removed);
    map['label'] = Variable<String>(label);
    if (!nullToAbsent || detail != null) {
      map['detail'] = Variable<String>(detail);
    }
    if (!nullToAbsent || facetId != null) {
      map['facet_id'] = Variable<String>(facetId);
    }
    if (!nullToAbsent || exerciseJson != null) {
      map['exercise_json'] = Variable<String>(exerciseJson);
    }
    return map;
  }

  BookmarksCompanion toCompanion(bool nullToAbsent) {
    return BookmarksCompanion(
      courseId: Value(courseId),
      kind: Value(kind),
      refId: Value(refId),
      at: Value(at),
      removed: Value(removed),
      label: Value(label),
      detail: detail == null && nullToAbsent
          ? const Value.absent()
          : Value(detail),
      facetId: facetId == null && nullToAbsent
          ? const Value.absent()
          : Value(facetId),
      exerciseJson: exerciseJson == null && nullToAbsent
          ? const Value.absent()
          : Value(exerciseJson),
    );
  }

  factory BookmarkRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return BookmarkRow(
      courseId: serializer.fromJson<String>(json['courseId']),
      kind: serializer.fromJson<String>(json['kind']),
      refId: serializer.fromJson<String>(json['refId']),
      at: serializer.fromJson<int>(json['at']),
      removed: serializer.fromJson<bool>(json['removed']),
      label: serializer.fromJson<String>(json['label']),
      detail: serializer.fromJson<String?>(json['detail']),
      facetId: serializer.fromJson<String?>(json['facetId']),
      exerciseJson: serializer.fromJson<String?>(json['exerciseJson']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'courseId': serializer.toJson<String>(courseId),
      'kind': serializer.toJson<String>(kind),
      'refId': serializer.toJson<String>(refId),
      'at': serializer.toJson<int>(at),
      'removed': serializer.toJson<bool>(removed),
      'label': serializer.toJson<String>(label),
      'detail': serializer.toJson<String?>(detail),
      'facetId': serializer.toJson<String?>(facetId),
      'exerciseJson': serializer.toJson<String?>(exerciseJson),
    };
  }

  BookmarkRow copyWith({
    String? courseId,
    String? kind,
    String? refId,
    int? at,
    bool? removed,
    String? label,
    Value<String?> detail = const Value.absent(),
    Value<String?> facetId = const Value.absent(),
    Value<String?> exerciseJson = const Value.absent(),
  }) => BookmarkRow(
    courseId: courseId ?? this.courseId,
    kind: kind ?? this.kind,
    refId: refId ?? this.refId,
    at: at ?? this.at,
    removed: removed ?? this.removed,
    label: label ?? this.label,
    detail: detail.present ? detail.value : this.detail,
    facetId: facetId.present ? facetId.value : this.facetId,
    exerciseJson: exerciseJson.present ? exerciseJson.value : this.exerciseJson,
  );
  BookmarkRow copyWithCompanion(BookmarksCompanion data) {
    return BookmarkRow(
      courseId: data.courseId.present ? data.courseId.value : this.courseId,
      kind: data.kind.present ? data.kind.value : this.kind,
      refId: data.refId.present ? data.refId.value : this.refId,
      at: data.at.present ? data.at.value : this.at,
      removed: data.removed.present ? data.removed.value : this.removed,
      label: data.label.present ? data.label.value : this.label,
      detail: data.detail.present ? data.detail.value : this.detail,
      facetId: data.facetId.present ? data.facetId.value : this.facetId,
      exerciseJson: data.exerciseJson.present
          ? data.exerciseJson.value
          : this.exerciseJson,
    );
  }

  @override
  String toString() {
    return (StringBuffer('BookmarkRow(')
          ..write('courseId: $courseId, ')
          ..write('kind: $kind, ')
          ..write('refId: $refId, ')
          ..write('at: $at, ')
          ..write('removed: $removed, ')
          ..write('label: $label, ')
          ..write('detail: $detail, ')
          ..write('facetId: $facetId, ')
          ..write('exerciseJson: $exerciseJson')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    courseId,
    kind,
    refId,
    at,
    removed,
    label,
    detail,
    facetId,
    exerciseJson,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is BookmarkRow &&
          other.courseId == this.courseId &&
          other.kind == this.kind &&
          other.refId == this.refId &&
          other.at == this.at &&
          other.removed == this.removed &&
          other.label == this.label &&
          other.detail == this.detail &&
          other.facetId == this.facetId &&
          other.exerciseJson == this.exerciseJson);
}

class BookmarksCompanion extends UpdateCompanion<BookmarkRow> {
  final Value<String> courseId;
  final Value<String> kind;
  final Value<String> refId;
  final Value<int> at;
  final Value<bool> removed;
  final Value<String> label;
  final Value<String?> detail;
  final Value<String?> facetId;
  final Value<String?> exerciseJson;
  final Value<int> rowid;
  const BookmarksCompanion({
    this.courseId = const Value.absent(),
    this.kind = const Value.absent(),
    this.refId = const Value.absent(),
    this.at = const Value.absent(),
    this.removed = const Value.absent(),
    this.label = const Value.absent(),
    this.detail = const Value.absent(),
    this.facetId = const Value.absent(),
    this.exerciseJson = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  BookmarksCompanion.insert({
    required String courseId,
    required String kind,
    required String refId,
    required int at,
    this.removed = const Value.absent(),
    this.label = const Value.absent(),
    this.detail = const Value.absent(),
    this.facetId = const Value.absent(),
    this.exerciseJson = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : courseId = Value(courseId),
       kind = Value(kind),
       refId = Value(refId),
       at = Value(at);
  static Insertable<BookmarkRow> custom({
    Expression<String>? courseId,
    Expression<String>? kind,
    Expression<String>? refId,
    Expression<int>? at,
    Expression<bool>? removed,
    Expression<String>? label,
    Expression<String>? detail,
    Expression<String>? facetId,
    Expression<String>? exerciseJson,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (courseId != null) 'course_id': courseId,
      if (kind != null) 'kind': kind,
      if (refId != null) 'ref_id': refId,
      if (at != null) 'at': at,
      if (removed != null) 'removed': removed,
      if (label != null) 'label': label,
      if (detail != null) 'detail': detail,
      if (facetId != null) 'facet_id': facetId,
      if (exerciseJson != null) 'exercise_json': exerciseJson,
      if (rowid != null) 'rowid': rowid,
    });
  }

  BookmarksCompanion copyWith({
    Value<String>? courseId,
    Value<String>? kind,
    Value<String>? refId,
    Value<int>? at,
    Value<bool>? removed,
    Value<String>? label,
    Value<String?>? detail,
    Value<String?>? facetId,
    Value<String?>? exerciseJson,
    Value<int>? rowid,
  }) {
    return BookmarksCompanion(
      courseId: courseId ?? this.courseId,
      kind: kind ?? this.kind,
      refId: refId ?? this.refId,
      at: at ?? this.at,
      removed: removed ?? this.removed,
      label: label ?? this.label,
      detail: detail ?? this.detail,
      facetId: facetId ?? this.facetId,
      exerciseJson: exerciseJson ?? this.exerciseJson,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (courseId.present) {
      map['course_id'] = Variable<String>(courseId.value);
    }
    if (kind.present) {
      map['kind'] = Variable<String>(kind.value);
    }
    if (refId.present) {
      map['ref_id'] = Variable<String>(refId.value);
    }
    if (at.present) {
      map['at'] = Variable<int>(at.value);
    }
    if (removed.present) {
      map['removed'] = Variable<bool>(removed.value);
    }
    if (label.present) {
      map['label'] = Variable<String>(label.value);
    }
    if (detail.present) {
      map['detail'] = Variable<String>(detail.value);
    }
    if (facetId.present) {
      map['facet_id'] = Variable<String>(facetId.value);
    }
    if (exerciseJson.present) {
      map['exercise_json'] = Variable<String>(exerciseJson.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('BookmarksCompanion(')
          ..write('courseId: $courseId, ')
          ..write('kind: $kind, ')
          ..write('refId: $refId, ')
          ..write('at: $at, ')
          ..write('removed: $removed, ')
          ..write('label: $label, ')
          ..write('detail: $detail, ')
          ..write('facetId: $facetId, ')
          ..write('exerciseJson: $exerciseJson, ')
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
  late final $AiExplanationsTable aiExplanations = $AiExplanationsTable(this);
  late final $FlagsTable flags = $FlagsTable(this);
  late final $BookmarksTable bookmarks = $BookmarksTable(this);
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
  late final Index flagsCreated = Index(
    'flags_created',
    'CREATE INDEX flags_created ON flags (created_at)',
  );
  late final Index bookmarksCourseAt = Index(
    'bookmarks_course_at',
    'CREATE INDEX bookmarks_course_at ON bookmarks (course_id, at)',
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
    aiExplanations,
    flags,
    bookmarks,
    reviewLogFacetAt,
    reviewLogAt,
    facetStateDue,
    mistakesAt,
    mistakesFacet,
    flagsCreated,
    bookmarksCourseAt,
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
typedef $$AiExplanationsTableCreateCompanionBuilder =
    AiExplanationsCompanion Function({
      required String fingerprint,
      required String given,
      required String lang,
      required String body,
      Value<String?> facetId,
      Value<String?> provider,
      Value<String?> model,
      required int createdAt,
      Value<int> rowid,
    });
typedef $$AiExplanationsTableUpdateCompanionBuilder =
    AiExplanationsCompanion Function({
      Value<String> fingerprint,
      Value<String> given,
      Value<String> lang,
      Value<String> body,
      Value<String?> facetId,
      Value<String?> provider,
      Value<String?> model,
      Value<int> createdAt,
      Value<int> rowid,
    });

class $$AiExplanationsTableFilterComposer
    extends Composer<_$ProgressDb, $AiExplanationsTable> {
  $$AiExplanationsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get fingerprint => $composableBuilder(
    column: $table.fingerprint,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get given => $composableBuilder(
    column: $table.given,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lang => $composableBuilder(
    column: $table.lang,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get body => $composableBuilder(
    column: $table.body,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get facetId => $composableBuilder(
    column: $table.facetId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get provider => $composableBuilder(
    column: $table.provider,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get model => $composableBuilder(
    column: $table.model,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$AiExplanationsTableOrderingComposer
    extends Composer<_$ProgressDb, $AiExplanationsTable> {
  $$AiExplanationsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get fingerprint => $composableBuilder(
    column: $table.fingerprint,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get given => $composableBuilder(
    column: $table.given,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lang => $composableBuilder(
    column: $table.lang,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get body => $composableBuilder(
    column: $table.body,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get facetId => $composableBuilder(
    column: $table.facetId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get provider => $composableBuilder(
    column: $table.provider,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get model => $composableBuilder(
    column: $table.model,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AiExplanationsTableAnnotationComposer
    extends Composer<_$ProgressDb, $AiExplanationsTable> {
  $$AiExplanationsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get fingerprint => $composableBuilder(
    column: $table.fingerprint,
    builder: (column) => column,
  );

  GeneratedColumn<String> get given =>
      $composableBuilder(column: $table.given, builder: (column) => column);

  GeneratedColumn<String> get lang =>
      $composableBuilder(column: $table.lang, builder: (column) => column);

  GeneratedColumn<String> get body =>
      $composableBuilder(column: $table.body, builder: (column) => column);

  GeneratedColumn<String> get facetId =>
      $composableBuilder(column: $table.facetId, builder: (column) => column);

  GeneratedColumn<String> get provider =>
      $composableBuilder(column: $table.provider, builder: (column) => column);

  GeneratedColumn<String> get model =>
      $composableBuilder(column: $table.model, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$AiExplanationsTableTableManager
    extends
        RootTableManager<
          _$ProgressDb,
          $AiExplanationsTable,
          AiExplanationRow,
          $$AiExplanationsTableFilterComposer,
          $$AiExplanationsTableOrderingComposer,
          $$AiExplanationsTableAnnotationComposer,
          $$AiExplanationsTableCreateCompanionBuilder,
          $$AiExplanationsTableUpdateCompanionBuilder,
          (
            AiExplanationRow,
            BaseReferences<
              _$ProgressDb,
              $AiExplanationsTable,
              AiExplanationRow
            >,
          ),
          AiExplanationRow,
          PrefetchHooks Function()
        > {
  $$AiExplanationsTableTableManager(_$ProgressDb db, $AiExplanationsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AiExplanationsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AiExplanationsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AiExplanationsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> fingerprint = const Value.absent(),
                Value<String> given = const Value.absent(),
                Value<String> lang = const Value.absent(),
                Value<String> body = const Value.absent(),
                Value<String?> facetId = const Value.absent(),
                Value<String?> provider = const Value.absent(),
                Value<String?> model = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AiExplanationsCompanion(
                fingerprint: fingerprint,
                given: given,
                lang: lang,
                body: body,
                facetId: facetId,
                provider: provider,
                model: model,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String fingerprint,
                required String given,
                required String lang,
                required String body,
                Value<String?> facetId = const Value.absent(),
                Value<String?> provider = const Value.absent(),
                Value<String?> model = const Value.absent(),
                required int createdAt,
                Value<int> rowid = const Value.absent(),
              }) => AiExplanationsCompanion.insert(
                fingerprint: fingerprint,
                given: given,
                lang: lang,
                body: body,
                facetId: facetId,
                provider: provider,
                model: model,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$AiExplanationsTable, AiExplanationRow>(table),
                  BaseReferences<
                    _$ProgressDb,
                    $AiExplanationsTable,
                    AiExplanationRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$AiExplanationsTableProcessedTableManager =
    ProcessedTableManager<
      _$ProgressDb,
      $AiExplanationsTable,
      AiExplanationRow,
      $$AiExplanationsTableFilterComposer,
      $$AiExplanationsTableOrderingComposer,
      $$AiExplanationsTableAnnotationComposer,
      $$AiExplanationsTableCreateCompanionBuilder,
      $$AiExplanationsTableUpdateCompanionBuilder,
      (
        AiExplanationRow,
        BaseReferences<_$ProgressDb, $AiExplanationsTable, AiExplanationRow>,
      ),
      AiExplanationRow,
      PrefetchHooks Function()
    >;
typedef $$FlagsTableCreateCompanionBuilder = FlagsCompanion Function({
  required String id,
  required int createdAt,
  required String courseId,
  Value<String?> skillId,
  required String facetId,
  required String exerciseType,
  required String exerciseJson,
  required String given,
  required String expected,
  required bool correct,
  required String reason,
  Value<String> comment,
  Value<String?> aiVerdict,
  Value<String?> aiReasoning,
  Value<String?> appVersion,
  Value<String?> packVersion,
  Value<String?> sourceLang,
  Value<int> rowid,
});
typedef $$FlagsTableUpdateCompanionBuilder = FlagsCompanion Function({
  Value<String> id,
  Value<int> createdAt,
  Value<String> courseId,
  Value<String?> skillId,
  Value<String> facetId,
  Value<String> exerciseType,
  Value<String> exerciseJson,
  Value<String> given,
  Value<String> expected,
  Value<bool> correct,
  Value<String> reason,
  Value<String> comment,
  Value<String?> aiVerdict,
  Value<String?> aiReasoning,
  Value<String?> appVersion,
  Value<String?> packVersion,
  Value<String?> sourceLang,
  Value<int> rowid,
});

class $$FlagsTableFilterComposer extends Composer<_$ProgressDb, $FlagsTable> {
  $$FlagsTableFilterComposer({
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

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get courseId => $composableBuilder(
    column: $table.courseId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get skillId => $composableBuilder(
    column: $table.skillId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get facetId => $composableBuilder(
    column: $table.facetId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get exerciseType => $composableBuilder(
    column: $table.exerciseType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get exerciseJson => $composableBuilder(
    column: $table.exerciseJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get given => $composableBuilder(
    column: $table.given,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get expected => $composableBuilder(
    column: $table.expected,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get correct => $composableBuilder(
    column: $table.correct,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get reason => $composableBuilder(
    column: $table.reason,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get comment => $composableBuilder(
    column: $table.comment,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get aiVerdict => $composableBuilder(
    column: $table.aiVerdict,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get aiReasoning => $composableBuilder(
    column: $table.aiReasoning,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get appVersion => $composableBuilder(
    column: $table.appVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get packVersion => $composableBuilder(
    column: $table.packVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourceLang => $composableBuilder(
    column: $table.sourceLang,
    builder: (column) => ColumnFilters(column),
  );
}

class $$FlagsTableOrderingComposer extends Composer<_$ProgressDb, $FlagsTable> {
  $$FlagsTableOrderingComposer({
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

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get courseId => $composableBuilder(
    column: $table.courseId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get skillId => $composableBuilder(
    column: $table.skillId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get facetId => $composableBuilder(
    column: $table.facetId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get exerciseType => $composableBuilder(
    column: $table.exerciseType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get exerciseJson => $composableBuilder(
    column: $table.exerciseJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get given => $composableBuilder(
    column: $table.given,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get expected => $composableBuilder(
    column: $table.expected,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get correct => $composableBuilder(
    column: $table.correct,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get reason => $composableBuilder(
    column: $table.reason,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get comment => $composableBuilder(
    column: $table.comment,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get aiVerdict => $composableBuilder(
    column: $table.aiVerdict,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get aiReasoning => $composableBuilder(
    column: $table.aiReasoning,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get appVersion => $composableBuilder(
    column: $table.appVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get packVersion => $composableBuilder(
    column: $table.packVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourceLang => $composableBuilder(
    column: $table.sourceLang,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$FlagsTableAnnotationComposer
    extends Composer<_$ProgressDb, $FlagsTable> {
  $$FlagsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<String> get courseId =>
      $composableBuilder(column: $table.courseId, builder: (column) => column);

  GeneratedColumn<String> get skillId =>
      $composableBuilder(column: $table.skillId, builder: (column) => column);

  GeneratedColumn<String> get facetId =>
      $composableBuilder(column: $table.facetId, builder: (column) => column);

  GeneratedColumn<String> get exerciseType => $composableBuilder(
    column: $table.exerciseType,
    builder: (column) => column,
  );

  GeneratedColumn<String> get exerciseJson => $composableBuilder(
    column: $table.exerciseJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get given =>
      $composableBuilder(column: $table.given, builder: (column) => column);

  GeneratedColumn<String> get expected =>
      $composableBuilder(column: $table.expected, builder: (column) => column);

  GeneratedColumn<bool> get correct =>
      $composableBuilder(column: $table.correct, builder: (column) => column);

  GeneratedColumn<String> get reason =>
      $composableBuilder(column: $table.reason, builder: (column) => column);

  GeneratedColumn<String> get comment =>
      $composableBuilder(column: $table.comment, builder: (column) => column);

  GeneratedColumn<String> get aiVerdict =>
      $composableBuilder(column: $table.aiVerdict, builder: (column) => column);

  GeneratedColumn<String> get aiReasoning => $composableBuilder(
    column: $table.aiReasoning,
    builder: (column) => column,
  );

  GeneratedColumn<String> get appVersion => $composableBuilder(
    column: $table.appVersion,
    builder: (column) => column,
  );

  GeneratedColumn<String> get packVersion => $composableBuilder(
    column: $table.packVersion,
    builder: (column) => column,
  );

  GeneratedColumn<String> get sourceLang => $composableBuilder(
    column: $table.sourceLang,
    builder: (column) => column,
  );
}

class $$FlagsTableTableManager
    extends
        RootTableManager<
          _$ProgressDb,
          $FlagsTable,
          FlagRow,
          $$FlagsTableFilterComposer,
          $$FlagsTableOrderingComposer,
          $$FlagsTableAnnotationComposer,
          $$FlagsTableCreateCompanionBuilder,
          $$FlagsTableUpdateCompanionBuilder,
          (FlagRow, BaseReferences<_$ProgressDb, $FlagsTable, FlagRow>),
          FlagRow,
          PrefetchHooks Function()
        > {
  $$FlagsTableTableManager(_$ProgressDb db, $FlagsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$FlagsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$FlagsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$FlagsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<String> courseId = const Value.absent(),
                Value<String?> skillId = const Value.absent(),
                Value<String> facetId = const Value.absent(),
                Value<String> exerciseType = const Value.absent(),
                Value<String> exerciseJson = const Value.absent(),
                Value<String> given = const Value.absent(),
                Value<String> expected = const Value.absent(),
                Value<bool> correct = const Value.absent(),
                Value<String> reason = const Value.absent(),
                Value<String> comment = const Value.absent(),
                Value<String?> aiVerdict = const Value.absent(),
                Value<String?> aiReasoning = const Value.absent(),
                Value<String?> appVersion = const Value.absent(),
                Value<String?> packVersion = const Value.absent(),
                Value<String?> sourceLang = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => FlagsCompanion(
                id: id,
                createdAt: createdAt,
                courseId: courseId,
                skillId: skillId,
                facetId: facetId,
                exerciseType: exerciseType,
                exerciseJson: exerciseJson,
                given: given,
                expected: expected,
                correct: correct,
                reason: reason,
                comment: comment,
                aiVerdict: aiVerdict,
                aiReasoning: aiReasoning,
                appVersion: appVersion,
                packVersion: packVersion,
                sourceLang: sourceLang,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required int createdAt,
                required String courseId,
                Value<String?> skillId = const Value.absent(),
                required String facetId,
                required String exerciseType,
                required String exerciseJson,
                required String given,
                required String expected,
                required bool correct,
                required String reason,
                Value<String> comment = const Value.absent(),
                Value<String?> aiVerdict = const Value.absent(),
                Value<String?> aiReasoning = const Value.absent(),
                Value<String?> appVersion = const Value.absent(),
                Value<String?> packVersion = const Value.absent(),
                Value<String?> sourceLang = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => FlagsCompanion.insert(
                id: id,
                createdAt: createdAt,
                courseId: courseId,
                skillId: skillId,
                facetId: facetId,
                exerciseType: exerciseType,
                exerciseJson: exerciseJson,
                given: given,
                expected: expected,
                correct: correct,
                reason: reason,
                comment: comment,
                aiVerdict: aiVerdict,
                aiReasoning: aiReasoning,
                appVersion: appVersion,
                packVersion: packVersion,
                sourceLang: sourceLang,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$FlagsTable, FlagRow>(table),
                  BaseReferences<_$ProgressDb, $FlagsTable, FlagRow>(
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

typedef $$FlagsTableProcessedTableManager =
    ProcessedTableManager<
      _$ProgressDb,
      $FlagsTable,
      FlagRow,
      $$FlagsTableFilterComposer,
      $$FlagsTableOrderingComposer,
      $$FlagsTableAnnotationComposer,
      $$FlagsTableCreateCompanionBuilder,
      $$FlagsTableUpdateCompanionBuilder,
      (FlagRow, BaseReferences<_$ProgressDb, $FlagsTable, FlagRow>),
      FlagRow,
      PrefetchHooks Function()
    >;
typedef $$BookmarksTableCreateCompanionBuilder = BookmarksCompanion Function({
  required String courseId,
  required String kind,
  required String refId,
  required int at,
  Value<bool> removed,
  Value<String> label,
  Value<String?> detail,
  Value<String?> facetId,
  Value<String?> exerciseJson,
  Value<int> rowid,
});
typedef $$BookmarksTableUpdateCompanionBuilder = BookmarksCompanion Function({
  Value<String> courseId,
  Value<String> kind,
  Value<String> refId,
  Value<int> at,
  Value<bool> removed,
  Value<String> label,
  Value<String?> detail,
  Value<String?> facetId,
  Value<String?> exerciseJson,
  Value<int> rowid,
});

class $$BookmarksTableFilterComposer
    extends Composer<_$ProgressDb, $BookmarksTable> {
  $$BookmarksTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get courseId => $composableBuilder(
    column: $table.courseId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get refId => $composableBuilder(
    column: $table.refId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get at => $composableBuilder(
    column: $table.at,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<bool> get removed => $composableBuilder(
    column: $table.removed,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get label => $composableBuilder(
    column: $table.label,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get detail => $composableBuilder(
    column: $table.detail,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get facetId => $composableBuilder(
    column: $table.facetId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get exerciseJson => $composableBuilder(
    column: $table.exerciseJson,
    builder: (column) => ColumnFilters(column),
  );
}

class $$BookmarksTableOrderingComposer
    extends Composer<_$ProgressDb, $BookmarksTable> {
  $$BookmarksTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get courseId => $composableBuilder(
    column: $table.courseId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get kind => $composableBuilder(
    column: $table.kind,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get refId => $composableBuilder(
    column: $table.refId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get at => $composableBuilder(
    column: $table.at,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<bool> get removed => $composableBuilder(
    column: $table.removed,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get label => $composableBuilder(
    column: $table.label,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get detail => $composableBuilder(
    column: $table.detail,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get facetId => $composableBuilder(
    column: $table.facetId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get exerciseJson => $composableBuilder(
    column: $table.exerciseJson,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$BookmarksTableAnnotationComposer
    extends Composer<_$ProgressDb, $BookmarksTable> {
  $$BookmarksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get courseId =>
      $composableBuilder(column: $table.courseId, builder: (column) => column);

  GeneratedColumn<String> get kind =>
      $composableBuilder(column: $table.kind, builder: (column) => column);

  GeneratedColumn<String> get refId =>
      $composableBuilder(column: $table.refId, builder: (column) => column);

  GeneratedColumn<int> get at =>
      $composableBuilder(column: $table.at, builder: (column) => column);

  GeneratedColumn<bool> get removed =>
      $composableBuilder(column: $table.removed, builder: (column) => column);

  GeneratedColumn<String> get label =>
      $composableBuilder(column: $table.label, builder: (column) => column);

  GeneratedColumn<String> get detail =>
      $composableBuilder(column: $table.detail, builder: (column) => column);

  GeneratedColumn<String> get facetId =>
      $composableBuilder(column: $table.facetId, builder: (column) => column);

  GeneratedColumn<String> get exerciseJson => $composableBuilder(
    column: $table.exerciseJson,
    builder: (column) => column,
  );
}

class $$BookmarksTableTableManager
    extends
        RootTableManager<
          _$ProgressDb,
          $BookmarksTable,
          BookmarkRow,
          $$BookmarksTableFilterComposer,
          $$BookmarksTableOrderingComposer,
          $$BookmarksTableAnnotationComposer,
          $$BookmarksTableCreateCompanionBuilder,
          $$BookmarksTableUpdateCompanionBuilder,
          (
            BookmarkRow,
            BaseReferences<_$ProgressDb, $BookmarksTable, BookmarkRow>,
          ),
          BookmarkRow,
          PrefetchHooks Function()
        > {
  $$BookmarksTableTableManager(_$ProgressDb db, $BookmarksTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$BookmarksTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$BookmarksTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$BookmarksTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> courseId = const Value.absent(),
                Value<String> kind = const Value.absent(),
                Value<String> refId = const Value.absent(),
                Value<int> at = const Value.absent(),
                Value<bool> removed = const Value.absent(),
                Value<String> label = const Value.absent(),
                Value<String?> detail = const Value.absent(),
                Value<String?> facetId = const Value.absent(),
                Value<String?> exerciseJson = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => BookmarksCompanion(
                courseId: courseId,
                kind: kind,
                refId: refId,
                at: at,
                removed: removed,
                label: label,
                detail: detail,
                facetId: facetId,
                exerciseJson: exerciseJson,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String courseId,
                required String kind,
                required String refId,
                required int at,
                Value<bool> removed = const Value.absent(),
                Value<String> label = const Value.absent(),
                Value<String?> detail = const Value.absent(),
                Value<String?> facetId = const Value.absent(),
                Value<String?> exerciseJson = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => BookmarksCompanion.insert(
                courseId: courseId,
                kind: kind,
                refId: refId,
                at: at,
                removed: removed,
                label: label,
                detail: detail,
                facetId: facetId,
                exerciseJson: exerciseJson,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$BookmarksTable, BookmarkRow>(table),
                  BaseReferences<_$ProgressDb, $BookmarksTable, BookmarkRow>(
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

typedef $$BookmarksTableProcessedTableManager =
    ProcessedTableManager<
      _$ProgressDb,
      $BookmarksTable,
      BookmarkRow,
      $$BookmarksTableFilterComposer,
      $$BookmarksTableOrderingComposer,
      $$BookmarksTableAnnotationComposer,
      $$BookmarksTableCreateCompanionBuilder,
      $$BookmarksTableUpdateCompanionBuilder,
      (BookmarkRow, BaseReferences<_$ProgressDb, $BookmarksTable, BookmarkRow>),
      BookmarkRow,
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
  $$AiExplanationsTableTableManager get aiExplanations =>
      $$AiExplanationsTableTableManager(_db, _db.aiExplanations);
  $$FlagsTableTableManager get flags =>
      $$FlagsTableTableManager(_db, _db.flags);
  $$BookmarksTableTableManager get bookmarks =>
      $$BookmarksTableTableManager(_db, _db.bookmarks);
}

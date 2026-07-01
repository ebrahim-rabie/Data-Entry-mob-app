import 'package:flutter_application_1/shared.dart';

enum SmartInputKind { text, number, date, boolean, searchableDropdown }
enum ValidationLevel { known, unknownValid, rejected }

class FieldRegistryEntry {
  final String key;
  final String label;
  final String domainType;
  final ColumnType columnType;
  final SmartInputKind widget;
  final String validator;
  final List<String> aliases;
  final String? parentKey;
  final List<String> childKeys;

  const FieldRegistryEntry({
    required this.key,
    required this.label,
    required this.domainType,
    required this.columnType,
    required this.widget,
    required this.validator,
    required this.aliases,
    this.parentKey,
    this.childKeys = const [],
  });
}

class FieldMatch {
  final FieldRegistryEntry entry;
  final double confidence;
  final String reason;

  const FieldMatch({
    required this.entry,
    required this.confidence,
    required this.reason,
  });
}

class ValueValidationResult {
  final ValidationLevel level;
  final String normalizedValue;
  final String? message;

  const ValueValidationResult({
    required this.level,
    required this.normalizedValue,
    this.message,
  });

  bool get canAccept => level != ValidationLevel.rejected;
}

class KnowledgeBase {
  final Map<String, List<String>> valuesByField;
  final Map<String, Map<String, List<String>>> childValuesByParent;
  final Map<String, List<String>> genericValuesByNormalizedColumn;
  final Map<String, String> genericColumnLabels;

  const KnowledgeBase({
    required this.valuesByField,
    required this.childValuesByParent,
    required this.genericValuesByNormalizedColumn,
    required this.genericColumnLabels,
  });

  factory KnowledgeBase.build({
    required List<SchemaColumn> columns,
    required List<Map<String, dynamic>> importedRecords,
    List<ProjectData> firestoreProjects = const [],
    Map<String, List<RecordData>> firestoreRecordsByProject = const {},
  }) {
    final values = <String, Set<String>>{};
    final relations = <String, Map<String, Set<String>>>{};
    final genericValues = <String, Map<String, String>>{};
    final genericLabels = <String, String>{};

    void addValue(String fieldKey, Object? raw) {
      final value = raw?.toString().trim();
      if (value == null || value.isEmpty) return;
      values.putIfAbsent(fieldKey, () => <String>{}).add(value);
    }

    void addGenericValue(String columnName, Object? raw) {
      final fieldName = columnName.toString().trim();
      if (fieldName.isEmpty) return;
      final normalizedColumn = SmartSchemaEngine.normalize(fieldName);
      if (normalizedColumn.isEmpty) return;
      genericLabels.putIfAbsent(normalizedColumn, () => fieldName);
      final value = raw?.toString().trim();
      if (value == null || value.isEmpty) return;
      final normalizedValue = SmartSchemaEngine.normalize(value);
      if (normalizedValue.isEmpty) return;
      genericValues
          .putIfAbsent(normalizedColumn, () => <String, String>{})
          .putIfAbsent(normalizedValue, () => value);
    }

    void addRelation(String childKey, Object? parentRaw, Object? childRaw) {
      final parent = parentRaw?.toString().trim();
      final child = childRaw?.toString().trim();
      if (parent == null || parent.isEmpty || child == null || child.isEmpty) return;
      relations
          .putIfAbsent(childKey, () => <String, Set<String>>{})
          .putIfAbsent(parent, () => <String>{})
          .add(child);
    }

    for (final entry in SeedDictionaries.values.entries) {
      values.putIfAbsent(entry.key, () => <String>{}).addAll(entry.value);
    }
    for (final entry in SeedDictionaries.relationships.entries) {
      for (final parentEntry in entry.value.entries) {
        addRelation(entry.key, parentEntry.key, parentEntry.key);
        relations[entry.key]![parentEntry.key]!.clear();
        relations[entry.key]![parentEntry.key]!.addAll(parentEntry.value);
        values.putIfAbsent(entry.key, () => <String>{}).addAll(parentEntry.value);
      }
    }

    final importedMatches = _recognizeColumns(columns);
    _mergeRows(
      importedRecords,
      importedMatches,
      addValue,
      addRelation,
      addGenericValue,
    );

    for (final project in firestoreProjects) {
      final matches = _recognizeColumns(project.columns);
      final records = firestoreRecordsByProject[project.id] ?? const <RecordData>[];
      _mergeRows(
        records.map((r) => r.data).toList(),
        matches,
        addValue,
        addRelation,
        addGenericValue,
      );
    }

    return KnowledgeBase(
      valuesByField: values.map((key, value) => MapEntry(key, _sorted(value))),
      childValuesByParent: relations.map((childKey, parentMap) {
        return MapEntry(childKey, parentMap.map((parent, childValues) {
          return MapEntry(parent, _sorted(childValues));
        }));
      }),
      genericValuesByNormalizedColumn: genericValues.map((key, value) => MapEntry(key, _sortedValues(value))),
      genericColumnLabels: Map<String, String>.unmodifiable(genericLabels),
    );
  }

  List<String> valuesFor(String? fieldKey, {String? parentValue}) {
    if (fieldKey == null) return const [];
    final parent = parentValue?.trim();
    if (parent != null && parent.isNotEmpty) {
      final related = childValuesByParent[fieldKey]?[parent];
      if (related != null && related.isNotEmpty) return related;
    }
    return valuesByField[fieldKey] ?? const [];
  }

  List<String> genericValuesForColumnName(String columnName) {
    final normalized = SmartSchemaEngine.normalize(columnName);
    if (normalized.isEmpty) return const [];
    final values = <String>{};
    for (final entry in genericValuesByNormalizedColumn.entries) {
      final normalizedKey = entry.key;
      if (normalizedKey == normalized || normalizedKey.contains(normalized) || normalized.contains(normalizedKey)) {
        values.addAll(entry.value);
      }
    }
    final result = values.toList();
    result.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return result;
  }

  bool hasGenericValuesForColumnName(String columnName) {
    return genericValuesForColumnName(columnName).isNotEmpty;
  }

  String? genericColumnLabel(String columnName) {
    final normalized = SmartSchemaEngine.normalize(columnName);
    return genericColumnLabels[normalized];
  }

  static Map<String, String> _recognizeColumns(List<SchemaColumn> columns) {
    final matches = <String, String>{};
    for (final column in columns) {
      final key = column.semanticKey ?? SmartSchemaEngine.matchColumnName(column.name)?.entry.key;
      if (key != null) matches[column.name] = key;
    }
    return matches;
  }

  static void _mergeRows(
    List<Map<String, dynamic>> rows,
    Map<String, String> columnMatches,
    void Function(String fieldKey, Object? raw) addValue,
    void Function(String childKey, Object? parentRaw, Object? childRaw) addRelation,
    void Function(String columnName, Object? raw) addGenericValue,
  ) {
    String? columnFor(String fieldKey) {
      for (final entry in columnMatches.entries) {
        if (entry.value == fieldKey) return entry.key;
      }
      return null;
    }

    final brandColumn = columnFor('brand');
    final modelColumn = columnFor('model');

    for (final row in rows) {
      for (final entry in columnMatches.entries) {
        addValue(entry.value, row[entry.key]);
      }
      for (final entry in row.entries) {
        addGenericValue(entry.key, entry.value);
      }
      if (brandColumn != null && modelColumn != null) {
        addRelation('model', row[brandColumn], row[modelColumn]);
      }
    }
  }

  static List<String> _sorted(Set<String> values) {
    final result = values
        .map((value) => value.trim().replaceAll(RegExp(r'\s+'), ' '))
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList();
    result.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return result;
  }

  static List<String> _sortedValues(Map<String, String> values) {
    final result = values.values
        .map((value) => value.trim().replaceAll(RegExp(r'\s+'), ' '))
        .where((value) => value.isNotEmpty)
        .toSet()
        .toList();
    result.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return result;
  }
}

class FieldRegistry {
  static const Map<String, FieldRegistryEntry> entries = {
    'brand': FieldRegistryEntry(
      key: 'brand',
      label: 'Vehicle Brand',
      domainType: 'vehicle_brand',
      columnType: ColumnType.dropdown,
      widget: SmartInputKind.searchableDropdown,
      validator: 'brandValidator',
      aliases: ['brand', 'manufacturer', 'make', 'vehicle brand', 'vehicle make', 'maker', 'car brand', 'manufactuer'],
      childKeys: ['model'],
    ),
    'model': FieldRegistryEntry(
      key: 'model',
      label: 'Vehicle Model',
      domainType: 'vehicle_model',
      columnType: ColumnType.dropdown,
      widget: SmartInputKind.searchableDropdown,
      validator: 'modelValidator',
      aliases: ['model', 'vehicle model', 'car model', 'variant', 'trim'],
      parentKey: 'brand',
    ),
    'country': FieldRegistryEntry(
      key: 'country',
      label: 'Country',
      domainType: 'country',
      columnType: ColumnType.dropdown,
      widget: SmartInputKind.searchableDropdown,
      validator: 'countryValidator',
      aliases: ['country', 'nation', 'origin country', 'country of origin', 'made in'],
    ),
    'fuel_type': FieldRegistryEntry(
      key: 'fuel_type',
      label: 'Fuel Type',
      domainType: 'fuel_type',
      columnType: ColumnType.dropdown,
      widget: SmartInputKind.searchableDropdown,
      validator: 'fuelValidator',
      aliases: ['fuel', 'fuel type', 'fuel_type', 'engine fuel', 'power source'],
    ),
    'transmission': FieldRegistryEntry(
      key: 'transmission',
      label: 'Transmission',
      domainType: 'transmission',
      columnType: ColumnType.dropdown,
      widget: SmartInputKind.searchableDropdown,
      validator: 'transmissionValidator',
      aliases: ['transmission', 'gearbox', 'gear box', 'trans'],
    ),
    'color': FieldRegistryEntry(
      key: 'color',
      label: 'Color',
      domainType: 'color',
      columnType: ColumnType.dropdown,
      widget: SmartInputKind.searchableDropdown,
      validator: 'colorValidator',
      aliases: ['color', 'colour', 'paint', 'vehicle color', 'exterior color'],
    ),
    'shape': FieldRegistryEntry(
      key: 'shape',
      label: 'Shape',
      domainType: 'shape',
      columnType: ColumnType.dropdown,
      widget: SmartInputKind.searchableDropdown,
      validator: 'shapeValidator',
      aliases: ['shape', 'body shape', 'body style'],
    ),
    'engine': FieldRegistryEntry(
      key: 'engine',
      label: 'Engine',
      domainType: 'engine',
      columnType: ColumnType.dropdown,
      widget: SmartInputKind.searchableDropdown,
      validator: 'engineValidator',
      aliases: ['engine', 'engine size', 'engine capacity', 'motor'],
    ),
    'province': FieldRegistryEntry(
      key: 'province',
      label: 'Province',
      domainType: 'province',
      columnType: ColumnType.dropdown,
      widget: SmartInputKind.searchableDropdown,
      validator: 'provinceValidator',
      aliases: ['province', 'state', 'region', 'area'],
    ),
    'governorate': FieldRegistryEntry(
      key: 'governorate',
      label: 'Governorate',
      domainType: 'governorate',
      columnType: ColumnType.dropdown,
      widget: SmartInputKind.searchableDropdown,
      validator: 'governorateValidator',
      aliases: ['governorate', 'governate', 'gov', 'muhafaza'],
    ),
    'year': FieldRegistryEntry(
      key: 'year',
      label: 'Year',
      domainType: 'year',
      columnType: ColumnType.number,
      widget: SmartInputKind.number,
      validator: 'yearValidator',
      aliases: ['year', 'model year', 'production year', 'manufacture year', 'yr'],
    ),
    'vehicle_type': FieldRegistryEntry(
      key: 'vehicle_type',
      label: 'Vehicle Type',
      domainType: 'vehicle_type',
      columnType: ColumnType.dropdown,
      widget: SmartInputKind.searchableDropdown,
      validator: 'vehicleTypeValidator',
      aliases: ['vehicle type', 'type', 'car type', 'vehicle category', 'category'],
    ),
    'status': FieldRegistryEntry(
      key: 'status',
      label: 'Status',
      domainType: 'status',
      columnType: ColumnType.dropdown,
      widget: SmartInputKind.searchableDropdown,
      validator: 'statusValidator',
      aliases: ['status', 'state', 'condition', 'stage'],
    ),
    'date': FieldRegistryEntry(
      key: 'date',
      label: 'Date',
      domainType: 'date',
      columnType: ColumnType.date,
      widget: SmartInputKind.date,
      validator: 'dateValidator',
      aliases: ['date', 'created date', 'updated date', 'registration date'],
    ),
    'boolean': FieldRegistryEntry(
      key: 'boolean',
      label: 'Yes / No',
      domainType: 'boolean',
      columnType: ColumnType.boolean,
      widget: SmartInputKind.boolean,
      validator: 'booleanValidator',
      aliases: ['active', 'enabled', 'available', 'is active', 'has warranty', 'sold'],
    ),
  };
}

class SeedDictionaries {
  static const Map<String, List<String>> values = {
    'brand': ['Toyota', 'BMW', 'Hyundai', 'Honda', 'Ford', 'Mercedes', 'Kia', 'Nissan'],
    'country': ['Japan', 'Germany', 'USA', 'China', 'South Korea', 'Egypt', 'India'],
    'fuel_type': ['Petrol', 'Diesel', 'Electric', 'Hybrid', 'CNG'],
    'transmission': ['Automatic', 'Manual', 'CVT', 'Semi-Automatic'],
    'color': ['Black', 'White', 'Silver', 'Gray', 'Blue', 'Red'],
    'shape': ['Sedan', 'SUV', 'Hatchback', 'Coupe', 'Pickup', 'Van'],
    'engine': ['1.0L', '1.2L', '1.5L', '1.6L', '2.0L', '2.5L'],
    'province': ['Cairo', 'Giza', 'Alexandria', 'Dakahlia', 'Sharqia'],
    'governorate': ['Cairo', 'Giza', 'Alexandria', 'Luxor', 'Aswan'],
    'vehicle_type': ['Passenger Car', 'Motorcycle', 'Truck', 'Bus', 'Van', 'SUV'],
    'status': ['Active', 'Inactive', 'Pending', 'Approved', 'Rejected', 'Available'],
  };

  static const Map<String, Map<String, List<String>>> relationships = {
    'model': {
      'Toyota': ['Corolla', 'Camry', 'Yaris', 'Hilux', 'Prius'],
      'BMW': ['X5', 'X3', '320i', 'M5'],
      'Mercedes': ['C-Class', 'E-Class', 'S-Class', 'GLC'],
      'Honda': ['Civic', 'Accord', 'CR-V'],
      'Hyundai': ['Elantra', 'Sonata', 'Tucson'],
      'Kia': ['Sportage', 'Cerato', 'Sorento'],
    },
  };
}

class SmartSchemaEngine {
  static FieldMatch? matchColumnName(String input) {
    final value = input.trim();
    if (value.isEmpty) return null;
    final normalized = normalize(value);
    FieldMatch? best;

    for (final entry in FieldRegistry.entries.values) {
      final names = [entry.key, entry.label, ...entry.aliases];
      for (final alias in names) {
        final aliasNormalized = normalize(alias);
        double score = 0;
        String reason = 'Similar to ${entry.label}';
        if (normalized == aliasNormalized) {
          score = 1;
          reason = 'Exact match';
        } else if (aliasNormalized.contains(normalized) || normalized.contains(aliasNormalized)) {
          score = 0.88;
          reason = 'Name contains ${entry.label}';
        } else {
          final distance = _levenshtein(normalized, aliasNormalized);
          final longest = normalized.length > aliasNormalized.length ? normalized.length : aliasNormalized.length;
          score = longest == 0 ? 0 : 1 - (distance / longest);
        }
        if (score >= 0.72 && (best == null || score > best.confidence)) {
          best = FieldMatch(entry: entry, confidence: score, reason: reason);
        }
      }
    }
    return best;
  }

  static SchemaColumn enrichColumn(SchemaColumn column, KnowledgeBase knowledgeBase) {
    final match = matchColumnName(column.name);
    if (match != null) {
      final entry = match.entry;
      return column.copyWith(
        type: entry.columnType,
        semanticKey: entry.key,
        parentKey: entry.parentKey,
        dropdownOptions: entry.columnType == ColumnType.dropdown
            ? _mergeOptions(knowledgeBase.valuesFor(entry.key), column.dropdownOptions)
            : const [],
      );
    }

    final genericValues = knowledgeBase.genericValuesForColumnName(column.name);
    final inferred = genericValues.isNotEmpty || column.dropdownOptions.isNotEmpty
        ? ColumnType.dropdown
        : inferColumnType(column.name);
    return column.copyWith(
      type: inferred,
      semanticKey: null,
      parentKey: null,
      dropdownOptions: inferred == ColumnType.dropdown ? _mergeOptions(genericValues, column.dropdownOptions) : const [],
    );
  }

  static List<String> _mergeOptions(List<String> first, List<String> second) {
    final values = <String, String>{};
    for (final option in [...first, ...second]) {
      final trimmed = option.trim();
      if (trimmed.isNotEmpty) values[normalize(trimmed)] = trimmed;
    }
    final merged = values.values.toList();
    merged.sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
    return merged;
  }
  static ColumnType inferColumnType(String input) {
    final n = normalize(input);
    if (n.contains('date') || n.contains('time') || n.contains('dob')) return ColumnType.date;
    if (n.contains('year') || n.contains('price') || n.contains('amount') || n.contains('qty') || n.contains('count') || n.contains('phone') || n.contains('mobile')) return ColumnType.number;
    if (n.startsWith('is') || n.startsWith('has') || n.contains('active') || n.contains('enabled')) return ColumnType.boolean;
    if (n.contains('type') || n.contains('status') || n.contains('category')) return ColumnType.dropdown;
    return ColumnType.text;
  }

  static ValueValidationResult validateValue({
    required String rawValue,
    required SchemaColumn column,
    required KnowledgeBase knowledgeBase,
    String? parentValue,
  }) {
    final fieldKey = column.semanticKey;
    final cleaned = rawValue.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (cleaned.isEmpty) {
      return const ValueValidationResult(
        level: ValidationLevel.rejected,
        normalizedValue: '',
        message: 'Enter a value first.',
      );
    }
    if (RegExp(r'[\u0600-\u06FF]').hasMatch(cleaned)) {
      return ValueValidationResult(
        level: ValidationLevel.rejected,
        normalizedValue: cleaned,
        message: '${column.name} cannot contain Arabic characters.',
      );
    }
    if (!RegExp(r"^[A-Za-z0-9 .&'/-]+$").hasMatch(cleaned)) {
      return ValueValidationResult(
        level: ValidationLevel.rejected,
        normalizedValue: cleaned,
        message: '${column.name} contains unsupported characters.',
      );
    }
    if (RegExp(r'(.)\1{4,}').hasMatch(cleaned.toLowerCase())) {
      return ValueValidationResult(
        level: ValidationLevel.rejected,
        normalizedValue: cleaned,
        message: '${column.name} looks misspelled.',
      );
    }

    final known = knowledgeBase.valuesFor(fieldKey, parentValue: parentValue);
    final exists = known.any((value) => normalize(value) == normalize(cleaned));
    if (exists) {
      return ValueValidationResult(level: ValidationLevel.known, normalizedValue: cleaned);
    }
    return ValueValidationResult(
      level: ValidationLevel.unknownValid,
      normalizedValue: cleaned,
      message: 'No existing value found. Add "$cleaned" as a new ${column.name}?',
    );
  }

  static List<String> rankedOptions(List<String> options, String query) {
    final q = normalize(query);
    final ranked = [...options];
    if (q.isEmpty) return ranked;
    ranked.sort((a, b) {
      final an = normalize(a);
      final bn = normalize(b);
      final aScore = _rankScore(an, q);
      final bScore = _rankScore(bn, q);
      final scoreCompare = bScore.compareTo(aScore);
      if (scoreCompare != 0) return scoreCompare;
      return a.toLowerCase().compareTo(b.toLowerCase());
    });
    return ranked;
  }

  static int _rankScore(String option, String query) {
    if (option == query) return 100;
    if (option.startsWith(query)) return 80;
    if (option.contains(query)) return 60;
    final distance = _levenshtein(option, query);
    return 40 - distance;
  }

  static String normalize(String value) {
    return value
        .toLowerCase()
        .replaceAll('&', 'and')
        .replaceAll(RegExp(r'[_\-\s]+'), '')
        .replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  static int _levenshtein(String a, String b) {
    if (a == b) return 0;
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;
    final previous = List<int>.generate(b.length + 1, (i) => i);
    final current = List<int>.filled(b.length + 1, 0);
    for (var i = 0; i < a.length; i++) {
      current[0] = i + 1;
      for (var j = 0; j < b.length; j++) {
        final cost = a.codeUnitAt(i) == b.codeUnitAt(j) ? 0 : 1;
        final insert = current[j] + 1;
        final delete = previous[j + 1] + 1;
        final replace = previous[j] + cost;
        current[j + 1] = insert < delete
            ? (insert < replace ? insert : replace)
            : (delete < replace ? delete : replace);
      }
      for (var j = 0; j < previous.length; j++) {
        previous[j] = current[j];
      }
    }
    return previous[b.length];
  }
}

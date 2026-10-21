import 'package:flutter/material.dart';

import '../../core/core.dart';

/// Maps `skill.icon` keys from `course.yaml` to Material icons. Unknown keys fall
/// back to a per-kind default, so packs can use new keys without an app update.
const Map<String, IconData> kSkillIcons = {
  'wave': Icons.waving_hand_outlined,
  'greetings': Icons.waving_hand_outlined,
  'hello': Icons.waving_hand_outlined,
  'food': Icons.restaurant_outlined,
  'drink': Icons.local_cafe_outlined,
  'family': Icons.family_restroom,
  'people': Icons.people_outline,
  'person': Icons.person_outline,
  'home': Icons.home_outlined,
  'house': Icons.home_outlined,
  'city': Icons.location_city_outlined,
  'travel': Icons.flight_outlined,
  'time': Icons.schedule,
  'clock': Icons.schedule,
  'calendar': Icons.calendar_today_outlined,
  'number': Icons.pin_outlined,
  'numbers': Icons.pin_outlined,
  'color': Icons.palette_outlined,
  'colors': Icons.palette_outlined,
  'animal': Icons.pets_outlined,
  'animals': Icons.pets_outlined,
  'work': Icons.work_outline,
  'school': Icons.school_outlined,
  'body': Icons.accessibility_new,
  'clothes': Icons.checkroom_outlined,
  'weather': Icons.wb_sunny_outlined,
  'nature': Icons.park_outlined,
  'shopping': Icons.shopping_bag_outlined,
  'question': Icons.help_outline,
  'search': Icons.search,
  'investigation': Icons.search,
  'verb': Icons.bolt_outlined,
  'verbs': Icons.bolt_outlined,
  'conjugation': Icons.bolt_outlined,
  'past': Icons.history,
  'future': Icons.update,
  'article': Icons.text_fields,
  'articles': Icons.text_fields,
  'grammar': Icons.menu_book_outlined,
  'book': Icons.menu_book_outlined,
  'star': Icons.star_outline,
  'chat': Icons.chat_bubble_outline,
  // themed topics (the topic restructure, docs/topic-split.md)
  'health': Icons.medical_services_outlined,
  'heart': Icons.favorite_border,
  'music': Icons.music_note_outlined,
  'money': Icons.payments_outlined,
  'society': Icons.account_balance_outlined,
};

IconData skillIcon(Skill skill) =>
    kSkillIcons[skill.icon] ?? (skill.kind == SkillKind.grammar ? Icons.menu_book_outlined : Icons.translate);

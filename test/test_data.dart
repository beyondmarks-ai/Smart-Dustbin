import 'package:flutter/material.dart';

import 'package:smart_dustbin/dashboard_data.dart';

const testWasteEntries = <WasteEntry>[
  WasteEntry(
    name: 'Plastic Bottle',
    classification: '85% Recyclable',
    count: 12,
    asset: 'assets/images/plastic_bottle.png',
    accent: Color(0xFF2DC65D),
    capturedAt: '2026-07-25T09:15:00Z',
  ),
  WasteEntry(
    name: 'Paper',
    classification: 'Recyclable',
    count: 8,
    asset: 'assets/images/paper.png',
    accent: Color(0xFF2DC65D),
    capturedAt: '2026-07-26T10:30:00Z',
  ),
  WasteEntry(
    name: 'Food Waste',
    classification: 'Organic',
    count: 6,
    asset: 'assets/images/food_waste.png',
    accent: Color(0xFF34C96B),
    capturedAt: '2026-07-27T13:45:00Z',
  ),
  WasteEntry(
    name: 'Chip Packet',
    classification: 'Non-Recyclable',
    count: 4,
    asset: 'assets/images/chip_packet.png',
    accent: Color(0xFFFF4D4D),
    capturedAt: '2026-07-28T15:10:00Z',
  ),
  WasteEntry(
    name: 'Aluminium Foil',
    classification: 'Recyclable',
    count: 3,
    asset: 'assets/images/aluminium_foil.png',
    accent: Color(0xFF2DC65D),
    capturedAt: '2026-07-29T17:25:00Z',
  ),
];

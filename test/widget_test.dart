import 'package:flutter_test/flutter_test.dart';
import 'package:hyperpik_rider/core/models.dart';

void main() {
  test('a trip offer reads its fee, route and cash to collect', () {
    final t = Trip.fromJson({
      'id': 'd1',
      'status': 'offered',
      'fee': 43,
      'distanceKm': 5.0,
      'expiresAt': '2026-10-14T10:00:00Z',
      'order': {
        'number': 'HP1',
        'cod': true,
        'collect': 191,
        'shopName': 'Tumyum Kitchen',
        'customerName': 'Jay',
        'dropAddress': 'Home, Hyderabad',
        'items': [
          {'name': 'Apricot Delight', 'quantity': 2}
        ],
      },
    });
    expect(t.fee, 43);
    expect(t.cod, isTrue);
    expect(t.collect, 191);
    expect(t.items.single.quantity, 2);
    expect(t.distanceKm, 5.0);
  });

  test('only an approved rider can work', () {
    final r = Rider.fromJson({'id': 'r', 'name': 'A', 'phone': '9', 'vehicleType': 'bike', 'status': 'applied'});
    expect(r.approved, isFalse);
    expect(Rider.fromJson({'id': 'r', 'name': 'A', 'phone': '9', 'vehicleType': 'bike', 'status': 'approved'}).approved, isTrue);
  });

  test('the application state reports which documents are on file', () {
    final me = Me.fromJson({
      'rider': {'id': 'r', 'name': 'A', 'phone': '9', 'vehicleType': 'bike', 'status': 'applied'},
      'documents': [
        {'kind': 'photo', 'status': 'pending'}
      ],
      'required': ['photo', 'license', 'aadhaar'],
    });
    expect(me.documents.single.kind, 'photo');
    expect(me.required.length, 3);
  });

  test('earnings add up what the server sends', () {
    final e = Earnings.fromJson({
      'today': 43,
      'week': 120,
      'month': 400,
      'total': 900,
      'trips': 20,
      'recent': [
        {'amount': 43, 'kind': 'delivery', 'at': '2026-10-14T09:00:00Z', 'order': 'HP1'}
      ],
    });
    expect(e.total, 900);
    expect(e.recent.single.order, 'HP1');
  });
}

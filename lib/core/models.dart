num _n(Object? v) => v is num ? v : (num.tryParse('$v') ?? 0);
String? _s(Object? v) => v == null ? null : '$v';

class Rider {
  Rider({
    required this.id,
    required this.name,
    required this.phone,
    required this.vehicleType,
    required this.status,
    this.city,
    this.vehicleNumber,
    this.licenseNumber,
    this.rejectionReason,
    this.online = false,
    this.ownerType = 'platform',
    this.totalDeliveries = 0,
  });

  final String id;
  final String name;
  final String phone;
  final String vehicleType;
  final String status;
  final String? city;
  final String? vehicleNumber;
  final String? licenseNumber;
  final String? rejectionReason;
  final bool online;
  final String ownerType;
  final int totalDeliveries;

  bool get approved => status == 'approved';

  factory Rider.fromJson(Map<String, dynamic> j) => Rider(
        id: '${j['id']}',
        name: '${j['name']}',
        phone: '${j['phone']}',
        vehicleType: '${j['vehicleType']}',
        status: '${j['status']}',
        city: _s(j['city']),
        vehicleNumber: _s(j['vehicleNumber']),
        licenseNumber: _s(j['licenseNumber']),
        rejectionReason: _s(j['rejectionReason']),
        online: j['online'] == true,
        ownerType: '${j['ownerType'] ?? 'platform'}',
        totalDeliveries: _n(j['totalDeliveries']).toInt(),
      );
}

class DocStatus {
  DocStatus({required this.kind, required this.status, this.note});
  final String kind;
  final String status;
  final String? note;
}

class Me {
  Me({this.rider, this.documents = const [], this.required = const [], this.activeTripId});
  final Rider? rider;
  final List<DocStatus> documents;
  final List<String> required;
  final String? activeTripId;

  factory Me.fromJson(Map<String, dynamic> j) => Me(
        rider: j['rider'] == null ? null : Rider.fromJson(Map<String, dynamic>.from(j['rider'] as Map)),
        documents: ((j['documents'] as List?) ?? const [])
            .map((d) => DocStatus(kind: '${(d as Map)['kind']}', status: '${d['status']}', note: _s(d['note'])))
            .toList(),
        required: ((j['required'] as List?) ?? const []).map((e) => '$e').toList(),
        activeTripId: _s(j['activeTripId']),
      );
}

class TripItem {
  TripItem({required this.name, required this.quantity});
  final String name;
  final int quantity;
}

class Trip {
  Trip({
    required this.id,
    required this.status,
    required this.fee,
    required this.orderNumber,
    required this.shopName,
    required this.items,
    this.distanceKm,
    this.expiresAt,
    this.cod = false,
    this.collect = 0,
    this.shopPhone,
    this.shopAddress,
    this.shopLat,
    this.shopLng,
    this.customerName,
    this.customerPhone,
    this.dropAddress,
    this.dropLat,
    this.dropLng,
    this.note,
  });

  final String id;
  final String status;
  final num fee;
  final double? distanceKm;
  final DateTime? expiresAt;
  final String orderNumber;
  final bool cod;
  final num collect;
  final String shopName;
  final String? shopPhone;
  final String? shopAddress;
  final double? shopLat;
  final double? shopLng;
  final String? customerName;
  final String? customerPhone;
  final String? dropAddress;
  final double? dropLat;
  final double? dropLng;
  final String? note;
  final List<TripItem> items;

  factory Trip.fromJson(Map<String, dynamic> j) {
    final o = Map<String, dynamic>.from(j['order'] as Map);
    return Trip(
      id: '${j['id']}',
      status: '${j['status']}',
      fee: _n(j['fee']),
      distanceKm: j['distanceKm'] == null ? null : _n(j['distanceKm']).toDouble(),
      expiresAt: j['expiresAt'] == null ? null : DateTime.tryParse('${j['expiresAt']}')?.toLocal(),
      orderNumber: '${o['number']}',
      cod: o['cod'] == true,
      collect: _n(o['collect']),
      shopName: '${o['shopName']}',
      shopPhone: _s(o['shopPhone']),
      shopAddress: _s(o['shopAddress']),
      shopLat: o['shopLat'] == null ? null : _n(o['shopLat']).toDouble(),
      shopLng: o['shopLng'] == null ? null : _n(o['shopLng']).toDouble(),
      customerName: _s(o['customerName']),
      customerPhone: _s(o['customerPhone']),
      dropAddress: _s(o['dropAddress']),
      dropLat: o['dropLat'] == null ? null : _n(o['dropLat']).toDouble(),
      dropLng: o['dropLng'] == null ? null : _n(o['dropLng']).toDouble(),
      note: _s(o['note']),
      items: ((o['items'] as List?) ?? const []).map((i) => TripItem(name: '${(i as Map)['name']}', quantity: _n(i['quantity']).toInt())).toList(),
    );
  }
}

class Earning {
  Earning({required this.amount, required this.kind, required this.at, this.order, this.paidAt});
  final num amount;
  final String kind;
  final DateTime at;
  final String? order;
  /// When Hyperpik paid this earning out, or null while it is still owed.
  final DateTime? paidAt;
}

/// One bank transfer Hyperpik made to the rider.
class Payout {
  Payout({required this.amount, required this.reference, required this.at});
  final num amount;
  final String reference;
  final DateTime at;
}

/// The rider's bank account for payouts, with all but the last four digits hidden.
class BankAccount {
  BankAccount({required this.holderName, required this.last4, required this.ifsc});
  final String holderName;
  final String last4;
  final String ifsc;
}

class Earnings {
  Earnings({required this.today, required this.week, required this.month, required this.total, required this.trips, required this.recent, this.note, this.owed = 0, this.paid = 0, this.hasBank = true, this.hyperpikPays = true});
  final num today;
  final num week;
  final num month;
  final num total;
  final int trips;
  final List<Earning> recent;
  final String? note;
  /// Earned and not yet paid out, and paid out so far.
  final num owed;
  final num paid;
  /// Whether a bank account is on file for payouts.
  final bool hasBank;
  /// False for a shop's own rider: the shop pays them directly, so Hyperpik shows no owed, paid or payouts.
  final bool hyperpikPays;

  factory Earnings.fromJson(Map<String, dynamic> j) => Earnings(
        today: _n(j['today']),
        week: _n(j['week']),
        month: _n(j['month']),
        total: _n(j['total']),
        trips: _n(j['trips']).toInt(),
        note: _s(j['payoutNote']),
        owed: _n(j['owed']),
        paid: _n(j['paid']),
        hasBank: j['hasBank'] != false,
        hyperpikPays: j['owed'] != null,
        recent: ((j['recent'] as List?) ?? const [])
            .map((e) => Earning(amount: _n((e as Map)['amount']), kind: '${e['kind']}', at: DateTime.tryParse('${e['at']}')?.toLocal() ?? DateTime.now(), order: _s(e['order']), paidAt: e['paidAt'] == null ? null : DateTime.tryParse('${e['paidAt']}')?.toLocal()))
            .toList(),
      );
}

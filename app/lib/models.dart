/// API data classes. Field names mirror the backend JSON.
library;

int? _int(dynamic v) => v == null ? null : (v as num).round();
double? _dbl(dynamic v) => v == null ? null : (v as num).toDouble();

class AppUser {
  final String id;
  final String? phone, name, email;
  AppUser({required this.id, this.phone, this.name, this.email});

  factory AppUser.fromJson(Map<String, dynamic> j) =>
      AppUser(id: j['id'], phone: j['phone'], name: j['name'], email: j['email']);
  Map<String, dynamic> toJson() => {'id': id, 'phone': phone, 'name': name, 'email': email};

  String get displayName => (name?.isNotEmpty ?? false) ? name! : (phone ?? 'Tarajuu user');
  /// First letter of the name for avatars; 'T' when there's no name (e.g. "+91…").
  String get initial {
    final m = RegExp(r'[A-Za-zऀ-ॿ]').firstMatch(name ?? '');
    return m == null ? 'T' : m.group(0)!.toUpperCase();
  }
  String get contact {
    final p = phone;
    if (p != null && p.startsWith('+91') && p.length == 13) return '+91 ${p.substring(3, 8)} ${p.substring(8)}';
    return p ?? email ?? '';
  }
}

class Offer {
  final String source; // amazon | flipkart
  final int price;
  final int? mrp;
  final String? url;
  Offer({required this.source, required this.price, this.mrp, this.url});
  factory Offer.fromJson(Map<String, dynamic> j) =>
      Offer(source: j['source'], price: _int(j['price'])!, mrp: _int(j['mrp']), url: j['url']);
}

class Badge {
  final String text, type; // type: off | new | hot
  Badge(this.text, this.type);
}

class Product {
  final String id, title;
  final String? brand, category, image;
  final String emoji;
  final double? rating;
  final int? reviews, bestPrice, compareAtPrice;
  final int offPercent;
  final Badge? badge;
  final List<Offer> offers;
  final List<String> images;

  Product({
    required this.id,
    required this.title,
    this.brand,
    this.category,
    this.image,
    this.emoji = '🛍️',
    this.rating,
    this.reviews,
    this.bestPrice,
    this.compareAtPrice,
    this.offPercent = 0,
    this.badge,
    this.offers = const [],
    this.images = const [],
  });

  factory Product.fromJson(Map<String, dynamic> j) => Product(
        id: j['id'],
        title: j['title'],
        brand: j['brand'],
        category: j['category'],
        image: j['image'],
        emoji: j['emoji'] ?? '🛍️',
        rating: _dbl(j['rating']),
        reviews: _int(j['reviews']),
        bestPrice: _int(j['bestPrice']),
        compareAtPrice: _int(j['compareAtPrice']),
        offPercent: _int(j['offPercent']) ?? 0,
        badge: j['badge'] == null ? null : Badge(j['badge']['text'], j['badge']['type']),
        offers: [for (final o in (j['offers'] as List? ?? [])) Offer.fromJson(o)],
        images: [for (final i in (j['images'] as List? ?? [])) i as String],
      );

  bool get onAmazon => offers.any((o) => o.source == 'amazon');
  bool get onFlipkart => offers.any((o) => o.source == 'flipkart');
  Offer? offer(String source) => offers.where((o) => o.source == source).firstOrNull;
}

class Seller {
  final String source, name, logo;
  final int price;
  final int? mrp;
  final String? url, delivery;
  final bool verified, best;
  Seller.fromJson(Map<String, dynamic> j)
      : source = j['source'],
        name = j['name'],
        logo = j['logo'],
        price = _int(j['price'])!,
        mrp = _int(j['mrp']),
        url = j['url'],
        delivery = j['delivery'],
        verified = j['verified'] ?? false,
        best = j['best'] ?? false;
}

class ProductDetail {
  final Product product;
  final List<Seller> sellers;
  bool favourite;
  ProductDetail(this.product, this.sellers, this.favourite);
  factory ProductDetail.fromJson(Map<String, dynamic> j) => ProductDetail(
        Product.fromJson(j),
        [for (final s in (j['sellers'] as List? ?? [])) Seller.fromJson(s)],
        j['favourite'] ?? false,
      );
}

class SearchResult {
  final String status; // pending | done
  final List<Product> results;
  final Map<String, dynamic> sources;
  SearchResult(this.status, this.results, this.sources);
  factory SearchResult.fromJson(Map<String, dynamic> j) => SearchResult(
        j['status'] ?? 'done',
        [for (final p in (j['results'] as List? ?? [])) Product.fromJson(p)],
        Map<String, dynamic>.from(j['sources'] ?? {}),
      );
  bool get done => status == 'done';
}

class Place {
  final String name, subtitle;
  final double lat, lon;
  Place({required this.name, this.subtitle = '', required this.lat, required this.lon});
  factory Place.fromJson(Map<String, dynamic> j) =>
      Place(name: j['name'], subtitle: j['subtitle'] ?? '', lat: _dbl(j['lat'])!, lon: _dbl(j['lon'])!);
  Map<String, dynamic> toJson() => {'name': name, 'lat': lat, 'lon': lon};
  String get label => subtitle.isEmpty ? name : '$name, $subtitle';
}

class Fare {
  final String provider, product, deeplink;
  final String? productId, fareId;
  final bool bookable; // true → can be booked through the API (Uber Guest Rides)
  final int price, priceLow, priceHigh, durationMin, pickupEtaMin;
  final double distanceKm;
  final bool estimated;
  Fare.fromJson(Map<String, dynamic> j)
      : provider = j['provider'],
        product = j['product'],
        deeplink = j['deeplink'],
        price = _int(j['price'])!,
        priceLow = _int(j['priceLow'])!,
        priceHigh = _int(j['priceHigh'])!,
        durationMin = _int(j['durationMin'])!,
        pickupEtaMin = _int(j['pickupEtaMin'])!,
        distanceKm = _dbl(j['distanceKm'])!,
        estimated = j['estimated'] ?? true,
        productId = j['productId'],
        fareId = j['fareId'],
        bookable = j['bookable'] ?? false;

  String get providerName => const {'uber': 'Uber', 'rapido': 'Rapido', 'ola': 'Ola'}[provider] ?? provider;
  String get logo => const {'uber': 'UBER', 'rapido': 'RPD', 'ola': 'OLA'}[provider] ?? provider.toUpperCase();
  String get priceText => priceHigh > priceLow ? '₹$priceLow–$priceHigh' : '₹$price';
}

class RideEstimate {
  final String type, label, emoji, uberStatus;
  final double distanceKm;
  final int durationMin, savings;
  final List<Fare> fares;
  final List<List<double>> route; // [lon, lat] pairs
  RideEstimate.fromJson(Map<String, dynamic> j)
      : type = j['type'],
        label = j['label'],
        emoji = j['emoji'],
        uberStatus = j['uberStatus'] ?? 'disabled',
        distanceKm = _dbl(j['distanceKm'])!,
        durationMin = _int(j['durationMin'])!,
        savings = _int(j['savings']) ?? 0,
        fares = [for (final f in j['fares'] as List) Fare.fromJson(f)],
        route = [
          for (final p in (j['route'] as List? ?? [])) [(p[0] as num).toDouble(), (p[1] as num).toDouble()]
        ];
}

class RecentItem {
  final String kind, query, title;
  final String? subtitle;
  RecentItem.fromJson(Map<String, dynamic> j)
      : kind = j['kind'],
        query = j['query'],
        title = j['title'],
        subtitle = j['subtitle'];
}

/// Live state of a ride booked through the API.
class TripStatus {
  final String bookingId, status;
  final bool terminal;
  final String? product, driverName, driverPhone, vehicle, plate, pin, trackingUrl;
  final double? driverRating, driverLat, driverLon, driverBearing;
  final int? pickupEtaMin, dropoffEtaMin, fare;
  final Place pickup, dropoff;

  TripStatus.fromJson(Map<String, dynamic> j)
      : bookingId = j['bookingId'],
        status = j['status'] ?? 'processing',
        terminal = j['terminal'] ?? false,
        product = j['product'],
        driverName = j['driver']?['name'],
        driverPhone = j['driver']?['phone'],
        driverRating = _dbl(j['driver']?['rating']),
        vehicle = j['vehicle'] == null
            ? null
            : [j['vehicle']['color'], j['vehicle']['make'], j['vehicle']['model']].whereType<String>().join(' '),
        plate = j['vehicle']?['plate'],
        pin = j['pin'],
        trackingUrl = j['trackingUrl'],
        driverLat = _dbl(j['driverLocation']?['lat']),
        driverLon = _dbl(j['driverLocation']?['lon']),
        driverBearing = _dbl(j['driverLocation']?['bearing']),
        pickupEtaMin = _int(j['pickupEtaMin']),
        dropoffEtaMin = _int(j['dropoffEtaMin']),
        fare = _int(j['fare']),
        pickup = Place(name: j['pickup']['name'] ?? '', lat: _dbl(j['pickup']['lat'])!, lon: _dbl(j['pickup']['lon'])!),
        dropoff = Place(name: j['dropoff']['name'] ?? '', lat: _dbl(j['dropoff']['lat'])!, lon: _dbl(j['dropoff']['lon'])!);

  /// Headline for the tracking sheet.
  String get headline => switch (status) {
        'processing' => 'Finding your driver…',
        'accepted' => pickupEtaMin != null ? 'Pick-up in $pickupEtaMin min' : 'Driver on the way',
        'arriving' => 'Driver arriving now!',
        'in_progress' => dropoffEtaMin != null ? 'On trip · $dropoffEtaMin min to drop' : 'On trip',
        'completed' => 'Trip completed 🎉',
        'no_drivers_available' => 'No drivers available',
        'driver_canceled' => 'Driver cancelled',
        'rider_canceled' => 'Ride cancelled',
        'scheduled' => 'Ride scheduled',
        _ => status.replaceAll('_', ' '),
      };
}

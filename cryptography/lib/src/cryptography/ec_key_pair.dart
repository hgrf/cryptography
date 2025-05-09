// Copyright 2019-2020 Gohilla.
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography_plus/cryptography_plus.dart';
import 'package:cryptography_plus/helpers.dart';

import '../_internal/hex.dart';
import '_cupertino_der.dart';

/// An opaque reference to _P-256_ / _P-384_ / _P-521_ key pair.
///
/// The private key bytes of the key may not be in the memory. The private key
/// bytes may not even be extractable. If the private key is in memory, it's an
/// instance of [EcKeyPairData].
///
/// The public key is always [EcPublicKey].
///
/// This class is used with algorithms such as [Ecdh.p256] and [Ecdsa.p256].
///
/// There are many formats for storing elliptic curve key parameters.
/// If you are encoding/decoding JWK (JSON Web Key) format, use
/// [package:jwk](https://pub.dev/packages/jwk).
abstract class EcKeyPair extends KeyPair {
  /// Constructor for subclasses.
  EcKeyPair.constructor();

  @override
  Future<EcKeyPairData> extract();

  @override
  Future<EcPublicKey> extractPublicKey();
}

/// _P-256_ / _P-384_ / _P-521_ key pair.
///
/// There are many formats for storing elliptic curve key parameters.
/// If you are encoding/decoding JWK (JSON Web Key) format, use
/// [package:jwk](https://pub.dev/packages/jwk).
///
/// ## Related classes
///   * [EcKeyPair]
///   * [EcPublicKey]
///
/// ## Algorithms that use this class
///   * [Ecdh]
///   * [Ecdsa]
///
class EcKeyPairData extends KeyPairData implements EcKeyPair {
  final SensitiveBytes _d;

  /// Elliptic curve public key component `x` (not confidential).
  final List<int> x;

  /// Elliptic curve public key component `y` (not confidential).
  final List<int> y;

  @override
  final EcPublicKey publicKey;

  /// Debugging label.
  final String? debugLabel;

  /// Constructs a private key with elliptic curve parameters.
  EcKeyPairData({
    required List<int> d,
    required this.x,
    required this.y,
    required KeyPairType type,
    this.debugLabel,
  })  : _d = SensitiveBytes(d),
        publicKey = EcPublicKey(
          x: x,
          y: y,
          type: type,
        ),
        super(type: type);

  /// Elliptic curve private key component `d` (confidential).
  List<int> get d {
    final d = _d;
    if (d.hasBeenDestroyed) {
      throw UnsupportedError('Private key has been destroyed: $this');
    }
    return d;
  }

  @override
  int get hashCode =>
      type.hashCode ^
      constantTimeBytesEquality.hash(x) ^
      constantTimeBytesEquality.hash(y);

  @override
  bool operator ==(other) {
    if (!(other is EcKeyPairData &&
        constantTimeBytesEquality.equals(x, other.x) &&
        constantTimeBytesEquality.equals(y, other.y) &&
        type == other.type)) {
      return false;
    }
    if (hasBeenDestroyed) {
      return other.hasBeenDestroyed;
    }
    if (other.hasBeenDestroyed) {
      return false;
    }
    return constantTimeBytesEquality.equals(d, other.d);
  }

  @override
  EcKeyPairData copy() {
    if (hasBeenDestroyed) {
      throw StateError('Private key has been destroyed');
    }
    return EcKeyPairData(
      d: d,
      x: x,
      y: y,
      type: type,
      debugLabel: debugLabel,
    );
  }

  @override
  void destroy() {
    super.destroy();
    _d.destroy();
  }

  @override
  Future<EcKeyPairData> extract() async {
    if (hasBeenDestroyed) {
      throw StateError('Private key has been destroyed');
    }
    return this;
  }

  @override
  Future<EcPublicKey> extractPublicKey() async {
    if (hasBeenDestroyed) {
      throw StateError('Private key has been destroyed');
    }
    return publicKey;
  }

  /// Constructs DER encoding of this public key.
  ///
  /// The implementation generates DER encodings identical to those generated by
  /// Apple CryptoKit.
  Uint8List toDer() {
    final config = CupertinoEcDer.get(type);
    final numberLength = config.numberLength;
    final d = _ensureNumberLength(this.d, numberLength, 'd');
    final x = _ensureNumberLength(this.x, numberLength, 'x');
    final y = _ensureNumberLength(this.y, numberLength, 'y');
    return Uint8List.fromList([
      ...config.privateKeyPrefix,
      ...d,
      ...config.privateKeyMiddle,
      ...x,
      ...y,
    ]);
  }

  @override
  String toString() {
    final debugLabel = this.debugLabel;
    if (debugLabel != null) {
      return 'EcKeyPairData(..., type: $type, debugLabel: $debugLabel)';
    }
    return 'EcKeyPairData(..., type: $type)';
  }

  /// Parses DER-encoded EC public key.
  ///
  /// Currently this is implemented only for very specific inputs: those
  /// generated by Apple's CryptoKit. Apple could decide to change their
  /// implementation in future (though it has no reason to). Therefore we would
  /// like to transition to a proper ASN.1 decoder.
  static EcKeyPairData parseDer(Uint8List der, {required KeyPairType type}) {
    // Parsing of CryptoKit generated keys:
    // Unfortunately our current solutions is not future proof. Apple may change
    // the format in the future. We want to transition to a proper ASN.1 decoder.
    final config = CupertinoEcDer.get(type);
    final prefix = config.privateKeyPrefix;
    final middle = config.privateKeyMiddle;
    final numberLength = config.numberLength;
    if (!bytesStartsWith(der, prefix, 0)) {
      assert(() {
        // ONLY IN DEBUG MODE (i.e. assertions enabled).
        // In production, we don't want a parsing error to expose a private key.
        throw UnsupportedError(
          'Apple has changed CryptoKit $type key DER format prefix.\n'
          'Got DER (part of the error message in debug mode only):\n'
          '${hexFromBytes(der)}\n'
          'Expected bytes at index 0:\n'
          '${hexFromBytes(prefix)}\n'
          'Actual bytes at 0:\n'
          '${hexFromBytes(der.sublist(0, min(der.length, prefix.length)))}\n',
        );
      }());
      throw UnsupportedError(
        'Your version of package:cryptography supports only specific DER encodings from Apple CryptoKit',
      );
    }
    final middleIndex = prefix.length + numberLength;
    if (!bytesStartsWith(der, middle, middleIndex)) {
      assert(() {
        // ONLY IN DEBUG MODE (i.e. assertions enabled).
        // In production, we don't want a parsing error to expose a private key.
        throw UnsupportedError(
          'Apple has changed CryptoKit $type key DER format middle part.\n'
          'Got DER:\n'
          '${hexFromBytes(der)}\n'
          'Expected bytes at $middleIndex (part of the error message in debug mode only):\n'
          '${hexFromBytes(middle)}\n'
          'Actual bytes at $middleIndex:\n'
          '${hexFromBytes(der.sublist(middleIndex, min(der.length, middleIndex + 12)))}\n',
        );
      }());
      throw UnsupportedError(
        'Your version of package:cryptography supports only specific DER encodings from Apple CryptoKit',
      );
    }
    final dIndex = prefix.length;
    final xIndex = middleIndex + middle.length;
    final yIndex = xIndex + numberLength;
    if (der.length != yIndex + numberLength) {
      throw ArgumentError(
        'Apple has changed CryptoKit $type key DER pattern. DER length should be ${yIndex + numberLength}, not ${der.length}',
      );
    }
    return EcKeyPairData(
      d: Uint8List.fromList(der.sublist(dIndex, dIndex + numberLength)),
      x: Uint8List.fromList(der.sublist(xIndex, xIndex + numberLength)),
      y: Uint8List.fromList(der.sublist(yIndex, yIndex + numberLength)),
      type: type,
    );
  }

  static List<int> _ensureNumberLength(
      List<int> bytes, int length, String name) {
    if (bytes.length == length) {
      return bytes;
    }
    if (bytes.length == 65 && length == 66) {
      final result = Uint8List(66);
      for (var i = 0; i < bytes.length; i++) {
        result[i + 1] = bytes[i];
      }
      return result;
    }
    throw StateError(
      'Parameter "$name" should have $length bytes, not ${bytes.length}',
    );
  }
}

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:pusher_reverb_flutter/pusher_reverb_flutter.dart';

import 'reverb_client_test.mocks.dart';

/// The first reconnect waits 2^1 seconds.
const _firstReconnectDelay = Duration(seconds: 2);
const _afterFirstReconnect = Duration(milliseconds: 2300);

/// One socket the client opened.
class _Socket {
  _Socket() {
    when(channel.stream).thenAnswer((_) => frames.stream);
    when(channel.sink).thenReturn(sink);
  }

  final channel = MockWebSocketChannel();
  final sink = MockWebSocketSink();
  final frames = StreamController<dynamic>.broadcast();
}

void main() {
  late List<_Socket> sockets;
  late ReverbClient client;

  setUp(() {
    sockets = [];
    client = ReverbClient.forTesting(
      host: 'localhost',
      port: 8080,
      appKey: 'app-key',
      channelFactory: (_) {
        final socket = _Socket();
        sockets.add(socket);
        return socket.channel;
      },
    );
  });

  tearDown(() {
    for (final socket in sockets) {
      socket.frames.close();
    }
  });

  test('connect closes the socket opened before', () async {
    await client.connect();
    await client.connect();

    expect(sockets, hasLength(2));
    verify(sockets.first.sink.close()).called(1);
    verifyNever(sockets.last.sink.close());
  });

  test('a reconnect scheduled before disconnect does not open a socket',
      () async {
    await client.connect();
    await sockets.single.frames.close();
    await pumpEventQueue();

    client.disconnect();
    await Future<void>.delayed(_afterFirstReconnect);

    expect(sockets, hasLength(1));
    expect(client.connectionState, ConnectionState.disconnected);
  });

  test('a connect during a scheduled reconnect replaces it', () async {
    await client.connect();
    await sockets.single.frames.close();
    await pumpEventQueue();

    await client.connect();
    await Future<void>.delayed(_afterFirstReconnect);

    expect(sockets, hasLength(2));
    verifyNever(sockets.last.sink.close());
  });

  test('reconnects by itself after the socket closes', () async {
    await client.connect();
    await sockets.single.frames.close();
    await pumpEventQueue();

    await Future<void>.delayed(_firstReconnectDelay * 1.15);

    expect(sockets, hasLength(2));
  });
}

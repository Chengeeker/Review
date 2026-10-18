import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:easy_refresh/easy_refresh.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:review/core/network/weibo_dio_client.dart';
import 'package:review/core/storage/storage_service.dart';
import 'package:review/features/drawer_features/presentation/chat_conversation_page.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _ChatAdapter implements HttpClientAdapter {
  _ChatAdapter({
    required this.isGroup,
    this.accept = true,
    this.readBack = true,
    this.sendStatus = 200,
  });

  final bool isGroup;
  final bool accept;
  final bool readBack;
  final int sendStatus;
  Completer<void>? sendReady;
  Map<String, String>? sentForm;
  RequestOptions? sendRequest;
  int sends = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    Object data = {};
    if (options.method == 'POST') {
      sends++;
      sendRequest = options;
      final bytes = <int>[];
      if (requestStream != null) {
        await for (final chunk in requestStream) {
          bytes.addAll(chunk);
        }
      }
      sentForm = Uri.splitQueryString(utf8.decode(bytes));
      await sendReady?.future;
      data = accept
          ? {if (isGroup) 'mid': '900' else 'id': '900'}
          : {'error': '对方设置了私信权限', 'error_code': 20331};
    } else if (options.path.endsWith('conversation.json') ||
        options.path.endsWith('query_messages.json')) {
      final cursor = options.queryParameters[isGroup ? 'max_mid' : 'max_id'];
      data = {
        isGroup ? 'messages' : 'direct_messages': [
          if ((cursor == null || cursor == '0') &&
              accept &&
              readBack &&
              sentForm != null)
            {
              'idstr': '900',
              'mid': '900',
              'from_uid': '42',
              'sender_id': '42',
              'text': sentForm![isGroup ? 'content' : 'text'],
              'time': DateTime.now().millisecondsSinceEpoch ~/ 1000,
            },
        ],
      };
    }
    return ResponseBody.fromString(
      jsonEncode(data),
      options.method == 'POST' ? sendStatus : 200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Future<void> _mount(WidgetTester tester, _ChatAdapter adapter) async {
  SharedPreferences.setMockInitialValues({
    StorageService.keyIsLoggedIn: true,
    StorageService.keyFullCookie: 'SUB=test-session; XSRF-TOKEN=test-xsrf',
    StorageService.keyUserUid: '42',
    StorageService.keyUserNickname: '我',
  });
  final storage = StorageService(await SharedPreferences.getInstance());
  final client = WeiboDioClient(storage)..dio.httpClientAdapter = adapter;
  addTearDown(() => client.dio.close(force: true));
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        storageServiceProvider.overrideWithValue(storage),
        weiboDioClientProvider.overrideWithValue(client),
      ],
      child: MaterialApp(
        home: ChatConversationPage(
          targetId: '123',
          targetName: '测试会话',
          targetAvatar: '',
          isGroup: adapter.isGroup,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<void> _finish(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 3));
  await tester.pumpAndSettle();
  await tester.pumpWidget(const SizedBox.shrink());
}

void main() {
  for (final isGroup in [false, true]) {
    for (final accept in [false, true]) {
      testWidgets('WebIM form send group=$isGroup accept=$accept', (
        tester,
      ) async {
        final adapter = _ChatAdapter(isGroup: isGroup, accept: accept);
        await _mount(tester, adapter);
        const text = '测试 & +\n👌';
        await tester.enterText(find.byType(TextField), text);
        await tester.tap(find.byIcon(Icons.send_rounded));
        await tester.pumpAndSettle();
        expect(adapter.sends, 1);
        expect(
          adapter.sendRequest!.path.endsWith(
            isGroup
                ? '/groupchat/send_message.json'
                : '/direct_messages/new.json',
          ),
          isTrue,
        );
        expect(
          adapter.sendRequest!.contentType,
          startsWith(Headers.formUrlEncodedContentType),
        );
        expect(
          adapter.sendRequest!.headers['Referer'],
          'https://api.weibo.com/chat/',
        );
        expect(adapter.sendRequest!.headers['X-XSRF-TOKEN'], 'test-xsrf');
        expect(adapter.sentForm![isGroup ? 'id' : 'uid'], '123');
        expect(adapter.sentForm![isGroup ? 'content' : 'text'], text);
        expect(adapter.sentForm!['source'], '209678993');
        expect(adapter.sentForm!['is_encoded'], '0');
        final annotations = jsonDecode(
          adapter.sentForm![isGroup ? 'annotations' : 'extensions']!,
        );
        expect(annotations['clientid'], '');
        if (isGroup) {
          expect(annotations['webchat'], 1);
          expect(adapter.sentForm!['media_type'], '0');
        } else {
          expect(adapter.sentForm!['decodetime'], '1');
        }
        final input = tester.widget<TextField>(find.byType(TextField));
        expect(input.controller!.text, accept ? '' : text);
        expect(
          find.byKey(const ValueKey('chat-message-content-900')),
          accept ? findsOneWidget : findsNothing,
        );
        if (!accept) {
          expect(find.text('发送失败：对方设置了私信权限（20331）'), findsOneWidget);
        }
        expect(find.byType(EasyRefresh), findsNothing);
        expect(tester.takeException(), isNull);
        await _finish(tester);
      });
    }
  }

  testWidgets('HTTP failure preserves the draft and is not resent', (
    tester,
  ) async {
    final adapter = _ChatAdapter(isGroup: false, sendStatus: 500);
    await _mount(tester, adapter);
    await tester.enterText(find.byType(TextField), '保留这条草稿');
    await tester.tap(find.byIcon(Icons.send_rounded));
    await tester.pumpAndSettle();
    expect(adapter.sends, 1);
    expect(find.text('发送请求失败（HTTP 500），内容已保留'), findsOneWidget);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '保留这条草稿',
    );
    expect(
      find.byKey(const ValueKey('chat-message-content-900')),
      findsNothing,
    );
    await _finish(tester);
  });

  testWidgets(
    'accepted request without readback does not invent an outgoing bubble',
    (tester) async {
      final adapter = _ChatAdapter(isGroup: true, readBack: false);
      await _mount(tester, adapter);
      await tester.enterText(find.byType(TextField), '待核实消息');
      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.pumpAndSettle();
      expect(adapter.sends, 1);
      expect(
        find.byKey(const ValueKey('chat-message-content-900')),
        findsNothing,
      );
      expect(find.textContaining('服务器暂未回读到消息'), findsOneWidget);
      await _finish(tester);
    },
  );

  testWidgets(
    'a new draft typed during sending survives the confirmed response',
    (tester) async {
      final adapter = _ChatAdapter(isGroup: false)
        ..sendReady = Completer<void>();
      await _mount(tester, adapter);
      await tester.enterText(find.byType(TextField), '第一条消息');
      await tester.tap(find.byIcon(Icons.send_rounded));
      await tester.pump();
      await tester.enterText(find.byType(TextField), '下一条草稿');
      adapter.sendReady!.complete();
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        '下一条草稿',
      );
      expect(
        find.byKey(const ValueKey('chat-message-content-900')),
        findsOneWidget,
      );
      expect(adapter.sends, 1);
      await _finish(tester);
    },
  );
}

import 'package:grimreach_server/net/websocket_server.dart';

void main() async {
  final server = WebsocketServer(port: 8080);
  await server.start();
}

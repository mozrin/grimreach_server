import 'dart:io';
import 'client_session.dart';

class WebsocketServer {
  final int port;
  final List<ClientSession> sessions = [];

  WebsocketServer({required this.port});

  Future<void> start() async {
    final httpServer = await HttpServer.bind(InternetAddress.anyIPv4, port);
    print("Server running on port $port");

    await for (HttpRequest req in httpServer) {
      if (req.uri.path == '/ws') {
        final socket = await WebSocketTransformer.upgrade(req);
        final session = ClientSession(socket);
        sessions.add(session);
        print('Server: Client connected');
      } else {
        req.response.statusCode = HttpStatus.notFound;
        await req.response.close();
      }
    }
  }
}

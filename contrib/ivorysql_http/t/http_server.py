"""Loopback-only, deterministic HTTP/HTTPS fixture; no external services."""
import http.server
from pathlib import Path
import ssl
import sys
import time


class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'

    def log_message(self, *args):
        pass

    def do_GET(self):
        if self.path == '/slow':
            time.sleep(3)
        if self.path == '/large':
            data = b'x' * (2 * 1024 * 1024)
        elif self.path in ('/latin', '/latin-spaced'):
            data = b'\xc3\xa9'
        elif self.path == '/empty':
            data = b''
        else:
            data = '你好，IvorySQL🌍'.encode()
        self.send_response(302 if self.path == '/redirect' else 404 if self.path == '/missing' else 200)
        content_type = 'text/plain; charset=UTF-8'
        if self.path == '/latin':
            content_type = 'text/plain; charset=ISO-8859-1'
        elif self.path == '/latin-spaced':
            content_type = 'text/plain; charset = "ISO-8859-1"'
        elif self.path == '/utf8-spaced':
            content_type = 'text/plain; ignored="a; charset=latin1"; charset = "UTF-8"'
        self.send_header('Content-Type', content_type)
        self.send_header('X-Fixture', 'ivorysql')
        if self.path == '/redirect':
            self.send_header('Location', 'http://127.0.0.1:1/never-follow')
        if self.path == '/chunk':
            self.send_header('Transfer-Encoding', 'chunked')
            self.end_headers()
            # Deliberately split a UTF-8 character between network chunks.
            for part in (data[:1], data[1:4], data[4:]):
                self.wfile.write(f'{len(part):x}\r\n'.encode() + part + b'\r\n')
            self.wfile.write(b'0\r\n\r\n')
        else:
            self.send_header('Content-Length', str(len(data)))
            self.end_headers()
            try:
                self.wfile.write(data)
            except (BrokenPipeError, ConnectionResetError, ssl.SSLError):
                pass

    def do_POST(self):
        data = self.rfile.read(int(self.headers.get('Content-Length', '0')))
        self.send_response(201)
        self.send_header('Content-Type', 'text/plain; charset=UTF-8')
        self.send_header('X-Echo', self.headers.get('X-Test', ''))
        self.send_header('Content-Length', str(len(data)))
        self.end_headers()
        self.wfile.write(data)


class Server(http.server.ThreadingHTTPServer):
    daemon_threads = True

    def handle_error(self, *args):
        pass


server = Server(('127.0.0.1', 0), Handler)
if len(sys.argv) > 2:
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.load_cert_chain(sys.argv[2], sys.argv[3])
    server.socket = context.wrap_socket(server.socket, server_side=True)
Path(sys.argv[1]).write_text(str(server.server_port))
server.serve_forever()

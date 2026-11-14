"""Cliente umqtt.simple transportado por WebSocket (MicroPython)."""

try:
    import usocket as socket
except ImportError:
    import socket

try:
    import ustruct as struct
except ImportError:
    import struct

try:
    import urandom
except ImportError:
    urandom = None

import time

from umqtt.simple import MQTTClient, MQTTException


class WebSocketStream:
    """Adapta quadros WebSocket binarios para a interface de stream do umqtt."""

    def __init__(self, host, port, path="/mqtt", use_tls=False, timeout=12):
        self.host = host
        self.port = port
        self.path = path if path.startswith("/") else "/" + path
        self.use_tls = use_tls
        self.sock = socket.socket()
        self.sock.settimeout(timeout)
        address = socket.getaddrinfo(host, port)[0][-1]
        try:
            self.sock.connect(address)
            self._setup(host, use_tls, timeout)
        except Exception:
            self.sock.close()
            raise

    def _setup(self, host, use_tls, timeout):
        if use_tls:
            try:
                import ssl
            except ImportError:
                import ussl as ssl
            self.sock = ssl.wrap_socket(self.sock, server_hostname=host)
            self.sock.settimeout(timeout)
        self._network_buffer = bytearray()
        self._payload_buffer = bytearray()
        self._blocking = True
        self._handshake()

    def _recv(self, size):
        # read(n) no MicroPython espera n bytes; recv devolve o que chegou.
        if hasattr(self.sock, "recv"):
            return self.sock.recv(size)
        return self.sock.read(size)

    def _send_all(self, data):
        sent = 0
        while sent < len(data):
            count = self.sock.write(data[sent:])
            if not count:
                raise OSError("WebSocket desconectado durante envio")
            sent += count

    def _handshake(self):
        key = "dGhlIHNhbXBsZSBub25jZQ=="
        request = (
            "GET %s HTTP/1.1\r\n"
            "Host: %s:%d\r\n"
            "Origin: http%s://%s\r\n"
            "Upgrade: websocket\r\n"
            "Connection: Upgrade\r\n"
            "Sec-WebSocket-Key: %s\r\n"
            "Sec-WebSocket-Version: 13\r\n"
            "Sec-WebSocket-Protocol: mqtt\r\n\r\n"
        ) % (
            self.path,
            self.host,
            self.port,
            "s" if self.use_tls else "",
            self.host,
            key,
        )
        self._send_all(request.encode())

        response = bytearray()
        while b"\r\n\r\n" not in response:
            chunk = self._recv(256)
            if not chunk:
                raise OSError("Broker encerrou o handshake WebSocket")
            response.extend(chunk)
            if len(response) > 4096:
                raise OSError("Resposta WebSocket excedeu o limite")

        header, remainder = bytes(response).split(b"\r\n\r\n", 1)
        first_line = header.split(b"\r\n", 1)[0]
        if b" 101 " not in first_line:
            raise OSError("Handshake WebSocket recusado: " + first_line.decode())
        lower_header = header.lower()
        if b"sec-websocket-protocol: mqtt" not in lower_header:
            raise OSError("Broker nao confirmou o subprotocolo MQTT")
        self._network_buffer.extend(remainder)
        self.sock.settimeout(None)

    def _mask(self):
        if urandom and hasattr(urandom, "getrandbits"):
            value = urandom.getrandbits(32)
        else:
            value = time.ticks_ms() & 0xFFFFFFFF
        return struct.pack("!I", value)

    def _send_frame(self, payload, opcode=0x2):
        length = len(payload)
        header = bytearray([0x80 | opcode])
        if length <= 125:
            header.append(0x80 | length)
        elif length <= 65535:
            header.extend((0xFE, (length >> 8) & 0xFF, length & 0xFF))
        else:
            header.append(0xFF)
            header.extend(struct.pack("!Q", length))
        mask = self._mask()
        masked = bytearray(payload)
        for index in range(length):
            masked[index] ^= mask[index & 3]
        self._send_all(header + mask + masked)

    def write(self, data, length=None):
        if length is not None:
            data = data[:length]
        if isinstance(data, str):
            data = data.encode()
        self._send_frame(data)
        return len(data)

    def _read_from_network(self):
        try:
            chunk = self._recv(512)
        except OSError as exc:
            if not self._blocking and exc.args and exc.args[0] in (11, 110, 116):
                return False
            raise
        if chunk is None:
            return False
        if chunk == b"":
            raise OSError("WebSocket desconectado")
        self._network_buffer.extend(chunk)
        return True

    def _decode_frame(self):
        data = self._network_buffer
        if len(data) < 2:
            return False
        first, second = data[0], data[1]
        opcode = first & 0x0F
        masked = bool(second & 0x80)
        length = second & 0x7F
        offset = 2
        if length == 126:
            if len(data) < 4:
                return False
            length = (data[2] << 8) | data[3]
            offset = 4
        elif length == 127:
            if len(data) < 10:
                return False
            length = 0
            for value in data[2:10]:
                length = (length << 8) | value
            offset = 10
        mask = None
        if masked:
            if len(data) < offset + 4:
                return False
            mask = data[offset:offset + 4]
            offset += 4
        end = offset + length
        if len(data) < end:
            return False
        payload = bytearray(data[offset:end])
        self._network_buffer = data[end:]
        if mask:
            for index in range(length):
                payload[index] ^= mask[index & 3]

        if opcode in (0x0, 0x2):
            self._payload_buffer.extend(payload)
        elif opcode == 0x8:
            raise OSError("Broker fechou o WebSocket")
        elif opcode == 0x9:
            self._send_frame(payload, opcode=0xA)
        return True

    def read(self, size=1):
        while len(self._payload_buffer) < size:
            while self._decode_frame():
                if len(self._payload_buffer) >= size:
                    break
            if len(self._payload_buffer) >= size:
                break
            if not self._read_from_network():
                return None
        result = bytes(self._payload_buffer[:size])
        self._payload_buffer = self._payload_buffer[size:]
        return result

    def setblocking(self, enabled):
        self._blocking = enabled
        self.sock.setblocking(enabled)

    def close(self):
        try:
            self._send_frame(b"", opcode=0x8)
        except Exception:
            pass
        self.sock.close()


class WebSocketMQTTClient(MQTTClient):
    """MQTTClient compativel com a API umqtt.simple usando WebSocket."""

    def __init__(self, client_id, server, port=8080, path="/mqtt",
                 use_tls=False, user=None, password=None, keepalive=0):
        super().__init__(client_id, server, port=port, user=user,
                         password=password, keepalive=keepalive)
        self.websocket_path = path
        self.websocket_tls = use_tls

    def connect(self, clean_session=True):
        self.sock = WebSocketStream(
            self.server,
            self.port,
            path=self.websocket_path,
            use_tls=self.websocket_tls,
        )
        premsg = bytearray(b"\x10\0\0\0\0\0")
        msg = bytearray(b"\x04MQTT\x04\x02\0\0")
        size = 10 + 2 + len(self.client_id)
        msg[6] = clean_session << 1
        if self.user is not None:
            size += 2 + len(self.user) + 2 + len(self.pswd)
            msg[6] |= 0xC0
        if self.keepalive:
            if self.keepalive >= 65536:
                raise ValueError("keepalive invalido")
            msg[7] |= self.keepalive >> 8
            msg[8] |= self.keepalive & 0xFF
        if self.lw_topic:
            size += 2 + len(self.lw_topic) + 2 + len(self.lw_msg)
            msg[6] |= 0x4 | (self.lw_qos & 0x1) << 3 | (self.lw_qos & 0x2) << 3
            msg[6] |= self.lw_retain << 5

        index = 1
        remaining = size
        while remaining > 0x7F:
            premsg[index] = (remaining & 0x7F) | 0x80
            remaining >>= 7
            index += 1
        premsg[index] = remaining
        self.sock.write(premsg, index + 2)
        self.sock.write(msg)
        self._send_str(self.client_id)
        if self.lw_topic:
            self._send_str(self.lw_topic)
            self._send_str(self.lw_msg)
        if self.user is not None:
            self._send_str(self.user)
            self._send_str(self.pswd)

        response = self.sock.read(4)
        if not response or len(response) != 4:
            raise OSError("Resposta MQTT incompleta via WebSocket")
        if response[0] != 0x20 or response[1] != 0x02:
            raise OSError("Resposta CONNACK MQTT invalida")
        if response[3] != 0:
            raise MQTTException(response[3])
        return response[2] & 1

import socket
import time

server = socket.socket()
server.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
server.bind(("0.0.0.0", 8000))
# Backlog 1 + no accept() loop: TCP SYN queue fills quickly, additional callers will hit connectionTimeoutInSeconds.
server.listen(1)
while True:
    time.sleep(3600)

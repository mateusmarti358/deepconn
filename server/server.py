import socket
import threading

import eventQueue
from eventQueue import evQueue

import eventListener
from eventListener import handle_messages

import user
from user import users

import client
from client import handle_client

PORT = 8080

def tcp_server(server_socket):
    server_socket.bind(('::', PORT, 0, 0))

    print('Server started on %s:%d' % (socket.gethostbyname(socket.gethostname()), PORT))

    server_socket.listen()

    while True:
        client_socket, client_address = server_socket.accept()
        print('Connection from %s:%d' % (client_address[0], client_address[1]))
        threading.Thread(target=handle_client, args=(client_socket,), daemon=True).start()

if __name__ == '__main__':
    server_socket = socket.socket(socket.AF_INET6, socket.SOCK_STREAM)
    threading.Thread(target=tcp_server, args=(server_socket,), daemon=True).start()
    threading.Thread(target=handle_messages, daemon=True).start()

    while True:
        try:
            inmsg = input()
            if inmsg == 'exit':
                break
            if inmsg == 'users':
                print(users.users)
        except KeyboardInterrupt:
            break
    
    print('Closing server...')
    server_socket.close()
